// swift-tools-version: 6.2

import PackageDescription

// The system frameworks the statically linked libwebrtc inside MatrixRtcFFI resolves against.
// These are safe linker settings, so a versioned dependency is allowed to declare them and the
// host does not have to. `-ObjC` is the one thing the host must still add itself: it cannot be
// expressed here (unsafeFlags are rejected in a versioned dependency) and without it libwebrtc's
// Objective-C categories are dead-stripped from the static archive. See the README.
//
// matrix-rust-rtc's own manifest gained this same block after 0.2.0-rc.1 was tagged; once a tag
// ships it, this list can go.
let mediaLinkerSettings: [LinkerSetting] = [
    .linkedLibrary("c++"),
    .linkedFramework("AVFoundation"),
    .linkedFramework("AudioToolbox"),
    .linkedFramework("CoreMedia"),
    .linkedFramework("CoreVideo"),
    .linkedFramework("VideoToolbox"),
    .linkedFramework("Metal"),
    .linkedFramework("MetalKit"),
    .linkedFramework("QuartzCore"),
    .linkedFramework("CoreGraphics"),
    .linkedFramework("Network"),
    .linkedFramework("UIKit"),
]

let package = Package(
    name: "ElementCall",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "ElementCallKit", targets: ["ElementCallKit"]),
        .library(name: "ElementCall", targets: ["ElementCall"]),
        .library(name: "ElementCallUI", targets: ["ElementCallUI"]),
        .library(name: "ElementCallMatrix", targets: ["ElementCallMatrix"])
    ],
    dependencies: [
        .package(url: "https://github.com/BillCarsonFr/matrix-rust-rtc", exact: "0.2.0-rc.1"),
        // .package(path: "../matrix-rust-rtc"),
        // The design *tokens*, not the Compound component library. Tokens are static values in
        // their own small package, so depending on them is safe. Compound itself is not, because its
        // colours live on a shared instance a host re-brands at runtime: a second copy linked in
        // here would never see that override, and a re-branded host would get a stock call screen.
        // The host still supplies the real colours through ElementCallTheme; these are the default.
        .package(url: "https://github.com/element-hq/compound-design-tokens", exact: "10.2.4"),
        // A range, deliberately, where everything else here is pinned exactly.
        //
        // A library that pins the SDK exactly forces every consumer onto that version, so resolution
        // fails the moment a host bumps the SDK before this package cuts a release. That is the
        // release-cadence coupling that ruled out shipping this UI from the Rust repo, and it would be
        // self-inflicted here.
        //
        // The upper bound is absurd on purpose: the SDK's major version is the calendar year, so
        // `upToNextMajor` would lock hosts out every January. CI builds against one exact version, and
        // that is what actually gets tested.
        .package(url: "https://github.com/element-hq/matrix-rust-components-swift", "26.09.01" ..< "100.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.4")
    ],
    targets: [
        .target(name: "ElementCallKit",
                dependencies: [.product(name: "MatrixRtc", package: "matrix-rust-rtc")],
                swiftSettings: [.defaultIsolation(MainActor.self)],
                linkerSettings: mediaLinkerSettings),
        .target(name: "ElementCall",
                dependencies: ["ElementCallKit",
                               .product(name: "CompoundDesignTokens", package: "compound-design-tokens")],
                swiftSettings: [.defaultIsolation(MainActor.self)]),
        .target(name: "ElementCallUI",
                dependencies: ["ElementCall"],
                swiftSettings: [.defaultIsolation(MainActor.self)]),
        // The only module allowed to know the Matrix SDK exists. Everything a host would otherwise
        // have to implement for itself lives here, so a host supplies a Client and nothing more.
        .target(name: "ElementCallMatrix",
                dependencies: ["ElementCallKit",
                               "ElementCall",
                               .product(name: "MatrixRustSDK", package: "matrix-rust-components-swift")],
                swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "ElementCallTests",
                    dependencies: ["ElementCallUI",
                                   "ElementCallMatrix",
                                   .product(name: "SnapshotTesting", package: "swift-snapshot-testing")],
                    exclude: ["__Snapshots__"],
                    swiftSettings: [.defaultIsolation(MainActor.self)])
    ]
)
