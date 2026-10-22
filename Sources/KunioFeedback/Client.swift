import Foundation
import CryptoKit

public enum KunioFeedback {
    public static let defaultEndpoint = URL(string: "https://hztohpliexkhpvyugfpu.supabase.co/functions/v1/feedback-public")!
    @MainActor static var client: KunioFeedbackClient?
    @MainActor static var configurationError: KunioFeedbackError?
    /// Call once from your App initializer. The board key is public and may ship in the app.
    @MainActor public static func configure(boardKey: String, endpoint: URL = defaultEndpoint) {
        do {
            client = try KunioFeedbackClient(boardKey: boardKey, endpoint: endpoint)
            configurationError = nil
        } catch {
            client = nil
            configurationError = .invalidConfiguration
        }
    }
}
private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
public actor KunioFeedbackClient {
    private let boardKey: String
    private let endpoint: URL
    private let session: URLSession
    private let credentials: any FeedbackCredentialStore
    private let account: String
    private var token: String?
    private var sessionTask: Task<String, Error>?
    public init(boardKey: String, endpoint: URL = KunioFeedback.defaultEndpoint) throws {
        try self.init(boardKey: boardKey, endpoint: endpoint, session: Self.makeSession(), credentials: KeychainCredentialStore())
    }
    init(boardKey: String, endpoint: URL, session: URLSession, credentials: any FeedbackCredentialStore) throws {
        guard boardKey.range(of: "^kb_live_[0-9a-f]{48}$", options: .regularExpression) != nil,
              endpoint.scheme == "https", endpoint.host != nil, endpoint.user == nil, endpoint.password == nil,
              endpoint.query == nil, endpoint.fragment == nil else { throw KunioFeedbackError.invalidConfiguration }
        self.boardKey = boardKey; self.endpoint = endpoint; self.session = session; self.credentials = credentials
        self.account = SHA256.hash(data: Data((endpoint.absoluteString + ":" + boardKey).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }
    private struct SessionResponse: Decodable { let participant_token: String }
    private struct WishResponse: Decodable { let request: FeatureWish }
    private struct ErrorResponse: Decodable { let error: String }
    private func newCredential() async throws -> String {
        let response: SessionResponse = try await post(["action": "session"], token: nil)
        guard response.participant_token.range(of: "^kfp_[0-9a-f]{64}$", options: .regularExpression) != nil else { throw KunioFeedbackError.invalidResponse }
        try credentials.save(response.participant_token, account: account)
        token = response.participant_token
        return response.participant_token
    }
    private func access() async throws -> String {
        if let token { return token }
        if let sessionTask { return try await sessionTask.value }
        if let stored = try credentials.load(account: account), stored.range(of: "^kfp_[0-9a-f]{64}$", options: .regularExpression) != nil {
            token = stored; return stored
        }
        let pending = Task { try await newCredential() }
        sessionTask = pending
        defer { sessionTask = nil }
        return try await pending.value
    }
    private func authenticated<T: Decodable>(_ payload: [String: Any]) async throws -> T {
        for attempt in 0...1 {
            let credential = try await access()
            do { return try await post(payload, token: credential) }
            catch KunioFeedbackError.server(let code) where code == "feedback_participant_invalid" && attempt == 0 {
                // This error is returned before any write. Never retry an ambiguous network failure.
                if token == credential { token = nil; try credentials.remove(account: account) }
            }
        }
        throw KunioFeedbackError.server("feedback_participant_invalid")
    }
    private func post<T: Decodable>(_ payload: [String: Any], token: String?) async throws -> T {
        try Task.checkCancellation()
        var body = payload
        body["version"] = 1; body["board_key"] = boardKey
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { if Task.isCancelled { throw CancellationError() }; throw KunioFeedbackError.connectionFailed }
        guard let http = response as? HTTPURLResponse, data.count <= 2_000_000 else { throw KunioFeedbackError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let error = try? JSONDecoder().decode(ErrorResponse.self, from: data) { throw KunioFeedbackError.server(error.error) }
            throw KunioFeedbackError.invalidResponse
        }
        do { return try feedbackDecoder().decode(T.self, from: data) }
        catch { throw KunioFeedbackError.invalidResponse }
    }
    public func list(search: String = "", sort: WishSort = .popular, mine: Bool = false, status: WishStatus? = nil, offset: Int = 0) async throws -> FeedbackPage {
        guard search.utf16.count <= 120, (0...10000).contains(offset) else { throw KunioFeedbackError.server("feedback_invalid") }
        return try await authenticated(["action": "list", "search": search, "sort": sort.rawValue, "mine": mine, "status": status?.rawValue ?? "all", "offset": offset])
    }
    public func submit(title: String, description: String = "", requestID: UUID = UUID(), appVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) async throws -> FeatureWish {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines), body = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...120).contains(title.utf16.count), body.utf16.count <= 4000 else { throw KunioFeedbackError.server("feedback_invalid") }
        var context = ["sdk_version": "0.1.0", "os_version": ProcessInfo.processInfo.operatingSystemVersionString, "locale": Locale.current.identifier]
        if let appVersion { context["app_version"] = appVersion }
        context = context.mapValues { String($0.prefix(64)) }
        let result: WishResponse = try await authenticated(["action": "submit", "client_request_id": requestID.uuidString, "title": title, "body": body, "context": context])
        return result.request
    }
    /// Sets the desired vote state. Repeating the same value never adds a second vote.
    public func setVote(wishID: String, voted: Bool) async throws -> FeatureWish {
        guard UUID(uuidString: wishID) != nil else { throw KunioFeedbackError.server("feedback_invalid") }
        let result: WishResponse = try await authenticated(["action": "vote", "request_id": wishID, "voted": voted])
        return result.request
    }
}
