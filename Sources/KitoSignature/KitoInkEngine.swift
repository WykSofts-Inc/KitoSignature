//
//  KitoInkEngine.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI

/// A point on a smoothed stroke with the line width at that point.
public struct KitoInkSample: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double

    public init(x: Double, y: Double, width: Double) {
        self.x = x
        self.y = y
        self.width = width
    }

    public var location: CGPoint { CGPoint(x: x, y: y) }
}

/// The pure maths behind the pen: widths from speed, Catmull-Rom smoothing and the filled
/// outline of a variable-width line. Everything else — the pad, exports, SVG — draws through it,
/// so a signature looks the same everywhere.
public enum KitoInkEngine {
    /// Line widths for each point: slow is thick, fast is thin. Speed and width are both eased so
    /// a jittery finger doesn't make blotchy lines. Apple Pencil pressure, when present, scales
    /// the width.
    public static func widths(for points: [KitoSignaturePoint], pen: KitoPenStyle) -> [Double] {
        guard let first = points.first else { return [] }
        let startWidth = (pen.minWidth + pen.maxWidth) / 2
        var widths = [pressured(startWidth, first.pressure)]
        var velocity = pen.slowVelocity
        var width = startWidth
        for index in points.indices.dropFirst() {
            let measured = speed(from: points[index - 1], to: points[index])
            velocity = velocity * 0.6 + measured * 0.4
            let target = pen.width(forVelocity: velocity)
            width += (target - width) * pen.responsiveness
            widths.append(pressured(width, points[index].pressure))
        }
        return widths
    }

    /// Points per second between two samples. Samples closer than 1/240 s count as 1/240 s apart.
    public static func speed(from a: KitoSignaturePoint, to b: KitoSignaturePoint) -> Double {
        let dt = max(b.t - a.t, 1.0 / 240)
        return a.distance(to: b) / dt
    }

    /// A smooth curve through `samples` using uniform Catmull-Rom splines, with widths eased
    /// between samples. The curve passes through every original sample.
    public static func smoothed(_ samples: [KitoInkSample], spacing: Double = 2) -> [KitoInkSample] {
        guard samples.count > 2 else { return samples }
        var result: [KitoInkSample] = [samples[0]]
        for index in 0..<(samples.count - 1) {
            let p0 = samples[max(index - 1, 0)]
            let p1 = samples[index]
            let p2 = samples[index + 1]
            let p3 = samples[min(index + 2, samples.count - 1)]
            let length = hypot(p2.x - p1.x, p2.y - p1.y)
            let steps = min(max(Int(length / max(spacing, 0.1)), 1), 24)
            for step in 1...steps {
                let t = Double(step) / Double(steps)
                result.append(catmullRom(p0, p1, p2, p3, t: t))
            }
        }
        return result
    }

    /// One point on a Catmull-Rom segment between `p1` and `p2`.
    public static func catmullRom(_ p0: KitoInkSample, _ p1: KitoInkSample, _ p2: KitoInkSample,
                                  _ p3: KitoInkSample, t: Double) -> KitoInkSample {
        let x = catmullRom(p0.x, p1.x, p2.x, p3.x, t: t)
        let y = catmullRom(p0.y, p1.y, p2.y, p3.y, t: t)
        let width = p1.width + (p2.width - p1.width) * t
        return KitoInkSample(x: x, y: y, width: width)
    }

    static func catmullRom(_ a: Double, _ b: Double, _ c: Double, _ d: Double, t: Double) -> Double {
        let t2 = t * t
        let t3 = t2 * t
        let linear = (c - a) * t
        let quadratic = (2 * a - 5 * b + 4 * c - d) * t2
        let cubic = (3 * b - a - 3 * c + d) * t3
        return 0.5 * (2 * b + linear + quadratic + cubic)
    }

    /// The raw points of a stroke with their widths, dropping repeats closer than `pen.minDistance`.
    public static func samples(for stroke: KitoSignatureStroke) -> [KitoInkSample] {
        let points = deduplicated(stroke.points, minDistance: stroke.pen.minDistance * 0.5)
        let widths = widths(for: points, pen: stroke.pen)
        return zip(points, widths).map { KitoInkSample(x: $0.x, y: $0.y, width: $1) }
    }

    static func deduplicated(_ points: [KitoSignaturePoint], minDistance: Double) -> [KitoSignaturePoint] {
        guard var last = points.first else { return [] }
        var result = [last]
        for point in points.dropFirst() where point.distance(to: last) >= minDistance {
            result.append(point)
            last = point
        }
        if let final = points.last, result.count > 1, final != last {
            result[result.count - 1] = final
        }
        return result
    }

    /// The closed outline of a variable-width line with round ends. Filling it (non-zero rule)
    /// draws the stroke. A single sample becomes a dot.
    public static func outline(_ samples: [KitoInkSample], capSegments: Int = 8) -> [CGPoint] {
        guard let first = samples.first else { return [] }
        guard samples.count > 1 else { return dot(first, segments: capSegments * 2) }
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        left.reserveCapacity(samples.count)
        right.reserveCapacity(samples.count)
        for index in samples.indices {
            let direction = tangent(samples, at: index)
            let normal = CGPoint(x: -direction.y, y: direction.x)
            let half = samples[index].width / 2
            left.append(offset(samples[index], normal, half))
            right.append(offset(samples[index], normal, -half))
        }
        let endDirection = tangent(samples, at: samples.count - 1)
        let startDirection = tangent(samples, at: 0)
        var polygon = left
        polygon += cap(around: samples[samples.count - 1], direction: endDirection, segments: capSegments)
        polygon += right.reversed()
        let back = CGPoint(x: -startDirection.x, y: -startDirection.y)
        polygon += cap(around: first, direction: back, segments: capSegments)
        return polygon
    }

    /// The filled shape of a stroke, ready to draw.
    public static func path(for stroke: KitoSignatureStroke) -> Path {
        path(polygon: outline(smoothed(samples(for: stroke))))
    }

    /// A closed path through `polygon`.
    public static func path(polygon: [CGPoint]) -> Path {
        var path = Path()
        guard polygon.count > 2 else { return path }
        path.addLines(polygon)
        path.closeSubpath()
        return path
    }

    // MARK: Helpers

    private static func pressured(_ width: Double, _ pressure: Double?) -> Double {
        guard let pressure else { return width }
        let clamped = min(max(pressure, 0), 1)
        return width * (0.45 + clamped * 1.1)
    }

    private static func tangent(_ samples: [KitoInkSample], at index: Int) -> CGPoint {
        let before = samples[max(index - 1, 0)]
        let after = samples[min(index + 1, samples.count - 1)]
        return unit(dx: after.x - before.x, dy: after.y - before.y)
    }

    private static func unit(dx: Double, dy: Double) -> CGPoint {
        let length = hypot(dx, dy)
        guard length > 0 else { return CGPoint(x: 1, y: 0) }
        return CGPoint(x: dx / length, y: dy / length)
    }

    private static func offset(_ sample: KitoInkSample, _ normal: CGPoint, _ distance: Double) -> CGPoint {
        CGPoint(x: sample.x + Double(normal.x) * distance, y: sample.y + Double(normal.y) * distance)
    }

    /// A half circle from the left edge, around the front, to the right edge.
    private static func cap(around sample: KitoInkSample, direction: CGPoint, segments: Int) -> [CGPoint] {
        let normal = CGPoint(x: -direction.y, y: direction.x)
        let radius = sample.width / 2
        let count = max(segments, 2)
        var points: [CGPoint] = []
        for step in 1..<count {
            let angle = Double.pi * Double(step) / Double(count)
            points.append(capPoint(sample, normal, direction, radius, angle))
        }
        return points
    }

    private static func capPoint(_ sample: KitoInkSample, _ normal: CGPoint, _ direction: CGPoint,
                                 _ radius: Double, _ angle: Double) -> CGPoint {
        let along = cos(angle) * radius
        let forward = sin(angle) * radius
        let x = sample.x + Double(normal.x) * along + Double(direction.x) * forward
        let y = sample.y + Double(normal.y) * along + Double(direction.y) * forward
        return CGPoint(x: x, y: y)
    }

    private static func dot(_ sample: KitoInkSample, segments: Int) -> [CGPoint] {
        let radius = max(sample.width, 0.5) * 0.6
        return (0..<max(segments, 6)).map { step in
            let angle = 2 * Double.pi * Double(step) / Double(max(segments, 6))
            return CGPoint(x: sample.x + cos(angle) * radius, y: sample.y + sin(angle) * radius)
        }
    }
}
