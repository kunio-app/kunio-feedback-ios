# KunioFeedback · 0.1.2

A native, moderated feature wishlist for iOS 17+. No external dependencies, web views, end-user registration or customer backend required.

## Install

In Xcode choose **File → Add Package Dependencies**, paste this repository URL, select **Up to Next Major Version** starting at **0.1.2**, and add the **KunioFeedback** product to your app target.

```text
https://github.com/kunio-app/kunio-feedback-ios.git
```

For a Swift package, add:

```swift
.package(url: "https://github.com/kunio-app/kunio-feedback-ios.git", from: "0.1.2")
```

Then add `.product(name: "KunioFeedback", package: "kunio-feedback-ios")` to your target dependencies. Create a feedback board in Kunio and copy its public board key from **Feedback → Installation**.

## Configure and present

```swift
import SwiftUI
import KunioFeedback

@main
struct MyApp: App {
    init() {
        KunioFeedback.configure(boardKey: "YOUR_PUBLIC_BOARD_KEY")
    }

    var body: some Scene {
        WindowGroup { SettingsScreen() }
    }
}

struct SettingsScreen: View {
    @State private var showFeedback = false

    var body: some View {
        List {
            Button("Feature wishes", systemImage: "bubble.left.and.bubble.right") {
                showFeedback = true
            }
        }
        .sheet(isPresented: $showFeedback) {
            KunioFeedbackBoard()
                .tint(.mint)
        }
    }
}
```

The board includes its own `NavigationStack`. It supports search, popular/new/my-wishes views, status filtering, submissions, similar-request suggestions and one reversible vote per anonymous participant/request. English and German localization, Dynamic Type, VoiceOver and system dark mode are included. The SwiftUI board is iOS-only; the core networking client also builds on macOS 14+ for testing/tooling.

## Moderation and synchronization

New app submissions are pending. Only the author sees their pending wish; other participants see it after a workspace owner/admin publishes it in Kunio. Hidden wishes are not returned by the SDK. Status changes are received on board opening, foregrounding or pull-to-refresh. There is no background polling, offline write queue or websocket dependency.

The current loaded board stays on screen if refreshing fails. Drafts stay in memory when a send fails. They are not persisted after the host app exits. Repeating a send with the same draft ID is idempotent; changing the draft starts a new submission ID. Ambiguous network failures are not automatically retried. One rejected anonymous credential can be re-established before retrying a request.

## Public board key and anonymous access

Copy the `kb_live_…` board key from Feedback → Installation. It is public configuration, not an administrative secret. The SDK obtains a board-scoped random participant credential and stores it in Keychain using `AfterFirstUnlockThisDeviceOnly`. Credentials are scoped locally to both the endpoint and board key. They are never logged or placed in URLs. HTTPS redirects are refused before credentials can be forwarded.

Anonymous identity is local to a device/keychain context and is not a verified person or a cross-device account. Voting can therefore not guarantee one vote per real human. Public endpoints apply limits and all new wishes are moderated. Custom user IDs, emails, paid-user weighting and signed account identity are not part of V1.

The server stores feature title/description, anonymous participant identity and software context (app/SDK/OS version and locale). It does not collect names, email addresses, IDFA, device fingerprints or analytics events. A PrivacyInfo.xcprivacy manifest is included. Product owners should reflect this app functionality in their app's privacy disclosures.

## Advanced client

```swift
let client = try KunioFeedbackClient(boardKey: "YOUR_PUBLIC_BOARD_KEY")
let page = try await client.list(search: "Offline", sort: .popular)
let requestID = UUID() // Keep the same ID for a retry of the same draft.
let wish = try await client.submit(
    title: "Offline workouts",
    description: "Open my saved sessions while travelling.",
    requestID: requestID
)
let updated = try await client.setVote(wishID: wish.id, voted: false)
```

Use `page.nextOffset` to request subsequent pages of up to 50 wishes. The default endpoint is Kunio's deployed feedback API; an explicit HTTPS endpoint may be supplied for a separately deployed environment.

## Development

`swift test` checks anonymous identity, concurrent initialization, idempotency IDs, dates and network-failure behavior using an isolated transport/store. `xcodebuild -scheme KunioFeedback -destination 'generic/platform=iOS Simulator' build` compiles the native board. The example app reads a public board key from the `KunioBoardKey` Info.plist entry and can be used as a minimal integration target.

## License

[Kunio SDK License 1.0](LICENSE) — proprietary, source available. You may use and adapt this SDK to integrate your own free or commercial apps with Kunio, and distribute it compiled inside those apps. Standalone resale or redistribution, rebranding as your own SDK, and use for a competing feedback service are not permitted. See the full license for the applicable terms.
