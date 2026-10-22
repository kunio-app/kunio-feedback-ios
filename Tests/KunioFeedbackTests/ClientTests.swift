import XCTest
import Foundation
@testable import KunioFeedback

final class MemoryCredentials: FeedbackCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    func load(account: String) -> String? { lock.lock(); defer { lock.unlock() }; return values[account] }
    func save(_ token: String, account: String) { lock.lock(); defer { lock.unlock() }; values[account] = token }
    func remove(account: String) { lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: account) }
}
final class MockFeedbackProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.lock.withLock { try Self.handler!(request) }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class ClientTests: XCTestCase {
    let key = "kb_live_" + String(repeating: "a", count: 48)
    let token = "kfp_" + String(repeating: "b", count: 64)
    func client(store: MemoryCredentials = MemoryCredentials()) throws -> KunioFeedbackClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockFeedbackProtocol.self]
        return try KunioFeedbackClient(boardKey: key, endpoint: URL(string: "https://feedback.example.test/api")!, session: URLSession(configuration: config), credentials: store)
    }
    func payload(_ request: URLRequest) throws -> [String: Any] {
        if let data = request.httpBody { return try JSONSerialization.jsonObject(with: data) as! [String: Any] }
        let stream = request.httpBodyStream!; stream.open(); defer { stream.close() }
        var data = Data(); var bytes = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let n = stream.read(&bytes, maxLength: bytes.count); if n > 0 { data.append(bytes, count: n) } else { break } }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
    func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    var page: [String: Any] { ["board": ["id": "board", "name": "Test", "intro": "Ideas", "icon_url": ""], "requests": [], "total": 0, "next_offset": NSNull()] }
    var wish: [String: Any] { ["id":"efbb3dcb-2563-4701-8da8-cb3899d56f40","title":"Offline mode","body":"Useful for travel","status":"planned","visibility":"published","vote_count":2,"created_at":"2026-10-22T12:34:56.123456+00:00","updated_at":"2026-10-22T12:34:56Z","has_voted":true,"is_mine":false] }
    func testRejectsInvalidKeysAndEndpoints() {
        XCTAssertThrowsError(try KunioFeedbackClient(boardKey: "secret"))
        XCTAssertThrowsError(try KunioFeedbackClient(boardKey: key, endpoint: URL(string:"http://example.com")!))
        XCTAssertThrowsError(try KunioFeedbackClient(boardKey: key, endpoint: URL(string:"https://user:password@example.com")!))
    }
    func testConcurrentReadsBootstrapOnceAndRestoreCredential() async throws {
        let store = MemoryCredentials(); var sessions = 0; var reads = 0
        MockFeedbackProtocol.handler = { request in
            let body = try self.payload(request)
            XCTAssertEqual(body["version"] as? Int, 1); XCTAssertEqual(body["board_key"] as? String, self.key)
            if body["action"] as? String == "session" { sessions += 1; return (200, try self.json(["participant_token":self.token])) }
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"), "Bearer " + self.token); reads += 1
            return (200, try self.json(self.page))
        }
        let a = try client(store: store)
        async let first = a.list(); async let second = a.list()
        _ = try await (first, second)
        let b = try client(store: store); _ = try await b.list()
        XCTAssertEqual(sessions, 1); XCTAssertEqual(reads, 3)
    }
    func testSubmissionCarriesStableIdAndVoteSetsExplicitState() async throws {
        let id = UUID(); var submissions = 0; var votes = 0
        MockFeedbackProtocol.handler = { request in
            let body = try self.payload(request)
            if body["action"] as? String == "session" { return (200, try self.json(["participant_token":self.token])) }
            if body["action"] as? String == "submit" { submissions += 1; XCTAssertEqual(body["client_request_id"] as? String, id.uuidString); XCTAssertEqual(body["title"] as? String,"Offline mode"); XCTAssertNil(body["participant_id"]); XCTAssertNil((body["context"] as? [String: Any])?["email"]) }
            if body["action"] as? String == "vote" { votes += 1; XCTAssertEqual(body["voted"] as? Bool,false) }
            return (200, try self.json(["request":self.wish]))
        }
        let a = try client(); _ = try await a.submit(title:" Offline mode ", requestID:id); _ = try await a.submit(title:"Offline mode", requestID:id)
        let result = try await a.setVote(wishID: wish["id"] as! String, voted:false)
        XCTAssertEqual(submissions, 2); XCTAssertEqual(votes, 1); XCTAssertEqual(result.status,.planned); XCTAssertEqual(result.voteCount,2)
    }
    func testAmbiguousWriteNeverRetriesAutomatically() async throws {
        var writes = 0
        MockFeedbackProtocol.handler = { request in
            let body = try self.payload(request)
            if body["action"] as? String == "session" { return (200, try self.json(["participant_token":self.token])) }
            writes += 1; throw URLError(.timedOut)
        }
        do { _ = try await client().submit(title:"Offline mode"); XCTFail("Expected failure") } catch { }
        XCTAssertEqual(writes,1)
    }
    func testExpiredAnonymousAccessReauthenticatesOnlyOnce() async throws {
        var sessions = 0; var lists = 0
        MockFeedbackProtocol.handler = { request in
            let body = try self.payload(request)
            if body["action"] as? String == "session" { sessions += 1; return (200, try self.json(["participant_token":self.token])) }
            lists += 1
            if lists == 1 { return (401, try self.json(["error":"feedback_participant_invalid"])) }
            return (200, try self.json(self.page))
        }
        _ = try await client().list(); XCTAssertEqual(sessions,2); XCTAssertEqual(lists,2)
    }
    func testBackendErrorsRemainActionable() async throws {
        MockFeedbackProtocol.handler = { request in
            if try self.payload(request)["action"] as? String == "session" { return (200, try self.json(["participant_token":self.token])) }
            return (403, try self.json(["error":"feedback_board_paused"]))
        }
        do { _ = try await client().list(); XCTFail("Expected pause") }
        catch KunioFeedbackError.server(let code) { XCTAssertEqual(code,"feedback_board_paused") }
    }
}
