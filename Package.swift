// swift-tools-version:5.10
// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import PackageDescription

let package = Package(
    name: "Ludotheque",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Ludotheque",
            path: "Sources/Ludotheque",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
