// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "touchy",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CMultitouch"
        ),
        .executableTarget(
            name: "Touchy",
            dependencies: ["CMultitouch"],
            swiftSettings: [
                // The @convention(c) multitouch callback + global wiring fight Swift 6
                // strict concurrency for little benefit in a small app; use v5 semantics.
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/System/Library/PrivateFrameworks",
                    "-framework", "MultitouchSupport",
                ])
            ]
        ),
    ]
)
