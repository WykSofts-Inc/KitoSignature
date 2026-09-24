//
//  KitoSignatureSVG.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation
import CoreGraphics

/// Turns shapes into SVG path data (`d="…"`) and whole SVG documents.
public enum KitoSVG {
    /// A closed polygon as `M x y L x y … Z`, rounded to `precision` decimal places.
    public static func pathData(polygon: [CGPoint], precision: Int = 2) -> String {
        guard let first = polygon.first, polygon.count > 2 else { return "" }
        var parts = ["M\(number(first.x, precision)) \(number(first.y, precision))"]
        parts.reserveCapacity(polygon.count + 1)
        for point in polygon.dropFirst() {
            parts.append("L\(number(point.x, precision)) \(number(point.y, precision))")
        }
        parts.append("Z")
        return parts.joined(separator: " ")
    }

    /// The centre line of a stroke as quadratic curves through the midpoints of its samples
    /// (`M … Q … L …`) — for plotters and tools that want a single line per stroke.
    public static func centerlineData(_ points: [CGPoint], precision: Int = 2) -> String {
        guard let first = points.first else { return "" }
        var parts = ["M\(number(first.x, precision)) \(number(first.y, precision))"]
        guard points.count > 2 else {
            if let last = points.last, points.count == 2 {
                parts.append("L\(number(last.x, precision)) \(number(last.y, precision))")
            }
            return parts.joined(separator: " ")
        }
        for index in 1..<(points.count - 1) {
            let control = points[index]
            let mid = midpoint(points[index], points[index + 1])
            parts.append("Q\(number(control.x, precision)) \(number(control.y, precision)) \(number(mid.x, precision)) \(number(mid.y, precision))")
        }
        if let last = points.last {
            parts.append("L\(number(last.x, precision)) \(number(last.y, precision))")
        }
        return parts.joined(separator: " ")
    }

    /// Path data for any `CGPath`, including curves.
    public static func pathData(_ path: CGPath, precision: Int = 2) -> String {
        var parts: [String] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            parts.append(command(for: element, precision: precision))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// A standalone SVG document with one filled `<path>` per entry.
    public static func document(paths: [(data: String, fill: String, opacity: Double)], size: CGSize) -> String {
        let width = number(size.width, 2)
        let height = number(size.height, 2)
        var lines = ["<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(width)\" height=\"\(height)\" viewBox=\"0 0 \(width) \(height)\">"]
        for entry in paths where !entry.data.isEmpty {
            let opacity = entry.opacity < 1 ? " fill-opacity=\"\(number(entry.opacity, 2))\"" : ""
            lines.append("  <path d=\"\(entry.data)\" fill=\"\(entry.fill)\"\(opacity)/>")
        }
        lines.append("</svg>")
        return lines.joined(separator: "\n")
    }

    /// A number with at most `precision` decimals and no trailing zeros ("12", "3.5", "-0.25").
    public static func number(_ value: CGFloat, _ precision: Int) -> String {
        let factor = pow(10, Double(precision))
        let rounded = (Double(value) * factor).rounded() / factor
        let clean = rounded == 0 ? 0 : rounded
        var text = String(format: "%.\(precision)f", clean)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    private static func pair(_ point: CGPoint, _ precision: Int) -> String {
        "\(number(point.x, precision)) \(number(point.y, precision))"
    }

    private static func command(for element: CGPathElement, precision: Int) -> String {
        let p = element.points
        switch element.type {
        case .moveToPoint: return "M" + pair(p[0], precision)
        case .addLineToPoint: return "L" + pair(p[0], precision)
        case .addQuadCurveToPoint: return "Q" + pair(p[0], precision) + " " + pair(p[1], precision)
        case .addCurveToPoint:
            return "C" + pair(p[0], precision) + " " + pair(p[1], precision) + " " + pair(p[2], precision)
        case .closeSubpath: return "Z"
        @unknown default: return ""
        }
    }
}
