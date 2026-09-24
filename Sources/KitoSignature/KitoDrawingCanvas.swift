//
//  KitoDrawingCanvas.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import PencilKit
import KitoCore

/// A PencilKit canvas on grid, lined, dotted or blank paper, with a floating toolbar (pen,
/// marker, pencil, eraser, colours), undo/redo, and a switch to Apple's own tool picker.
///
/// ```swift
/// @State private var sketch = KitoDrawingController(background: .dotted)
///
/// KitoDrawingCanvas(controller: sketch)
///     .frame(height: 420)
/// ```
///
/// Finger and Apple Pencil both draw by default; pass `drawingPolicy: .pencilOnly` to let fingers
/// scroll and only Pencil draw. For a canvas without PencilKit use `KitoSketchCanvas`.
public struct KitoDrawingCanvas: View {
    @Bindable private var controller: KitoDrawingController
    private let inks: [KitoInk]
    private let showsToolbar: Bool
    private let drawingPolicy: PKCanvasViewDrawingPolicy
    private let tint: Color?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(controller: KitoDrawingController, inks: [KitoInk] = [.automatic, .royalBlue, .red, .forest, .orange],
                showsToolbar: Bool = true, drawingPolicy: PKCanvasViewDrawingPolicy = .anyInput, tint: Color? = nil) {
        self.controller = controller
        self.inks = inks
        self.showsToolbar = showsToolbar
        self.drawingPolicy = drawingPolicy
        self.tint = tint
    }

    private var accent: Color { tint ?? theme.colors.primary }

    public var body: some View {
        ZStack {
            KitoCanvasBackgroundView(controller.background)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: controller.background)
            KitoPencilCanvas(controller: controller, drawingPolicy: drawingPolicy)
                .accessibilityLabel("Drawing canvas")
        }
        .overlay(alignment: .topTrailing) {
            if showsToolbar { topBar.padding(theme.spacing.sm) }
        }
        .overlay(alignment: .bottom) {
            if showsToolbar && !controller.showsToolPicker {
                toolBar
                    .padding(theme.spacing.sm)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous)
            .strokeBorder(theme.colors.border, lineWidth: 1))
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: controller.showsToolPicker)
    }

    private var topBar: some View {
        HStack(spacing: theme.spacing.xs) {
            KitoSignatureToolButton("Undo", systemImage: "arrow.uturn.backward", isEnabled: controller.canUndo) {
                controller.undo()
            }
            KitoSignatureToolButton("Redo", systemImage: "arrow.uturn.forward", isEnabled: controller.canRedo) {
                controller.redo()
            }
            moreMenu
        }
    }

    private var moreMenu: some View {
        Menu {
            Picker("Paper", selection: $controller.background) {
                ForEach(KitoCanvasBackground.allCases) { paper in
                    Label(paper.title, systemImage: paper.systemImage).tag(paper)
                }
            }
            Toggle(isOn: $controller.showsToolPicker) {
                Label("Apple Pencil tools", systemImage: "pencil.tip.crop.circle")
            }
            Button(role: .destructive) { controller.clear() } label: {
                Label("Clear canvas", systemImage: "trash")
            }
            .disabled(controller.isEmpty)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.colors.onSurface)
                .frame(width: 38, height: 38)
                .background(Circle().fill(theme.colors.surface))
                .overlay(Circle().strokeBorder(theme.colors.border.opacity(0.5), lineWidth: 0.5))
        }
        .accessibilityLabel("More")
    }

    private var toolBar: some View {
        HStack(spacing: theme.spacing.sm) {
            ForEach(KitoDrawingTool.allCases) { tool in
                KitoSignatureToolButton(tool.title, systemImage: tool.systemImage,
                                        isSelected: controller.tool == tool, tint: accent) {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
                        controller.tool = tool
                    }
                }
            }
            if controller.tool != .eraser {
                Rectangle().fill(theme.colors.border).frame(width: 1, height: 24)
                KitoInkSwatches(inks, selection: $controller.ink, tint: accent)
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
            }
        }
        .padding(.horizontal, theme.spacing.sm)
        .padding(.vertical, 6)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(theme.colors.border.opacity(0.6), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: controller.tool)
    }
}

/// The `PKCanvasView` itself, kept in sync with a `KitoDrawingController`.
struct KitoPencilCanvas: UIViewRepresentable {
    let controller: KitoDrawingController
    let drawingPolicy: PKCanvasViewDrawingPolicy

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = KitoSizedCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = drawingPolicy
        canvas.drawing = controller.drawing
        canvas.tool = controller.pencilKitTool
        canvas.delegate = context.coordinator
        canvas.onResize = { [weak controller] size in
            if controller?.canvasSize != size { controller?.canvasSize = size }
        }
        context.coordinator.toolPicker.addObserver(canvas)
        controller.canvasView = canvas
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.drawingPolicy = drawingPolicy
        if canvas.drawing != controller.drawing { canvas.drawing = controller.drawing }
        let picker = context.coordinator.toolPicker
        if controller.showsToolPicker {
            picker.setVisible(true, forFirstResponder: canvas)
            canvas.becomeFirstResponder()
        } else {
            picker.setVisible(false, forFirstResponder: canvas)
            canvas.tool = controller.pencilKitTool
        }
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.toolPicker.setVisible(false, forFirstResponder: canvas)
        coordinator.toolPicker.removeObserver(canvas)
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let controller: KitoDrawingController
        let toolPicker = PKToolPicker()

        init(controller: KitoDrawingController) {
            self.controller = controller
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            controller.drawing = canvasView.drawing
            controller.sync()
        }
    }
}

/// Reports its size so exports match what's on screen.
final class KitoSizedCanvasView: PKCanvasView {
    var onResize: (@MainActor (CGSize) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onResize?(bounds.size)
    }
}
