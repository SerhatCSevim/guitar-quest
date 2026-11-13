// swift-tools-version:5.10
import PackageDescription

// Guitar Quest — native macOS (SwiftUI) port of the Windows web app.
// MusicCore: pure Swift music engine (no UI, no audio) — checked against the golden JSON via `swift run GoldenCheck`.
// GuitarQuest: the SwiftUI app. Build a double-clickable .app with scripts/build_app.sh
let package = Package(
    name: "GuitarQuest",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GuitarQuest", targets: ["GuitarQuest"]),
        .library(name: "MusicCore", targets: ["MusicCore"])
    ],
    targets: [
        .target(name: "MusicCore"),
        .executableTarget(name: "GuitarQuest", dependencies: ["MusicCore"]),
        .executableTarget(name: "IconMaker"),
        // Golden parity checker (plain executable: works without XCTest / swift-testing). Run: swift run GoldenCheck
        .executableTarget(name: "GoldenCheck", dependencies: ["MusicCore"], resources: [.copy("Golden")])
    ]
)
