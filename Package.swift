// swift-tools-version:6.0
// SPDX-FileCopyrightText: 2026 Nick Wolff <nick@wolff.tech>
// SPDX-License-Identifier: GPL-2.0-only

import PackageDescription

let package = Package(
    name: "LogoGlow",
    // The illuminated logo only exists on MacBook Pro models that ship with macOS 27.
    platforms: [.macOS("27.0")],
    targets: [
        // Menu bar app. Scripts/make-app.sh wraps this executable in "Logo Glow.app".
        .executableTarget(
            name: "LogoGlow",
            dependencies: ["LogoGlowCore"],
            path: "Sources/LogoGlow"
        ),
        // CoreBrightness access and control handoff, kept free of UI so it can be tested.
        .target(
            name: "LogoGlowCore",
            path: "Sources/LogoGlowCore"
        ),
        .testTarget(
            name: "LogoGlowCoreTests",
            dependencies: ["LogoGlowCore"],
            path: "Tests/LogoGlowCoreTests"
        ),
    ]
)
