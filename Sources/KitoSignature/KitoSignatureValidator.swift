//
//  KitoSignatureValidator.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// Whether a drawing counts as a signature.
public enum KitoSignatureValidation: Equatable, Sendable {
    case empty
    /// Too little ink — a dot or a tick.
    case tooShort
    /// Long enough but squeezed into a tiny area.
    case tooSmall
    case valid

    public var isValid: Bool { self == .valid }

    /// A friendly line to show under the pad, or `nil` when valid.
    public var message: String? {
        switch self {
        case .empty: "Sign in the box above."
        case .tooShort: "That's a bit short for a signature — try your full signature."
        case .tooSmall: "Sign a little larger so it's legible."
        case .valid: nil
        }
    }
}

/// Rules for what counts as a signature. Values are in pad points.
public struct KitoSignatureValidator: Equatable, Sendable {
    /// Fewest touch samples across all strokes.
    public var minimumPoints: Int
    /// Shortest total ink length.
    public var minimumLength: Double
    /// Smallest the longer side of the bounding box may be.
    public var minimumSize: Double

    public init(minimumPoints: Int = 10, minimumLength: Double = 60, minimumSize: Double = 32) {
        self.minimumPoints = minimumPoints
        self.minimumLength = minimumLength
        self.minimumSize = minimumSize
    }

    /// Accepts anything with at least one point.
    public static let lenient = KitoSignatureValidator(minimumPoints: 1, minimumLength: 0, minimumSize: 0)

    public func validate(_ data: KitoSignatureData) -> KitoSignatureValidation {
        if data.isEmpty { return .empty }
        if data.pointCount < minimumPoints || data.inkLength < minimumLength { return .tooShort }
        let box = data.boundingBox
        if Double(max(box.width, box.height)) < minimumSize { return .tooSmall }
        return .valid
    }
}
