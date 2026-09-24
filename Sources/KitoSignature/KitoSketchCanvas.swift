//
//  KitoSketchCanvas.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// A lightweight drawing canvas in pure SwiftUI — no PencilKit — using the same pen engine as
/// the signature pad. Pen, marker and a stroke eraser, colours, paper and undo/redo.
///
/// ```swift
/// @State private var sketch = KitoSignatureModel(pen: .ballpoint, validator: .lenient)
///
/// KitoSketchCanvas(model: sketch, background: .grid)
/// let image = sketch.canvasImage(background: .grid)
/// ```
public struct KitoSketchCanvas: View {
    public enum Tool: String, CaseIterable, Identifiable, Sendable {
        case pen, marker, eraser

        public var id: String { rawValue }

        var title: String {
            switch self {
            case .pen: "Pen"
            case .marker: "Marker"
            case .eraser: "Eraser"
            }
        }

        var systemImage: String {
            switch self {
            case .pen: "pencil.tip"
            case .marker: "highlighter"
            case .eraser: "eraser"
            }
        }
    }

    @Bindable private var model: KitoSignatureModel
    private let inks: [KitoInk]
    private let showsToolbar: Bool
    private let tint: Color?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var background: KitoCanvasBackground
    @State private var tool: Tool = .pen
    @State private var eraserLocation: CGPoint?

    public init(model: KitoSignatureModel, background: KitoCanvasBackground = .dotted,
                inks: [KitoInk] = [.automatic, .royalBlue, .red, .forest, .orange],
                showsToolbar: Bool = true, tint: Color? = nil) {
        self.model = model
        self.inks = inks
        self.showsToolbar = showsToolbar
        self.tint = tint
        self._background = State(initialValue: background)
    }

    private var accent: Color { tint ?? theme.colors.primary }

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                KitoCanvasBackgroundView(background)
                inkLayer
                eraserCursor
            }
            .contentShape(Rectangle())
            .gesture(gesture)
            .onAppear { adopt(proxy.size) }
            .onChange(of: proxy.size) { _, size in adopt(size) }
        }
        .overlay(alignment: .topTrailing) {
            if showsToolbar { topBar.padding(theme.spacing.sm) }
        }
        .overlay(alignment: .bottom) {
            if showsToolbar { toolBar.padding(theme.spacing.sm) }
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous)
            .strokeBorder(theme.colors.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sketch canvas")
    }

    private var inkLayer: some View {
        let strokes = model.allStrokes
        let adaptive = theme.colors.onSurface
        return Canvas { context, _ in
            for stroke in strokes {
                context.fill(model.path(for: stroke), with: .color(stroke.ink.color(adaptive: adaptive)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var eraserCursor: some View {
        if let eraserLocation {
            Circle()
                .strokeBorder(theme.colors.onSurface.opacity(0.5), lineWidth: 1.5)
                .background(Circle().fill(theme.colors.surface.opacity(0.4)))
                .frame(width: 28, height: 28)
                .position(eraserLocation)
                .allowsHitTesting(false)
        }
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if tool == .eraser {
                    eraserLocation = value.location
                    model.erase(at: value.location, radius: 14)
                } else if model.isDrawing {
                    model.extend(to: value.location, date: value.time)
                } else {
                    model.begin(at: value.location, date: value.time)
                }
            }
            .onEnded { _ in
                if tool == .eraser {
                    eraserLocation = nil
                    model.commitErase()
                } else {
                    model.end()
                }
            }
    }

    private var topBar: some View {
        HStack(spacing: theme.spacing.xs) {
            KitoSignatureToolButton("Undo", systemImage: "arrow.uturn.backward", isEnabled: model.canUndo) { model.undo() }
            KitoSignatureToolButton("Redo", systemImage: "arrow.uturn.forward", isEnabled: model.canRedo) { model.redo() }
            Menu {
                Picker("Paper", selection: $background) {
                    ForEach(KitoCanvasBackground.allCases) { paper in
                        Label(paper.title, systemImage: paper.systemImage).tag(paper)
                    }
                }
                Button(role: .destructive) { model.clear() } label: { Label("Clear canvas", systemImage: "trash") }
                    .disabled(model.isEmpty)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.colors.onSurface)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(theme.colors.surface))
            }
            .accessibilityLabel("More")
        }
    }

    private var toolBar: some View {
        HStack(spacing: theme.spacing.sm) {
            ForEach(Tool.allCases) { item in
                KitoSignatureToolButton(item.title, systemImage: item.systemImage, isSelected: tool == item,
                                        tint: accent) { select(item) }
            }
            if tool != .eraser {
                Rectangle().fill(theme.colors.border).frame(width: 1, height: 24)
                KitoInkSwatches(inks, selection: inkBinding, tint: accent)
            }
        }
        .padding(.horizontal, theme.spacing.sm)
        .padding(.vertical, 6)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(theme.colors.border.opacity(0.6), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: tool)
    }

    /// Swatches show full-strength colours; the marker lays them down translucent.
    private var inkBinding: Binding<KitoInk> {
        Binding(get: { model.ink.opacity(1) }, set: { model.ink = tool == .marker ? $0.opacity(0.55) : $0 })
    }

    private func select(_ item: Tool) {
        tool = item
        switch item {
        case .pen:
            model.pen = .ballpoint
            model.ink = model.ink.opacity(1)
        case .marker:
            model.pen = .marker
            model.ink = model.ink.opacity(0.55)
        case .eraser:
            break
        }
    }

    private func adopt(_ size: CGSize) {
        if model.canvasSize != size { model.canvasSize = size }
    }
}

public extension KitoSignatureModel {
    /// Everything drawn, at the size it was drawn, on white paper with the given pattern.
    func canvasImage(background: KitoCanvasBackground = .blank, scale: CGFloat = 3) -> UIImage? {
        let size = canvasSize
        guard size.width > 0, size.height > 0 else { return nil }
        let rect = CGRect(origin: .zero, size: size)
        let layout = KitoSignatureLayout(canvas: size, transform: .identity)
        let paths = data.inkPaths()
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(rect)
            background.draw(in: context.cgContext, rect: rect, spacing: 24,
                            line: UIColor.black.withAlphaComponent(0.12),
                            margin: UIColor.systemRed.withAlphaComponent(0.35))
            KitoSignatureLayout.draw(paths, in: context.cgContext, layout: layout, background: .transparent, ink: nil)
        }
    }
}
