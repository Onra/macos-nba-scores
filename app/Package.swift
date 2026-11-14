// swift-tools-version: 6.0
// Built into "NBA Scores.app" by build.sh.
import PackageDescription

let package = Package(
    name: "NBAScores",
    platforms: [.macOS("26.0")],
    targets: [
        // Data: ESPN parsing and formatting, no UI.
        .target(name: "NBAKit"),
        .executableTarget(name: "NBAScores", dependencies: ["NBAKit"]),
        .testTarget(name: "NBAScoresTests", dependencies: ["NBAKit"], resources: [.copy("Fixtures")]),
    ]
)
