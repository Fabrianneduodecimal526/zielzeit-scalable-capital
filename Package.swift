// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Zielzeit",
    // The UI leans on modern SwiftUI and Swift Charts APIs; targeting an older
    // release would mean scattering availability checks through every view.
    platforms: [.macOS(.v15)],
    targets: [
        // Pure logic: projection math and Scalable CLI access. No AppKit or
        // SwiftUI, so it stays unit-testable without a UI.
        .target(name: "ZielzeitCore"),
        // The menu bar app itself.
        .executableTarget(name: "Zielzeit", dependencies: ["ZielzeitCore"]),
        .testTarget(name: "ZielzeitCoreTests", dependencies: ["ZielzeitCore"]),
    ],
    // Swift 5 language mode: this is a small single-threaded app and strict
    // concurrency checking buys nothing here.
    swiftLanguageModes: [.v5]
)
