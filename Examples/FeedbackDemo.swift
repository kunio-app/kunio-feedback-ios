import SwiftUI
import KunioFeedback

@main
struct FeedbackDemo: App {
    init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "KunioBoardKey") as? String ?? ""
        KunioFeedback.configure(boardKey: key)
    }
    var body: some Scene {
        WindowGroup { KunioFeedbackBoard().tint(.mint) }
    }
}
