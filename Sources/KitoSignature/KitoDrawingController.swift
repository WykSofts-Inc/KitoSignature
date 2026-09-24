//
//  KitoDrawingController.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import PencilKit
import Observation

/// A drawing tool for `KitoDrawingCanvas` when Apple's tool picker is hidden.
public enum KitoDrawingTool: String, CaseIterable, Sendable, Identifiable {
    case pen
    case marker
    case pencil
    case eraser

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pen: "Pen"
        case .marker: "Marker"
        case .pencil: "Pencil"
        case .eraser: "Eraser"
        }
    }

    public var systemImage: String {
        switch self {
        case .pen: "pencil.tip"
        case .marker: "highlighter"
        case .pencil: "pencil"
        case .eraser: "eraser"
        }
    }
}

/// State for `KitoDrawingCanvas`: the PencilKit drawing, the paper, the current tool and colour,
/// undo/redo and export.
///
/// ```swift
/// @State private var sketch = KitoDrawingController(background: .grid)
///
/// KitoDrawingCanvas(controller: sketch)
/// let png = sketch.image()?.pngData()
/// ```
@MainActor
@Observable
public final class KitoDrawingController {
    public var drawing: PKDrawing
    public var background: KitoCanvasBackground
    /// Shows Apple's floating tool picker instead of the built-in toolbar.
    public var showsToolPicker: Bool
    public var tool: KitoDrawingTool
    public var ink: KitoInk
    /// Base line width for pen, marker and pencil.
    public var width: CGFloat
    public private(set) var canUndo = false
    public private(set) var canRedo = false
    /// The size of the canvas on screen.
    public internal(set) var canvasSize: CGSize = .zero

    @ObservationIgnored weak var canvasView: PKCanvasView?

    public init(drawing: PKDrawing = PKDrawing(), background: KitoCanvasBackground = .blank,
                tool: KitoDrawingTool = .pen, ink: KitoInk = .black, width: CGFloat = 4,
                showsToolPicker: Bool = false) {
        self.drawing = drawing
        self.background = background
        self.tool = tool
        self.ink = ink
        self.width = width
        self.showsToolPicker = showsToolPicker
    }

    public var isEmpty: Bool { drawing.strokes.isEmpty }

    /// The PencilKit tool for the current tool, colour and width.
    public var pencilKitTool: PKTool {
        let color = ink.exportColor
        switch tool {
        case .pen: return PKInkingTool(.pen, color: color, width: width)
        case .marker: return PKInkingTool(.marker, color: color, width: width * 4)
        case .pencil: return PKInkingTool(.pencil, color: color, width: width * 1.5)
        case .eraser: return PKEraserTool(.vector)
        }
    }

    public func undo() {
        canvasView?.undoManager?.undo()
        sync()
    }

    public func redo() {
        canvasView?.undoManager?.redo()
        sync()
    }

    /// Removes everything. Undo brings it back.
    public func clear() {
        guard !isEmpty else { return }
        let previous = drawing
        if let canvas = canvasView {
            canvas.undoManager?.registerUndo(withTarget: canvas) { view in
                view.drawing = previous
            }
            canvas.drawing = PKDrawing()
        }
        drawing = PKDrawing()
        sync()
    }

    /// Replaces the drawing, e.g. with one loaded from `PKDrawing(data:)`.
    public func load(_ newDrawing: PKDrawing) {
        drawing = newDrawing
        canvasView?.drawing = newDrawing
        canvasView?.undoManager?.removeAllActions()
        sync()
    }

    /// The drawing as an image, always in light appearance so dark ink stays dark. With
    /// `includesBackground` the paper pattern is drawn underneath on white.
    public func image(scale: CGFloat = 3, includesBackground: Bool = true) -> UIImage? {
        let size = exportSize
        guard size.width > 0, size.height > 0 else { return nil }
        let rect = CGRect(origin: .zero, size: size)
        var strokes = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            strokes = drawing.image(from: rect, scale: scale)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = includesBackground
        let paper = background
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            if includesBackground {
                UIColor.white.setFill()
                context.fill(rect)
                paper.draw(in: context.cgContext, rect: rect, spacing: 24,
                           line: UIColor.black.withAlphaComponent(0.12),
                           margin: UIColor.systemRed.withAlphaComponent(0.35))
            }
            strokes.draw(in: rect)
        }
    }

    /// `PKDrawing` data for saving.
    public var dataRepresentation: Data { drawing.dataRepresentation() }

    private var exportSize: CGSize {
        if canvasSize.width > 0, canvasSize.height > 0 { return canvasSize }
        let bounds = drawing.bounds
        return CGSize(width: bounds.maxX + 16, height: bounds.maxY + 16)
    }

    func sync() {
        if let canvas = canvasView, canvas.drawing != drawing { drawing = canvas.drawing }
        canUndo = canvasView?.undoManager?.canUndo ?? false
        canRedo = canvasView?.undoManager?.canRedo ?? false
    }
}
