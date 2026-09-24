//
//  KitoSignatureData.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation
import CoreGraphics

/// One sampled touch: where, when (seconds since the signature began) and, from Apple Pencil, how
/// hard.
public struct KitoSignaturePoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    /// Seconds since the first point of the signature.
    public var t: Double
    /// 0...1 from Apple Pencil, `nil` for a finger.
    public var pressure: Double?

    public init(x: Double, y: Double, t: Double = 0, pressure: Double? = nil) {
        self.x = x
        self.y = y
        self.t = t
        self.pressure = pressure
    }

    public init(_ location: CGPoint, t: Double = 0, pressure: Double? = nil) {
        self.init(x: Double(location.x), y: Double(location.y), t: t, pressure: pressure)
    }

    public var location: CGPoint { CGPoint(x: x, y: y) }

    enum CodingKeys: String, CodingKey {
        case x, y, t
        case pressure = "p"
    }

    func distance(to other: KitoSignaturePoint) -> Double {
        let dx = other.x - x
        let dy = other.y - y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// One continuous line, from touch down to touch up, with the ink and pen it was drawn with.
public struct KitoSignatureStroke: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var points: [KitoSignaturePoint]
    public var ink: KitoInk
    public var pen: KitoPenStyle

    public init(id: UUID = UUID(), points: [KitoSignaturePoint], ink: KitoInk = .automatic,
                pen: KitoPenStyle = .fountain) {
        self.id = id
        self.points = points
        self.ink = ink
        self.pen = pen
    }

    /// The distance the pen travelled.
    public var length: Double {
        guard points.count > 1 else { return 0 }
        var total = 0.0
        for index in 1..<points.count {
            total += points[index - 1].distance(to: points[index])
        }
        return total
    }

    /// The smallest rectangle around the stroke's points (not including line width).
    public var boundingBox: CGRect {
        KitoSignatureGeometry.bounds(of: points)
    }

    /// The shortest distance from `location` to the stroke's centre line.
    public func distance(to location: CGPoint) -> Double {
        let target = KitoSignaturePoint(location)
        guard let first = points.first else { return .infinity }
        guard points.count > 1 else { return first.distance(to: target) }
        var best = Double.infinity
        for index in 1..<points.count {
            let d = KitoSignatureGeometry.distance(from: target, toSegment: points[index - 1], points[index])
            best = min(best, d)
        }
        return best
    }

    func transformed(scale: Double, dx: Double, dy: Double) -> KitoSignatureStroke {
        var copy = self
        copy.points = points.map { point in
            KitoSignaturePoint(x: point.x * scale + dx, y: point.y * scale + dy, t: point.t, pressure: point.pressure)
        }
        copy.pen = pen.scaled(by: scale)
        return copy
    }
}

/// A drawn signature: every stroke with its timing, plus the size of the pad it was drawn on.
///
/// It is `Codable`, so store it as JSON and re-render it at any size later — as a thumbnail, a PNG
/// on white, a PDF or an SVG path — or replay it stroke by stroke.
public struct KitoSignatureData: Codable, Hashable, Sendable {
    public var strokes: [KitoSignatureStroke]
    /// The size of the pad the strokes were drawn in.
    public var canvasSize: CGSize
    public var createdAt: Date

    public init(strokes: [KitoSignatureStroke] = [], canvasSize: CGSize = .zero, createdAt: Date = Date()) {
        self.strokes = strokes
        self.canvasSize = canvasSize
        self.createdAt = createdAt
    }

    public static func == (lhs: KitoSignatureData, rhs: KitoSignatureData) -> Bool {
        lhs.strokes == rhs.strokes && lhs.canvasSize == rhs.canvasSize && lhs.createdAt == rhs.createdAt
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(strokes)
        hasher.combine(canvasSize.width)
        hasher.combine(canvasSize.height)
        hasher.combine(createdAt)
    }

    /// No strokes, or strokes without points.
    public var isEmpty: Bool { strokes.allSatisfy { $0.points.isEmpty } }
    public var pointCount: Int { strokes.reduce(0) { $0 + $1.points.count } }
    /// The total distance the pen travelled across all strokes.
    public var inkLength: Double { strokes.reduce(0) { $0 + $1.length } }

    /// The smallest rectangle around every point, or `.null` when empty.
    public var boundingBox: CGRect {
        KitoSignatureGeometry.bounds(of: strokes.flatMap(\.points))
    }

    /// Moves and scales every point (and the pen widths) together.
    public func transformed(scale: Double, dx: Double = 0, dy: Double = 0) -> KitoSignatureData {
        var copy = self
        copy.strokes = strokes.map { $0.transformed(scale: scale, dx: dx, dy: dy) }
        copy.canvasSize = CGSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
        return copy
    }

    /// The signature moved to the origin and scaled so its longer side is 1, keeping its shape.
    /// `canvasSize` becomes the normalised bounding box.
    public func normalized() -> KitoSignatureData {
        let box = boundingBox
        guard !box.isNull else { return self }
        let side = Double(max(box.width, box.height))
        let scale = side > 0 ? 1 / side : 1
        var copy = transformed(scale: scale, dx: -Double(box.minX) * scale, dy: -Double(box.minY) * scale)
        copy.canvasSize = CGSize(width: Double(box.width) * scale, height: Double(box.height) * scale)
        return copy
    }

    /// The signature scaled and centred to fit inside `rect` (keeping its aspect ratio), inset by
    /// `padding`. Pen widths scale too.
    public func fitted(in rect: CGRect, padding: CGFloat = 0) -> KitoSignatureData {
        let box = boundingBox
        guard !box.isNull else { return self }
        let transform = KitoSignatureGeometry.fitTransform(from: box, into: rect, padding: padding)
        var copy = transformed(scale: Double(transform.a), dx: Double(transform.tx), dy: Double(transform.ty))
        copy.canvasSize = rect.size
        return copy
    }

    /// JSON for storage.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Reads a signature saved with `jsonData()`.
    public init(jsonData: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self = try decoder.decode(KitoSignatureData.self, from: jsonData)
    }
}

// MARK: - Replay

public extension KitoSignatureData {
    /// Pauses between strokes longer than this are shortened when replaying.
    static let maxReplayPause: Double = 0.25

    /// How long `replayed(upTo:)` takes to draw the whole signature.
    var replayDuration: Double {
        replayTimeline.last?.end ?? 0
    }

    /// The signature as it looked `seconds` into a replay: whole strokes, then part of the
    /// current one. Long pauses between strokes are shortened.
    func replayed(upTo seconds: Double) -> KitoSignatureData {
        var copy = self
        copy.strokes = []
        for (stroke, span) in zip(strokes, replayTimeline) where seconds >= span.start {
            let base = stroke.points.first?.t ?? 0
            var partial = stroke
            partial.points = stroke.points.filter { $0.t - base + span.start <= seconds }
            if partial.points.isEmpty, let first = stroke.points.first { partial.points = [first] }
            copy.strokes.append(partial)
        }
        return copy
    }

    private var replayTimeline: [(start: Double, end: Double)] {
        var result: [(start: Double, end: Double)] = []
        var clock = 0.0
        var previousEnd: Double?
        for stroke in strokes {
            let first = stroke.points.first?.t ?? 0
            let last = stroke.points.last?.t ?? first
            if let previousEnd {
                clock += min(max(first - previousEnd, 0), Self.maxReplayPause)
            }
            let duration = max(last - first, 0)
            result.append((clock, clock + duration))
            clock += duration
            previousEnd = last
        }
        return result
    }
}

// MARK: - Geometry helpers

enum KitoSignatureGeometry {
    static func bounds(of points: [KitoSignaturePoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func distance(from p: KitoSignaturePoint, toSegment a: KitoSignaturePoint,
                         _ b: KitoSignaturePoint) -> Double {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let lengthSquared = abx * abx + aby * aby
        guard lengthSquared > 0 else { return p.distance(to: a) }
        let raw = ((p.x - a.x) * abx + (p.y - a.y) * aby) / lengthSquared
        let t = min(max(raw, 0), 1)
        let closest = KitoSignaturePoint(x: a.x + abx * t, y: a.y + aby * t)
        return p.distance(to: closest)
    }

    /// A uniform scale plus translation that centres `content` inside `rect` inset by `padding`.
    static func fitTransform(from content: CGRect, into rect: CGRect, padding: CGFloat) -> CGAffineTransform {
        let target = rect.insetBy(dx: padding, dy: padding)
        guard !content.isNull, target.width > 0, target.height > 0 else { return .identity }
        let scale = fitScale(content.size, into: target.size)
        let dx = target.midX - content.midX * scale
        let dy = target.midY - content.midY * scale
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: dx, ty: dy)
    }

    static func fitScale(_ content: CGSize, into target: CGSize) -> CGFloat {
        let sx = content.width > 0 ? target.width / content.width : .infinity
        let sy = content.height > 0 ? target.height / content.height : .infinity
        let scale = min(sx, sy)
        return scale.isFinite ? scale : 1
    }
}
