#if os(iOS)
import SwiftUI

/// A complete native board, including navigation. Present directly in a sheet or as a screen.
@MainActor public struct KunioFeedbackBoard: View {
    @State private var model = FeedbackBoardModel()
    @State private var showStatusFilter = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    public init() {}
    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let board = model.board {
                        HStack(alignment: .top, spacing: 14) {
                            if let url = board.iconURL {
                                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.1) }
                                    .frame(width: 44, height: 44).clipShape(.rect(cornerRadius: 12)).accessibilityHidden(true)
                            }
                            VStack(alignment: .leading, spacing: 5) { Text(board.name).font(.headline); Text(board.intro).font(.subheadline).foregroundStyle(.secondary) }
                            Spacer(minLength: 0)
                        }
                        Picker(feedbackText("Sort wishes"), selection: $model.segment) {
                            ForEach(FeedbackBoardModel.Segment.allCases, id: \.self) { segment in Text(segment.title).tag(segment) }
                        }.pickerStyle(.segmented)
                    }
                    if let notice = model.notice {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(notice).font(.subheadline); Spacer(minLength: 0)
                            Button { model.notice = nil } label: { Image(systemName: "xmark").font(.caption.bold()).frame(minWidth: 24, minHeight: 24) }
                                .accessibilityLabel(feedbackText("Dismiss message")).buttonStyle(.plain)
                        }.padding(16).background(.green.opacity(0.08), in: .rect(cornerRadius: 16))
                    }
                    if let error = model.error {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(error, systemImage: "exclamationmark.circle").font(.subheadline)
                            Button(feedbackText("Try again")) { Task { await model.refresh() } }.font(.subheadline.weight(.semibold))
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
                    }
                    if model.isLoading && model.wishes.isEmpty {
                        ProgressView(feedbackText("Loading wishes…")).frame(maxWidth: .infinity).padding(.vertical, 70)
                    } else if model.wishes.isEmpty && model.error == nil {
                        ContentUnavailableView {
                            Label(feedbackText(model.search.isEmpty ? "What should we build next?" : "No matching wishes"), systemImage: "bubble.left.and.bubble.right")
                        } description: { Text(feedbackText(model.search.isEmpty ? "Share an idea or vote for a feature you would love to see." : "Try another search or suggest a new feature.")) }
                        actions: {
                            Button { model.submissionError = nil; model.showComposer = true } label: {
                                Text(feedbackText("Suggest a feature"))
                                    .font(.headline)
                                    .frame(minWidth: 220, minHeight: 28)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .buttonBorderShape(.capsule)
                            .disabled(model.board == nil || model.paused)
                        }
                        .padding(.vertical, 28)
                    }
                    ForEach(model.wishes) { wish in WishRow(wish: wish, model: model) }
                    if model.nextOffset != nil {
                        Button { Task { await model.more() } } label: {
                            if model.isLoadingMore { ProgressView() } else { Text(feedbackText("Load more wishes")) }
                        }.buttonStyle(.bordered).frame(maxWidth: .infinity).padding(.vertical, 8).disabled(model.isLoadingMore)
                    }
                }.padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(feedbackText("Feature wishes")).navigationBarTitleDisplayMode(.large)
            .searchable(text: $model.search, prompt: Text(feedbackText("Search wishes")))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").fontWeight(.semibold) }
                        .accessibilityLabel(feedbackText("Close board"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showStatusFilter = true } label: {
                        Label(feedbackText("Filter status"), systemImage: model.status == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel(feedbackText("Filter status"))
                    .accessibilityValue(model.status?.title ?? feedbackText("All statuses"))
                    .confirmationDialog(feedbackText("Filter status"), isPresented: $showStatusFilter, titleVisibility: .visible) {
                        Button(feedbackText("All statuses")) { model.status = nil }
                        ForEach(WishStatus.allCases, id: \.self) { status in
                            Button(status.title) { model.status = status }
                        }
                        Button(feedbackText("Cancel"), role: .cancel) { }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.submissionError = nil; model.showComposer = true } label: { Image(systemName: "plus").fontWeight(.semibold) }
                        .accessibilityLabel(feedbackText("Suggest a feature")).disabled(model.board == nil || model.paused)
                }
            }
            .refreshable { await model.refresh() }
            .task(id: model.filterKey) { do { try await Task.sleep(for: .milliseconds(250)); try Task.checkCancellation(); await model.refresh() } catch { } }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refresh() } } }
            .navigationDestination(for: String.self) { id in WishDetails(id: id, model: model) }
            .sheet(isPresented: $model.showComposer) { ComposeWish(model: model) }
        }
    }
}
@MainActor private struct WishRow: View {
    let wish: FeatureWish
    let model: FeedbackBoardModel
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            NavigationLink(value: wish.id) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(wish.title).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    if !wish.body.isEmpty { Text(wish.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading) }
                    WishStatusBadge(wish: wish)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
            }.buttonStyle(.plain)
            VoteControl(wish: wish, model: model)
        }.padding(18).background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }
}
@MainActor private struct VoteControl: View {
    let wish: FeatureWish
    let model: FeedbackBoardModel
    var body: some View {
        Button { Task { await model.vote(wish) } } label: {
            VStack(spacing: 5) {
                if model.voting.contains(wish.id) { ProgressView().controlSize(.mini) }
                else { Image(systemName: wish.hasVoted ? "chevron.up.circle.fill" : "chevron.up").font(.subheadline.weight(.semibold)) }
                Text(wish.voteCount, format: .number).font(.subheadline.weight(.semibold)).monospacedDigit()
            }.frame(minWidth: 44, minHeight: 52).padding(.horizontal, 5)
        }.buttonStyle(.plain)
        .foregroundStyle(wish.hasVoted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .background(wish.hasVoted ? Color.accentColor.opacity(0.1) : Color(uiColor: .tertiarySystemGroupedBackground), in: .rect(cornerRadius: 13))
        .disabled(model.voting.contains(wish.id) || model.paused)
        .accessibilityLabel(feedbackText(wish.hasVoted ? "Remove vote" : "Vote for this wish"))
        .accessibilityValue(String(wish.voteCount))
        .sensoryFeedback(.selection, trigger: wish.hasVoted)
    }
}
private struct WishStatusBadge: View {
    let wish: FeatureWish
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(wish.visibility == .pending ? .orange : wish.status == .done ? .green : .secondary).frame(width: 5, height: 5)
            Text(wish.visibility == .pending ? feedbackText("Awaiting review · Only visible to you") : wish.status.title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}
@MainActor private struct WishDetails: View {
    let id: String
    let model: FeedbackBoardModel
    var body: some View {
        ScrollView {
            if let wish = model.wishes.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 24) {
                    WishStatusBadge(wish: wish); Text(wish.title).font(.title.bold()).textSelection(.enabled)
                    if !wish.body.isEmpty { Text(wish.body).font(.body).foregroundStyle(.secondary).textSelection(.enabled) }
                    HStack {
                        Label(wish.createdAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
                        Spacer(); VoteControl(wish: wish, model: model)
                    }
                    if let error = model.error { Text(error).font(.subheadline).foregroundStyle(.secondary) }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            } else { ContentUnavailableView(feedbackText("This wish is no longer available."), systemImage: "bubble.left") }
        }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle(feedbackText("Feature wish")).navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.refresh() }
    }
}
@MainActor private struct ComposeWish: View {
    @Bindable var model: FeedbackBoardModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(feedbackText("What would you like to see?"), text: $model.draftTitle, axis: .vertical).font(.headline).lineLimit(1...3).focused($titleFocused)
                    TextField(feedbackText("Describe the problem this would solve (optional)"), text: $model.draftBody, axis: .vertical).lineLimit(5...10).font(.body)
                } footer: { Text(feedbackText("Your wish is reviewed before it becomes visible to others. Please keep personal information out of your suggestion.")) }
                if model.draftTitle.utf16.count > 120 || model.draftBody.utf16.count > 4000 {
                    Text(feedbackText("Use a title between 3 and 120 characters and a description up to 4,000 characters.")).font(.footnote).foregroundStyle(.red)
                }
                if model.similarLoading { Section { ProgressView(feedbackText("Finding similar wishes…")) } }
                if !model.similar.isEmpty {
                    Section {
                        ForEach(model.similar) { wish in
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) { Text(wish.title).font(.subheadline.weight(.semibold)); Text(wish.status.title).font(.caption).foregroundStyle(.secondary) }
                                Spacer(); VoteControl(wish: wish, model: model)
                            }.padding(.vertical, 5)
                        }
                    } header: { Text(feedbackText("Already on the board")) }
                    footer: { Text(feedbackText("If one of these matches your idea, add your vote instead of creating a duplicate.")) }
                }
                if let error = model.submissionError { Section { Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.red) } }
                if let error = model.error { Section { Text(error).font(.footnote).foregroundStyle(.secondary) } }
            }.navigationTitle(feedbackText("Suggest a feature")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(feedbackText("Cancel")) { dismiss() }.disabled(model.isSubmitting) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await model.submit() } } label: { if model.isSubmitting { ProgressView() } else { Text(feedbackText("Send")).fontWeight(.semibold) } }.disabled(!model.canSubmit)
                }
            }.interactiveDismissDisabled(model.isSubmitting).task { titleFocused = true }
            .task(id: model.draftTitle) { do { try await Task.sleep(for: .milliseconds(350)); try Task.checkCancellation(); await model.findSimilar() } catch { } }
        }
    }
}
#endif
