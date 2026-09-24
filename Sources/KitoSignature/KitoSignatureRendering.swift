//
//  KitoSignatureRendering.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import UIKit

/// A filled shape and the ink to fill it with.
public struct KitoInkPath {
    public var path: Path
    public var ink: KitoInk

    public init(path: Path, ink: KitoInk) {
        self.path = path
        self.ink = ink
    }
}

/// What sits behind the ink in an export.
public enum KitoSignatureBackground: Equatable, Sendable {
    /// A transparent PNG, ready to lay over a document.
    case transparent
    /// Paper white.
    case white
    case color(KitoInk)

    var fill: UIColor? {
        switch self {
        case .transparent: nil
        case .white: .white
        case .color(let ink): ink.exportColor
        }
    }
}

/// Anything that draws as filled ink — a drawn signature, a typed one, or a captured result.
/// Conforming gives you PNG, PDF and SVG export for free.
public protocol KitoSignatureRenderable {
    /// Filled shapes in the signature's own coordinates.
    func inkPaths() -> [KitoInkPath]
}

public extension KitoSignatureRenderable {
    /// The area the ink covers, or `.null` when there is none.
    var inkBounds: CGRect {
        inkPaths().reduce(CGRect.null) { $0.union($1.path.boundingRect) }
    }

    /// Renders the ink as an image. With `size` the ink is scaled to fit; without, the image is
    /// cropped to the ink plus `padding`. `ink` overrides every stroke's colour.
    func image(size: CGSize? = nil, padding: CGFloat = 12, scale: CGFloat = 3,
               background: KitoSignatureBackground = .transparent, ink: KitoInk? = nil) -> UIImage? {
        guard let layout = KitoSignatureLayout(bounds: inkBounds, size: size, padding: padding) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = background.fill != nil
        let renderer = UIGraphicsImageRenderer(size: layout.canvas, format: format)
        let paths = inkPaths()
        return renderer.image { context in
            KitoSignatureLayout.draw(paths, in: context.cgContext, layout: layout,
                                     background: background, ink: ink)
        }
    }

    /// PNG data — transparent unless you pass a background.
    func pngData(size: CGSize? = nil, padding: CGFloat = 12, scale: CGFloat = 3,
                 background: KitoSignatureBackground = .transparent, ink: KitoInk? = nil) -> Data? {
        image(size: size, padding: padding, scale: scale, background: background, ink: ink)?.pngData()
    }

    /// A one-page vector PDF of the ink.
    func pdfData(size: CGSize? = nil, padding: CGFloat = 12,
                 background: KitoSignatureBackground = .transparent, ink: KitoInk? = nil) -> Data? {
        guard let layout = KitoSignatureLayout(bounds: inkBounds, size: size, padding: padding) else { return nil }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: layout.canvas))
        let paths = inkPaths()
        return renderer.pdfData { context in
            context.beginPage()
            KitoSignatureLayout.draw(paths, in: context.cgContext, layout: layout,
                                     background: background, ink: ink)
        }
    }

    /// A standalone SVG document with one filled path per stroke.
    func svg(size: CGSize? = nil, padding: CGFloat = 12, ink: KitoInk? = nil, precision: Int = 2) -> String? {
        guard let layout = KitoSignatureLayout(bounds: inkBounds, size: size, padding: padding) else { return nil }
        let entries = inkPaths().map { item in
            let moved = item.path.applying(layout.transform)
            let color = ink ?? item.ink
            return (data: KitoSVG.pathData(moved.cgPath, precision: precision), fill: color.hex, opacity: color.opacity)
        }
        return KitoSVG.document(paths: entries, size: layout.canvas)
    }

    /// Just the path data (`d` attribute) of every stroke joined together, in the signature's own
    /// coordinates.
    func svgPathData(precision: Int = 2) -> String {
        inkPaths().map { KitoSVG.pathData($0.path.cgPath, precision: precision) }.joined(separator: " ")
    }
}

extension KitoSignatureData: KitoSignatureRenderable {
    public func inkPaths() -> [KitoInkPath] {
        strokes.filter { !$0.points.isEmpty }.map { KitoInkPath(path: KitoInkEngine.path(for: $0), ink: $0.ink) }
    }
}

/// Where exported ink lands on the page.
struct KitoSignatureLayout {
    var canvas: CGSize
    var transform: CGAffineTransform

    init(canvas: CGSize, transform: CGAffineTransform) {
        self.canvas = canvas
        self.transform = transform
    }

    init?(bounds: CGRect, size: CGSize?, padding: CGFloat) {
        guard !bounds.isNull, !bounds.isInfinite else { return nil }
        if let size, size.width > 0, size.height > 0 {
            canvas = size
            transform = KitoSignatureGeometry.fitTransform(from: bounds, into: CGRect(origin: .zero, size: size),
                                                           padding: padding)
        } else {
            canvas = CGSize(width: ceil(bounds.width + padding * 2), height: ceil(bounds.height + padding * 2))
            transform = CGAffineTransform(translationX: padding - bounds.minX, y: padding - bounds.minY)
        }
    }

    static func draw(_ paths: [KitoInkPath], in context: CGContext, layout: KitoSignatureLayout,
                     background: KitoSignatureBackground, ink: KitoInk?) {
        if let fill = background.fill {
            context.setFillColor(fill.cgColor)
            context.fill(CGRect(origin: .zero, size: layout.canvas))
        }
        for item in paths {
            let color = (ink ?? item.ink).exportColor
            context.addPath(item.path.applying(layout.transform).cgPath)
            context.setFillColor(color.cgColor)
            context.fillPath()
        }
    }
}
