//
//  KitoAnnotation.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI

/// What a finger does on `KitoAnnotationView`.
public enum KitoAnnotationTool: String, CaseIterable, Codable, Sendable, Identifiable {
    case pen
    case highlighter
    case arrow
    case text

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .arrow: "Arrow"
        case .text: "Text"
        }
    }

    public var systemImage: String {
        switch self {
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .arrow: "arrow.up.right"
        case .text: "textformat"
        }
    }
}

/// One mark on a photo, in the image's own point coordinates so it lands in the same place at
/// any display size and in the flattened export.
public struct KitoAnnotation: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: Codable, Hashable, Sendable {
        case pen([KitoSignaturePoint])
        case highlight([KitoSignaturePoint])
        case arrow(from: KitoSignaturePoint, to: KitoSignaturePoint)
        case text(String, at: KitoSignaturePoint)
    }

    public var id: UUID
    public var kind: Kind
    public var ink: KitoInk
    /// Line width in image points (text size is derived from it).
    public var lineWidth: Double

    public init(id: UUID = UUID(), kind: Kind, ink: KitoInk, lineWidth: Double) {
        self.id = id
        self.kind = kind
        self.ink = ink
        self.lineWidth = lineWidth
    }

    /// The font size used for `.text`, in image points.
    public var fontSize: Double { lineWidth * 5 }
}

/// Pure geometry for annotations.
public enum KitoAnnotationGeometry {
    /// Where an image of `imageSize` sits when scaled to fit (and centred in) `container`.
    public static func fitRect(for imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return .zero
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(x: (container.width - width) / 2, y: (container.height - height) / 2, width: width, height: height)
    }

    /// The two back corners of an arrowhead pointing at `to`.
    public static func arrowHead(from: CGPoint, to: CGPoint, length: CGFloat,
                                 spread: CGFloat = .pi / 7) -> (left: CGPoint, right: CGPoint) {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let left = CGPoint(x: to.x - length * cos(angle - spread), y: to.y - length * sin(angle - spread))
        let right = CGPoint(x: to.x - length * cos(angle + spread), y: to.y - length * sin(angle + spread))
        return (left, right)
    }

    /// A filled, even-width line through `points` with round ends.
    public static func linePath(_ points: [KitoSignaturePoint], width: Double) -> Path {
        let samples = points.map { KitoInkSample(x: $0.x, y: $0.y, width: width) }
        return KitoInkEngine.path(polygon: KitoInkEngine.outline(KitoInkEngine.smoothed(samples)))
    }

    /// The shaft and head of an arrow, to stroke with round caps.
    public static func arrowPath(from: CGPoint, to: CGPoint, width: Double) -> Path {
        let length = max(CGFloat(width) * 4.5, hypot(to.x - from.x, to.y - from.y) * 0.18)
        let head = arrowHead(from: from, to: to, length: min(length, CGFloat(width) * 9))
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        path.move(to: head.left)
        path.addLine(to: to)
        path.addLine(to: head.right)
        return path
    }

    /// Black or white text, whichever reads better on `ink`.
    public static func labelTextIsDark(on ink: KitoInk) -> Bool {
        let luminance = 0.2126 * ink.red + 0.7152 * ink.green + 0.0722 * ink.blue
        return luminance > 0.6
    }
}
