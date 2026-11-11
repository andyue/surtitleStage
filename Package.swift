// swift-tools-version: 6.0
import PackageDescription
import Foundation

let vendor = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Vendor").path
let syphonSwift: [SwiftSetting] = [.unsafeFlags(["-F", vendor])]
let syphonLink: [LinkerSetting] = [
    .unsafeFlags(["-F", vendor]), .linkedFramework("Syphon"),
    .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
    .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", vendor], .when(configuration: .debug))
]

let package = Package(
    name: "SubtitleStage",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SubtitleStage", targets: ["SubtitleStage"])],
    targets: [
        .target(name: "NDIBridge", path: "NDIBridge", publicHeadersPath: "include"),
        .target(name: "SubtitleCore", path: "SubtitleStage", exclude: ["App", "Stores", "Views", "Rendering", "Output", "Control"], sources: ["Models", "Playback", "Importers", "Utilities"]),
        .executableTarget(name: "SubtitleStage", dependencies: ["SubtitleCore", "NDIBridge"], path: "SubtitleStage", exclude: ["Models", "Playback", "Importers", "Utilities"], sources: ["App", "Stores", "Views", "Rendering", "Output", "Control"], swiftSettings: syphonSwift, linkerSettings: syphonLink),
        .target(name: "NDITestSupport", path: "NDITestSupport", publicHeadersPath: "include"),
        .testTarget(name: "SubtitleStageTests", dependencies: ["SubtitleCore", "SubtitleStage", "NDITestSupport"], path: "SubtitleStageTests", swiftSettings: syphonSwift)
    ]
)
