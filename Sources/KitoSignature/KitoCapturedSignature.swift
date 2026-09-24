//
//  KitoCapturedSignature.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// A finished signature from `KitoSignatureSheet` or `KitoSignatureField`: drawn or typed, who
/// signed, when, and whether they ticked the consent box. `Codable` for storing with a form.
public struct KitoCapturedSignature: Codable, Hashable, Sendable, KitoSignatureRenderable {
    public enum Content: Codable, Hashable, Sendable {
        case drawn(KitoSignatureData)
        case typed(KitoTypedSignatureValue)
    }

    public var content: Content
    public var signerName: String?
    public var signedAt: Date
    /// The consent sentence the signer agreed to, if there was one.
    public var consent: String?

    public init(content: Content, signerName: String? = nil, signedAt: Date = Date(), consent: String? = nil) {
        self.content = content
        self.signerName = signerName
        self.signedAt = signedAt
        self.consent = consent
    }

    public static func drawn(_ data: KitoSignatureData, signerName: String? = nil,
                             signedAt: Date = Date()) -> KitoCapturedSignature {
        KitoCapturedSignature(content: .drawn(data), signerName: signerName, signedAt: signedAt)
    }

    public static func typed(_ value: KitoTypedSignatureValue, signedAt: Date = Date()) -> KitoCapturedSignature {
        KitoCapturedSignature(content: .typed(value), signerName: value.trimmedName, signedAt: signedAt)
    }

    public var isTyped: Bool {
        if case .typed = content { return true }
        return false
    }

    /// "Signed by Wycliff N · 24 Sep 2026".
    public var caption: KitoSignatureCaption {
        KitoSignatureCaption(signerName: signerName ?? "", date: signedAt)
    }

    public func inkPaths() -> [KitoInkPath] {
        switch content {
        case .drawn(let data): data.inkPaths()
        case .typed(let value): value.inkPaths()
        }
    }
}
