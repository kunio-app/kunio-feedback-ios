import Foundation

public enum WishStatus: String, Codable, CaseIterable, Sendable {
    case open, planned, inProgress = "in_progress", done
    public var title: String {
        switch self {
        case .open: return feedbackText("Open")
        case .planned: return feedbackText("Planned")
        case .inProgress: return feedbackText("In progress")
        case .done: return feedbackText("Done")
        }
    }
}
public enum WishVisibility: String, Codable, Sendable { case pending, published, hidden }
public struct FeatureWish: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let status: WishStatus
    public let visibility: WishVisibility
    public let voteCount: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let hasVoted: Bool
    public let isMine: Bool
    enum CodingKeys: String, CodingKey {
        case id, title, body, status, visibility
        case voteCount = "vote_count", createdAt = "created_at", updatedAt = "updated_at"
        case hasVoted = "has_voted", isMine = "is_mine"
    }
}
public struct FeedbackBoard: Codable, Sendable {
    public let id: String
    public let name: String
    public let intro: String
    public let iconURL: URL?
    enum CodingKeys: String, CodingKey { case id, name, intro, iconURL = "icon_url" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        intro = try c.decode(String.self, forKey: .intro)
        let raw = try c.decodeIfPresent(String.self, forKey: .iconURL) ?? ""
        if let u = URL(string: raw), u.scheme == "https", let host = u.host, host == "mzstatic.com" || host.hasSuffix(".mzstatic.com") { iconURL = u } else { iconURL = nil }
    }
}
public struct FeedbackPage: Decodable, Sendable {
    public let board: FeedbackBoard
    public let requests: [FeatureWish]
    public let total: Int
    public let nextOffset: Int?
    enum CodingKeys: String, CodingKey { case board, requests, total, nextOffset = "next_offset" }
}
public enum WishSort: String, Sendable { case popular, new }
public enum KunioFeedbackError: Error, LocalizedError, Sendable {
    case notConfigured, invalidConfiguration, invalidResponse, connectionFailed, credentialStorage, server(String)
    public var errorDescription: String? {
        switch self {
        case .notConfigured: return feedbackText("Configure KunioFeedback with your board key before opening the board.")
        case .invalidConfiguration: return feedbackText("Check your feedback board key and endpoint.")
        case .invalidResponse: return feedbackText("The board returned an unexpected response. Please try again.")
        case .connectionFailed: return feedbackText("Could not connect. Check your connection and try again.")
        case .credentialStorage: return feedbackText("Your anonymous access could not be saved securely on this device.")
        case .server(let code):
            let key: String
            switch code {
            case "feedback_board_paused": key = "This feedback board is currently paused."
            case "feedback_rate_limited": key = "Please wait a little before trying again."
            case "feedback_key_invalid": key = "This feedback board is not available."
            case "feedback_participant_invalid": key = "Your anonymous access could not be restored. Please try again."
            case "feedback_request_not_found": key = "This wish is no longer available."
            case "feedback_invalid": key = "Use a title between 3 and 120 characters and a description up to 4,000 characters."
            case "feedback_idempotency_conflict": key = "This draft changed after an earlier attempt. Please try again."
            case "feedback_invalid_version": key = "Update the app to continue using this board."
            default: key = "Feedback could not be loaded. Please try again."
            }
            return feedbackText(key)
        }
    }
}
func feedbackText(_ key: String) -> String { NSLocalizedString(key, bundle: .module, comment: "") }
func feedbackDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let c = try decoder.singleValueContainer(), value = try c.decode(String.self)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: value) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        if let d = formatter.date(from: value) { return d }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid feedback date")
    }
    return decoder
}
