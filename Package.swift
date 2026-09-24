// swift-tools-version: 5.9
//
//  Package.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import PackageDescription

let package = Package(
    name: "KitoSignature",
    platforms: [.iOS(.v17)],
    products: [.library(name: "KitoSignature", targets: ["KitoSignature"])],
    dependencies: [
        .package(url: "https://github.com/WykSofts-Inc/KitoCore.git", from: "1.1.0"),
    ],
    targets: [
        .target(name: "KitoSignature", dependencies: [.product(name: "KitoCore", package: "KitoCore")]),
        .testTarget(name: "KitoSignatureTests", dependencies: ["KitoSignature"]),
    ]
)
