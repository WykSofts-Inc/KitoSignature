//
//  KitoInk.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI

/// An ink colour stored with every stroke, so a saved signature re-renders in the colour it was
/// signed in.
///
/// `.automatic` follows the theme on screen (dark ink on light surfaces, light ink in dark mode) and
/// exports as black, so a signature signed at night still prints.
public struct KitoInk: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double
    /// Follows `theme.colors.onSurface` on screen and exports as black.
    public var isAutomatic: Bool

    public var id: String { name }

    public init(name: String, red: Double, green: Double, blue: Double, opacity: Double = 1,
                isAutomatic: Bool = false) {
        self.name = name
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
        self.isAutomatic = isAutomatic
    }

    /// The colour to draw with on screen. Automatic ink uses `adaptive`.
    public func color(adaptive: Color) -> Color {
        isAutomatic ? adaptive : Color(red: red, green: green, blue: blue).opacity(opacity)
    }

    /// The colour used in exported images, PDFs and SVGs.
    public var exportColor: UIColor {
        UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(opacity))
    }

    /// A `#RRGGBB` string for SVG.
    public var hex: String {
        let r = Self.byte(red), g = Self.byte(green), b = Self.byte(blue)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// The same ink at another opacity.
    public func opacity(_ value: Double) -> KitoInk {
        var copy = self
        copy.opacity = value
        return copy
    }

    private static func byte(_ value: Double) -> Int {
        Int((min(max(value, 0), 1) * 255).rounded())
    }
}

public extension KitoInk {
    /// Follows the theme on screen, black when exported.
    static let automatic = KitoInk(name: "Ink", red: 0.07, green: 0.07, blue: 0.09, isAutomatic: true)
    static let black = KitoInk(name: "Black", red: 0.07, green: 0.07, blue: 0.09)
    static let royalBlue = KitoInk(name: "Royal blue", red: 0.12, green: 0.33, blue: 0.86)
    static let navy = KitoInk(name: "Navy", red: 0.08, green: 0.16, blue: 0.42)
    static let burgundy = KitoInk(name: "Burgundy", red: 0.55, green: 0.10, blue: 0.20)
    static let forest = KitoInk(name: "Forest", red: 0.09, green: 0.43, blue: 0.27)
    static let red = KitoInk(name: "Red", red: 0.93, green: 0.23, blue: 0.21)
    static let orange = KitoInk(name: "Orange", red: 0.98, green: 0.55, blue: 0.10)
    static let yellow = KitoInk(name: "Yellow", red: 1.00, green: 0.84, blue: 0.04)
    static let green = KitoInk(name: "Green", red: 0.20, green: 0.74, blue: 0.35)
    static let white = KitoInk(name: "White", red: 1, green: 1, blue: 1)

    /// Inks that look right on a legal document.
    static let signatureInks: [KitoInk] = [.automatic, .royalBlue, .navy, .burgundy]
    /// Bright inks for marking up photos.
    static let markupInks: [KitoInk] = [.red, .orange, .yellow, .green, .royalBlue, .white, .black]
}

/// How a pen turns speed into line width: slow strokes are thick, fast strokes thin out, like a
/// fountain pen. Widths and speeds are in points, so scaling a signature scales its pen too.
public struct KitoPenStyle: Codable, Hashable, Sendable {
    /// Width when moving at `fastVelocity` or faster.
    public var minWidth: Double
    /// Width when moving at `slowVelocity` or slower.
    public var maxWidth: Double
    /// Points per second at or below which the pen draws `maxWidth`.
    public var slowVelocity: Double
    /// Points per second at or above which the pen draws `minWidth`.
    public var fastVelocity: Double
    /// 0...1 — how quickly the width follows the speed. Lower is smoother.
    public var responsiveness: Double
    /// Points closer than this to the previous one are ignored while drawing.
    public var minDistance: Double

    public init(minWidth: Double = 1.2, maxWidth: Double = 4.2, slowVelocity: Double = 60,
                fastVelocity: Double = 1_600, responsiveness: Double = 0.35, minDistance: Double = 1.2) {
        self.minWidth = minWidth
        self.maxWidth = max(maxWidth, minWidth)
        self.slowVelocity = slowVelocity
        self.fastVelocity = max(fastVelocity, slowVelocity + 1)
        self.responsiveness = min(max(responsiveness, 0.01), 1)
        self.minDistance = minDistance
    }

    /// A pen-like default with a lot of line variation.
    public static let fountain = KitoPenStyle()
    /// Even, confident lines.
    public static let ballpoint = KitoPenStyle(minWidth: 1.8, maxWidth: 2.8, responsiveness: 0.25)
    /// Thin and crisp.
    public static let fineliner = KitoPenStyle(minWidth: 1, maxWidth: 1.8, responsiveness: 0.2)
    /// Bold, for sketching and markup.
    public static let marker = KitoPenStyle(minWidth: 5, maxWidth: 7, responsiveness: 0.2)

    /// The target width for a speed, before smoothing.
    public func width(forVelocity velocity: Double) -> Double {
        let progress = (velocity - slowVelocity) / (fastVelocity - slowVelocity)
        let clamped = min(max(progress, 0), 1)
        return maxWidth - (maxWidth - minWidth) * clamped
    }

    /// The same pen at another scale: widths, speeds and spacing all multiply by `factor`.
    public func scaled(by factor: Double) -> KitoPenStyle {
        var copy = self
        copy.minWidth *= factor
        copy.maxWidth *= factor
        copy.slowVelocity *= factor
        copy.fastVelocity *= factor
        copy.minDistance *= factor
        return copy
    }
}
