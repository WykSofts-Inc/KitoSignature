//
//  KitoAnnotationModel.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import UIKit
import Observation

/// State for `KitoAnnotationView`: the photo, its marks, the current tool and ink, undo/redo, and
/// the flattened export.
///
/// ```swift
/// @State private var markup = KitoAnnotationModel(image: parcelPhoto)
///
/// KitoAnnotationView(model: markup)
/// let proof = markup.flattenedImage()
/// ```
@MainActor
@Observable
public final class KitoAnnotationModel {
    public var image: UIImage
    public private(set) var annotations: [KitoAnnotation]
    /// The mark being drawn right now.
    public private(set) var draft: KitoAnnotation?
    public var tool: KitoAnnotationTool
    public var ink: KitoInk
    /// Multiplies the default line width (about 0.8% of the image width).
    public var thickness: Double

    private var history: KitoUndoStack<[KitoAnnotation]>

    public init(image: UIImage, annotations: [KitoAnnotation] = [], tool: KitoAnnotationTool = .pen,
                ink: KitoInk = .red, thickness: Double = 1) {
        self.image = image
        self.annotations = annotations
        self.tool = tool
        self.ink = ink
        self.thickness = thickness
        self.history = KitoUndoStack(annotations)
    }

    public var canUndo: Bool { history.canUndo }
    public var canRedo: Bool { history.canRedo }
    public var isEmpty: Bool { annotations.isEmpty }
    /// Finished marks plus the one in progress.
    public var visibleAnnotations: [KitoAnnotation] {
        if let draft { return annotations + [draft] }
        return annotations
    }

    /// Line width in image points for the current tool.
    public var lineWidth: Double {
        let base = max(Double(image.size.width) * 0.008, 2) * thickness
        return tool == .highlighter ? base * 3.5 : base
    }

    // MARK: Drawing (image coordinates)

    public func begin(at point: CGPoint) {
        let start = KitoSignaturePoint(point)
        let kind: KitoAnnotation.Kind
        switch tool {
        case .pen: kind = .pen([start])
        case .highlighter: kind = .highlight([start])
        case .arrow: kind = .arrow(from: start, to: start)
        case .text: return
        }
        let markInk = tool == .highlighter ? ink.opacity(0.4) : ink
        draft = KitoAnnotation(kind: kind, ink: markInk, lineWidth: lineWidth)
    }

    public func extend(to point: CGPoint) {
        guard var mark = draft else { return }
        let next = KitoSignaturePoint(point)
        switch mark.kind {
        case .pen(let points):
            guard let last = points.last, last.distance(to: next) >= 1.5 else { return }
            mark.kind = .pen(points + [next])
        case .highlight(let points):
            guard let last = points.last, last.distance(to: next) >= 1.5 else { return }
            mark.kind = .highlight(points + [next])
        case .arrow(let from, _):
            mark.kind = .arrow(from: from, to: next)
        case .text:
            return
        }
        draft = mark
    }

    /// Keeps the mark in progress. Arrows shorter than a few line widths are dropped.
    public func end() {
        guard let mark = draft else { return }
        draft = nil
        if case .arrow(let from, let to) = mark.kind, from.distance(to: to) < mark.lineWidth * 3 { return }
        commit(annotations + [mark])
    }

    /// Adds a text label centred on `point`.
    public func addText(_ text: String, at point: CGPoint) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let width = max(Double(image.size.width) * 0.008, 2) * thickness
        let label = KitoAnnotation(kind: .text(clean, at: KitoSignaturePoint(point)), ink: ink, lineWidth: width)
        commit(annotations + [label])
    }

    public func remove(_ id: KitoAnnotation.ID) {
        commit(annotations.filter { $0.id != id })
    }

    public func undo() {
        draft = nil
        if let restored = history.undo() { annotations = restored }
    }

    public func redo() {
        draft = nil
        if let restored = history.redo() { annotations = restored }
    }

    public func clear() {
        draft = nil
        commit([])
    }

    private func commit(_ next: [KitoAnnotation]) {
        annotations = next
        history.push(next)
    }

    // MARK: Export

    /// The photo with every mark burned in, at the photo's full resolution.
    public func flattenedImage() -> UIImage {
        let size = image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let marks = annotations
        let photo = image
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            photo.draw(in: CGRect(origin: .zero, size: size))
            for mark in marks {
                KitoAnnotationDrawing.draw(mark, in: context.cgContext)
            }
        }
    }
}

/// Core Graphics drawing for exports — mirrors what `KitoAnnotationView` draws on screen.
enum KitoAnnotationDrawing {
    static func draw(_ mark: KitoAnnotation, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        let color = mark.ink.exportColor.cgColor
        switch mark.kind {
        case .pen(let points):
            context.addPath(KitoAnnotationGeometry.linePath(points, width: mark.lineWidth).cgPath)
            context.setFillColor(color)
            context.fillPath()
        case .highlight(let points):
            context.setBlendMode(.multiply)
            context.addPath(KitoAnnotationGeometry.linePath(points, width: mark.lineWidth).cgPath)
            context.setFillColor(color)
            context.fillPath()
        case .arrow(let from, let to):
            let path = KitoAnnotationGeometry.arrowPath(from: from.location, to: to.location, width: mark.lineWidth)
            context.addPath(path.cgPath)
            context.setStrokeColor(color)
            context.setLineWidth(CGFloat(mark.lineWidth))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()
        case .text(let text, let at):
            drawLabel(text, at: at.location, mark: mark, in: context)
        }
    }

    private static func drawLabel(_ text: String, at center: CGPoint, mark: KitoAnnotation, in context: CGContext) {
        let font = UIFont.systemFont(ofSize: CGFloat(mark.fontSize), weight: .bold)
        let dark = KitoAnnotationGeometry.labelTextIsDark(on: mark.ink)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: dark ? UIColor.black : UIColor.white]
        let string = NSAttributedString(string: text, attributes: attributes)
        let textSize = string.size()
        let pill = labelRect(textSize: textSize, center: center, fontSize: CGFloat(mark.fontSize))
        context.addPath(UIBezierPath(roundedRect: pill, cornerRadius: pill.height / 2).cgPath)
        context.setFillColor(mark.ink.exportColor.cgColor)
        context.fillPath()
        UIGraphicsPushContext(context)
        string.draw(at: CGPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2))
        UIGraphicsPopContext()
    }

    /// The pill behind a label.
    static func labelRect(textSize: CGSize, center: CGPoint, fontSize: CGFloat) -> CGRect {
        let padX = fontSize * 0.6
        let padY = fontSize * 0.3
        let width = textSize.width + padX * 2
        let height = textSize.height + padY * 2
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }
}
