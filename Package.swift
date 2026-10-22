// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "KunioFeedback",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "KunioFeedback", targets: ["KunioFeedback"])],
    targets: [
        .target(name: "KunioFeedback", resources: [.process("Resources")]),
        .testTarget(name: "KunioFeedbackTests", dependencies: ["KunioFeedback"])
    ]
)
