//
//  KitoSignatureModel.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import Observation

/// The state behind `KitoSignaturePad` and `KitoSketchCanvas`: finished strokes, the stroke in
/// progress, the ink and pen, and undo/redo.
///
/// ```swift
/// @State private var signature = KitoSignatureModel()
///
/// KitoSignaturePad(model: signature)
/// Button("Save") { save(signature.data) }.disabled(!signature.isValid)
/// ```
@MainActor
@Observable
public final class KitoSignatureModel {
    /// Finished strokes, oldest first.
    public private(set) var strokes: [KitoSignatureStroke]
    /// The stroke being drawn right now.
    public private(set) var activeStroke: KitoSignatureStroke?
    /// The ink for the next stroke.
    public var ink: KitoInk
    /// The pen for the next stroke.
    public var pen: KitoPenStyle
    public var validator: KitoSignatureValidator
    /// The size of the pad, set by the view.
    public var canvasSize: CGSize
    public private(set) var createdAt: Date

    private var history: KitoUndoStack<[KitoSignatureStroke]>
    @ObservationIgnored private var origin: Date?
    @ObservationIgnored private var pathCache: [UUID: Path] = [:]

    public init(data: KitoSignatureData = KitoSignatureData(), ink: KitoInk = .automatic,
                pen: KitoPenStyle = .fountain, validator: KitoSignatureValidator = KitoSignatureValidator()) {
        self.strokes = data.strokes
        self.canvasSize = data.canvasSize
        self.createdAt = data.createdAt
        self.ink = ink
        self.pen = pen
        self.validator = validator
        self.history = KitoUndoStack(data.strokes)
    }

    // MARK: State

    /// Everything drawn so far, including the stroke in progress.
    public var data: KitoSignatureData {
        KitoSignatureData(strokes: allStrokes, canvasSize: canvasSize, createdAt: createdAt)
    }

    public var allStrokes: [KitoSignatureStroke] {
        if let activeStroke { return strokes + [activeStroke] }
        return strokes
    }

    public var isEmpty: Bool { strokes.isEmpty && activeStroke == nil }
    public var isDrawing: Bool { activeStroke != nil }
    public var validation: KitoSignatureValidation { validator.validate(data) }
    public var isValid: Bool { validation.isValid }
    public var canUndo: Bool { history.canUndo }
    public var canRedo: Bool { history.canRedo }

    // MARK: Drawing

    /// Starts a stroke at `location`. `date` is when the touch happened.
    public func begin(at location: CGPoint, date: Date = Date(), pressure: Double? = nil) {
        if activeStroke != nil { end() }
        let start = origin ?? startClock(at: date)
        let point = KitoSignaturePoint(location, t: date.timeIntervalSince(start), pressure: pressure)
        activeStroke = KitoSignatureStroke(points: [point], ink: ink, pen: pen)
    }

    /// Adds a point to the stroke in progress. Points closer than `pen.minDistance` are skipped.
    public func extend(to location: CGPoint, date: Date = Date(), pressure: Double? = nil) {
        guard var stroke = activeStroke, let start = origin else {
            begin(at: location, date: date, pressure: pressure)
            return
        }
        let point = KitoSignaturePoint(location, t: date.timeIntervalSince(start), pressure: pressure)
        if let last = stroke.points.last, last.distance(to: point) < stroke.pen.minDistance { return }
        stroke.points.append(point)
        activeStroke = stroke
    }

    /// Finishes the stroke in progress and records it for undo.
    public func end() {
        guard let stroke = activeStroke else { return }
        activeStroke = nil
        strokes.append(stroke)
        history.push(strokes)
    }

    /// Drops the stroke in progress without keeping it.
    public func cancelStroke() {
        activeStroke = nil
    }

    // MARK: Editing

    public func undo() {
        cancelStroke()
        if let restored = history.undo() { strokes = restored }
    }

    public func redo() {
        cancelStroke()
        if let restored = history.redo() { strokes = restored }
    }

    /// Removes every stroke. Undo brings them back.
    public func clear() {
        cancelStroke()
        guard !strokes.isEmpty else { return }
        strokes = []
        history.push(strokes)
        origin = nil
    }

    /// Removes strokes passing within `radius` of `location`. Call `commitErase()` when the
    /// eraser lifts so the whole gesture undoes in one step.
    public func erase(at location: CGPoint, radius: Double = 12) {
        let kept = strokes.filter { $0.distance(to: location) > radius + $0.pen.maxWidth / 2 }
        if kept.count != strokes.count { strokes = kept }
    }

    public func commitErase() {
        history.push(strokes)
    }

    /// Replaces everything with a saved signature and starts a fresh history.
    public func load(_ data: KitoSignatureData) {
        cancelStroke()
        strokes = data.strokes
        canvasSize = data.canvasSize
        createdAt = data.createdAt
        history.reset(to: data.strokes)
        origin = nil
    }

    // MARK: Rendering

    /// The filled path of a stroke, cached for finished strokes.
    public func path(for stroke: KitoSignatureStroke) -> Path {
        if stroke.id == activeStroke?.id { return KitoInkEngine.path(for: stroke) }
        if let cached = pathCache[stroke.id] { return cached }
        let path = KitoInkEngine.path(for: stroke)
        if pathCache.count > 400 { pathCache.removeAll() }
        pathCache[stroke.id] = path
        return path
    }

    private func startClock(at date: Date) -> Date {
        if strokes.isEmpty { createdAt = date }
        let lastT = strokes.last?.points.last?.t ?? 0
        let start = date.addingTimeInterval(-(strokes.isEmpty ? 0 : lastT + 0.4))
        origin = start
        return start
    }
}
