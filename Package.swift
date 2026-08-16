// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexAccountSwitcher",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "CodexAccountSwitcherCore",
            targets: ["CodexAccountSwitcherCore"]
        ),
        .executable(
            name: "CodexAccountSwitcher",
            targets: ["CodexAccountSwitcher"]
        )
    ],
    targets: [
        .target(
            name: "CodexAccountSwitcherCore",
            path: "Sources/CodexAccountSwitcherCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "CodexAccountSwitcher",
            dependencies: ["CodexAccountSwitcherCore"],
            path: "Sources/CodexAccountSwitcher",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "CodexAccountSwitcherCoreTests",
            dependencies: ["CodexAccountSwitcherCore"],
            path: "Tests/CodexAccountSwitcherCoreTests"
        )
    ]
)
