//
//  KitoTypedSignatureStyle.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import UIKit
import CoreText

/// A handwriting-like look for a typed signature. Script styles use handwriting fonts that ship
/// with iOS and fall back to a slanted system font if one is missing.
public enum KitoTypedSignatureStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Flowing copperplate (Snell Roundhand).
    case script
    /// Loose and friendly (Bradley Hand).
    case casual
    /// Tall and formal (Savoye).
    case elegant
    /// A slanted serif, like a signed letter.
    case classic
    /// A light, slanted sans-serif.
    case modern
    /// Soft and rounded.
    case rounded

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .script: "Script"
        case .casual: "Casual"
        case .elegant: "Elegant"
        case .classic: "Classic"
        case .modern: "Modern"
        case .rounded: "Rounded"
        }
    }

    /// The font at `size`, with any slant applied separately by `slant`.
    public func font(size: CGFloat) -> UIFont {
        if let name = fontName, let font = UIFont(name: name, size: size * sizeFactor) {
            return font
        }
        return systemFont(size: size)
    }

    /// Horizontal shear applied to the glyphs (0 = upright).
    public var slant: CGFloat {
        if let name = fontName, UIFont(name: name, size: 12) != nil { return 0 }
        switch self {
        case .modern, .rounded: return 0.22
        default: return 0.16
        }
    }

    private var fontName: String? {
        switch self {
        case .script: "SnellRoundhand-Bold"
        case .casual: "BradleyHandITCTT-Bold"
        case .elegant: "SavoyeLetPlain"
        case .classic, .modern, .rounded: nil
        }
    }

    private var sizeFactor: CGFloat {
        self == .elegant ? 1.35 : 1
    }

    private func systemFont(size: CGFloat) -> UIFont {
        let weight: UIFont.Weight = self == .modern ? .light : (self == .rounded ? .medium : .regular)
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let design: UIFontDescriptor.SystemDesign = switch self {
        case .rounded: .rounded
        case .modern: .default
        default: .serif
        }
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        let italic = self == .classic ? descriptor.withSymbolicTraits(.traitItalic) : nil
        return UIFont(descriptor: italic ?? descriptor, size: size)
    }

    /// The outline of `text` in this style, y pointing down, baseline at y = 0.
    public func glyphPath(for text: String, size: CGFloat = 64) -> Path {
        let font = font(size: size)
        let path = KitoGlyphOutline.path(for: text, font: font)
        guard slant != 0 else { return Path(path) }
        let shear = CGAffineTransform(a: 1, b: 0, c: -slant, d: 1, tx: 0, ty: 0)
        return Path(path).applying(shear)
    }
}

/// A typed signature: the name, its style and ink.
public struct KitoTypedSignatureValue: Codable, Hashable, Sendable, KitoSignatureRenderable {
    public var name: String
    public var style: KitoTypedSignatureStyle
    public var ink: KitoInk

    public init(name: String = "", style: KitoTypedSignatureStyle = .script, ink: KitoInk = .automatic) {
        self.name = name
        self.style = style
        self.ink = ink
    }

    /// The name with extra spaces removed.
    public var trimmedName: String { KitoSignatureCaption.clean(name) }
    /// True when the name has at least two letters.
    public var isValid: Bool { trimmedName.filter(\.isLetter).count >= 2 }

    public func inkPaths() -> [KitoInkPath] {
        guard !trimmedName.isEmpty else { return [] }
        return [KitoInkPath(path: style.glyphPath(for: trimmedName), ink: ink)]
    }
}

enum KitoGlyphOutline {
    /// Glyph outlines for a line of text, using fallback fonts for characters the font lacks.
    static func path(for text: String, font: UIFont) -> CGPath {
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        let result = CGMutablePath()
        let runs = (CTLineGetGlyphRuns(line) as? [CTRun]) ?? []
        for run in runs {
            append(run, fallback: font as CTFont, to: result)
        }
        return result
    }

    private static func append(_ run: CTRun, fallback: CTFont, to result: CGMutablePath) {
        let count = CTRunGetGlyphCount(run)
        guard count > 0 else { return }
        let runFont = font(of: run) ?? fallback
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        for index in 0..<count {
            guard let glyph = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) else { continue }
            let position = positions[index]
            let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: position.x, ty: -position.y)
            result.addPath(glyph, transform: flip)
        }
    }

    private static func font(of run: CTRun) -> CTFont? {
        let attributes = CTRunGetAttributes(run) as NSDictionary
        guard let value = attributes[kCTFontAttributeName] else { return nil }
        let object = value as CFTypeRef
        guard CFGetTypeID(object) == CTFontGetTypeID() else { return nil }
        // The type ID check above guarantees this is a CTFont.
        return (object as! CTFont)
    }
}
