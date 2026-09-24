//
//  KitoCanvasBackground.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import UIKit
import KitoCore

/// A straight line in a background pattern.
public struct KitoCanvasLine: Equatable, Sendable {
    public var start: CGPoint
    public var end: CGPoint

    public init(start: CGPoint, end: CGPoint) {
        self.start = start
        self.end = end
    }
}

/// Paper for a drawing canvas.
public enum KitoCanvasBackground: String, CaseIterable, Codable, Sendable, Identifiable {
    case blank
    case grid
    case lined
    case dotted

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .blank: "Blank"
        case .grid: "Grid"
        case .lined: "Lined"
        case .dotted: "Dotted"
        }
    }

    public var systemImage: String {
        switch self {
        case .blank: "square"
        case .grid: "squareshape.split.3x3"
        case .lined: "line.3.horizontal"
        case .dotted: "circle.grid.3x3"
        }
    }

    /// The pattern's lines inside `rect`, `spacing` apart. Blank and dotted have none.
    public func lines(in rect: CGRect, spacing: CGFloat) -> [KitoCanvasLine] {
        guard spacing > 0, !rect.isEmpty else { return [] }
        switch self {
        case .blank, .dotted:
            return []
        case .lined:
            return Self.offsets(from: rect.minY, to: rect.maxY, spacing: spacing).map { y in
                KitoCanvasLine(start: CGPoint(x: rect.minX, y: y), end: CGPoint(x: rect.maxX, y: y))
            }
        case .grid:
            let rows = Self.offsets(from: rect.minY, to: rect.maxY, spacing: spacing).map { y in
                KitoCanvasLine(start: CGPoint(x: rect.minX, y: y), end: CGPoint(x: rect.maxX, y: y))
            }
            let columns = Self.offsets(from: rect.minX, to: rect.maxX, spacing: spacing).map { x in
                KitoCanvasLine(start: CGPoint(x: x, y: rect.minY), end: CGPoint(x: x, y: rect.maxY))
            }
            return rows + columns
        }
    }

    /// Dot centres for `.dotted`, empty for the others.
    public func dots(in rect: CGRect, spacing: CGFloat) -> [CGPoint] {
        guard self == .dotted, spacing > 0, !rect.isEmpty else { return [] }
        let xs = Self.offsets(from: rect.minX, to: rect.maxX, spacing: spacing)
        let ys = Self.offsets(from: rect.minY, to: rect.maxY, spacing: spacing)
        return ys.flatMap { y in xs.map { x in CGPoint(x: x, y: y) } }
    }

    /// The x position of the notebook margin on lined paper.
    public func marginX(in rect: CGRect, spacing: CGFloat) -> CGFloat? {
        self == .lined ? rect.minX + spacing * 2 : nil
    }

    /// Positions `spacing` apart strictly inside `from..<to`, starting one step in.
    static func offsets(from start: CGFloat, to end: CGFloat, spacing: CGFloat) -> [CGFloat] {
        var values: [CGFloat] = []
        var value = start + spacing
        while value < end, values.count < 2_000 {
            values.append(value)
            value += spacing
        }
        return values
    }

    /// Draws the pattern into a Core Graphics context, for exports.
    func draw(in context: CGContext, rect: CGRect, spacing: CGFloat, line: UIColor, margin: UIColor) {
        context.saveGState()
        context.setStrokeColor(line.cgColor)
        context.setLineWidth(0.75)
        for item in lines(in: rect, spacing: spacing) {
            context.move(to: item.start)
            context.addLine(to: item.end)
        }
        context.strokePath()
        context.setFillColor(line.cgColor)
        for dot in dots(in: rect, spacing: spacing) {
            context.fillEllipse(in: CGRect(x: dot.x - 1.25, y: dot.y - 1.25, width: 2.5, height: 2.5))
        }
        if let x = marginX(in: rect, spacing: spacing) {
            context.setStrokeColor(margin.cgColor)
            context.setLineWidth(1)
            context.move(to: CGPoint(x: x, y: rect.minY))
            context.addLine(to: CGPoint(x: x, y: rect.maxY))
            context.strokePath()
        }
        context.restoreGState()
    }
}

/// Draws a `KitoCanvasBackground` with theme colours.
public struct KitoCanvasBackgroundView: View {
    private let background: KitoCanvasBackground
    private let spacing: CGFloat

    @Environment(\.kitoTheme) private var theme

    public init(_ background: KitoCanvasBackground, spacing: CGFloat = 24) {
        self.background = background
        self.spacing = spacing
    }

    public var body: some View {
        let lineColor = theme.colors.onSurface.opacity(background == .dotted ? 0.22 : 0.09)
        let marginColor = theme.colors.danger.opacity(0.35)
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            var lines = Path()
            for item in background.lines(in: rect, spacing: spacing) {
                lines.move(to: item.start)
                lines.addLine(to: item.end)
            }
            context.stroke(lines, with: .color(lineColor), lineWidth: 0.75)
            var dots = Path()
            for dot in background.dots(in: rect, spacing: spacing) {
                dots.addEllipse(in: CGRect(x: dot.x - 1.25, y: dot.y - 1.25, width: 2.5, height: 2.5))
            }
            context.fill(dots, with: .color(lineColor))
            if let x = background.marginX(in: rect, spacing: spacing) {
                let margin = Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) }
                context.stroke(margin, with: .color(marginColor), lineWidth: 1)
            }
        }
        .background(theme.colors.surface)
        .accessibilityHidden(true)
    }
}
