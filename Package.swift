// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Zielzeit",
    // The UI leans on modern SwiftUI and Swift Charts APIs; targeting an older
    // release would mean scattering availability checks through every view.
    platforms: [.macOS(.v15)],
    dependencies: [
        // The only dependency this package has, and it earns it: without an
        // updater a user who installed v1.0 runs v1.0 forever, because the app
        // is distributed as a DMG from a releases page and there is no cask.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4"),
    ],
    targets: [
        // Pure logic: projection math and Scalable CLI access. No AppKit or
        // SwiftUI, so it stays unit-testable without a UI. Sparkle does not
        // reach here either — the updater is AppKit-backed and lives in the app
        // target, which is what keeps this one testable.
        .target(name: "ZielzeitCore"),
        // The menu bar app itself.
        .executableTarget(
            name: "Zielzeit",
            dependencies: ["ZielzeitCore", .product(name: "Sparkle", package: "Sparkle")],
            // SwiftPM links the XCFramework but will not embed it, so the binary
            // has to be told where the copy in the bundle lives. Scripts/embed-sparkle
            // is what puts it there.
            //
            // `.unsafeFlags` is legal only because Zielzeit is a root package and is
            // never consumed as a dependency. The day anything depends on this
            // package, SwiftPM refuses to resolve it and this is why.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(name: "ZielzeitCoreTests", dependencies: ["ZielzeitCore"]),
    ],
    // Swift 5 language mode: this is a small single-threaded app and strict
    // concurrency checking buys nothing here.
    swiftLanguageModes: [.v5]
)
