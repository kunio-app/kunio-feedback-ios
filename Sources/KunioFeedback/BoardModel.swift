#if os(iOS)
import Foundation
import Observation

@MainActor @Observable final class FeedbackBoardModel {
    enum Segment: String, CaseIterable { case popular, new, mine
        var title: String { feedbackText(self == .popular ? "Popular" : self == .new ? "New" : "My wishes") }
    }
    var board: FeedbackBoard?
    var wishes: [FeatureWish] = []
    var segment = Segment.popular
    var status: WishStatus?
    var search = ""
    var error: String?
    var submissionError: String?
    var notice: String?
    var isLoading = false
    var isLoadingMore = false
    var isSubmitting = false
    var paused = false
    var voting: Set<String> = []
    var showComposer = false
    var draftTitle = ""
    var draftBody = ""
    var similar: [FeatureWish] = []
    var similarLoading = false
    var nextOffset: Int?
    private var client: KunioFeedbackClient?
    private var ticket = 0
    private var similarTicket = 0
    private var draftID = UUID()
    private var lastSubmittedDraft = ""
    var filterKey: String { segment.rawValue + ":" + (status?.rawValue ?? "all") + ":" + search }
    var canSubmit: Bool { (3...120).contains(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count) && draftBody.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= 4000 && !isSubmitting && !paused }
    private func api() throws -> KunioFeedbackClient {
        if let client { return client }
        guard let configured = KunioFeedback.client else { throw KunioFeedback.configurationError ?? KunioFeedbackError.notConfigured }
        client = configured; return configured
    }
    func refresh() async {
        ticket += 1; let current = ticket; isLoading = true
        defer { if ticket == current { isLoading = false } }
        do {
            let result = try await api().list(search: search.trimmingCharacters(in: .whitespacesAndNewlines), sort: segment == .new ? .new : .popular, mine: segment == .mine, status: status)
            guard ticket == current, !Task.isCancelled else { return }
            board = result.board; wishes = result.requests; nextOffset = result.nextOffset; error = nil; paused = false
        } catch is CancellationError { }
        catch {
            guard ticket == current else { return }; self.error = error.localizedDescription
            if case KunioFeedbackError.server("feedback_board_paused") = error { paused = true }
        }
    }
    func more() async {
        guard let nextOffset, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true; let current = ticket; defer { isLoadingMore = false }
        do {
            let result = try await api().list(search: search.trimmingCharacters(in: .whitespacesAndNewlines), sort: segment == .new ? .new : .popular, mine: segment == .mine, status: status, offset: nextOffset)
            guard ticket == current else { return }; var ids = Set(wishes.map(\.id))
            wishes += result.requests.filter { ids.insert($0.id).inserted }; self.nextOffset = result.nextOffset
        } catch { if ticket == current { self.error = error.localizedDescription } }
    }
    func vote(_ wish: FeatureWish) async {
        guard !voting.contains(wish.id), !paused else { return }; voting.insert(wish.id); defer { voting.remove(wish.id) }
        do {
            let updated = try await api().setVote(wishID: wish.id, voted: !wish.hasVoted)
            if let i = wishes.firstIndex(where: { $0.id == wish.id }) { wishes[i] = updated }
            if let i = similar.firstIndex(where: { $0.id == wish.id }) { similar[i] = updated }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func findSimilar() async {
        similarTicket += 1; let current = similarTicket; let query = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { if current == similarTicket { similarLoading = false } }
        guard query.utf16.count >= 3 else { similar = []; similarLoading = false; return }; similarLoading = true
        do {
            let result = try await api().list(search: String(query.prefix(120)))
            guard current == similarTicket, !Task.isCancelled else { return }
            similar = Array(result.requests.filter { $0.visibility == .published }.prefix(3))
        } catch { if current == similarTicket { similar = [] } }
    }
    func submit() async {
        guard canSubmit else { return }; isSubmitting = true; submissionError = nil; defer { isSubmitting = false }
        let signature = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines) + "\u{0}" + draftBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if !lastSubmittedDraft.isEmpty && signature != lastSubmittedDraft { draftID = UUID() }; lastSubmittedDraft = signature
        do {
            let wish = try await api().submit(title: draftTitle, description: draftBody, requestID: draftID)
            wishes.removeAll { $0.id == wish.id }; wishes.insert(wish, at: 0)
            draftTitle = ""; draftBody = ""; draftID = UUID(); lastSubmittedDraft = ""; similar = []
            segment = .mine; status = nil; search = ""; showComposer = false
            notice = feedbackText("Wish sent. It is visible to you and will appear on the board after approval.")
            await refresh()
        } catch { submissionError = error.localizedDescription }
    }
}
#endif
