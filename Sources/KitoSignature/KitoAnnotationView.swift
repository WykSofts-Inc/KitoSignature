//
//  KitoAnnotationView.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// Mark up a photo — circle the damage on a delivery photo, highlight a meter reading, point an
/// arrow at the dent, add a note — then export one flattened image with
/// `model.flattenedImage()`.
///
/// ```swift
/// @State private var markup = KitoAnnotationModel(image: parcelPhoto)
///
/// KitoAnnotationView(model: markup)
/// ```
///
/// With the Text tool, tap where the note should go.
public struct KitoAnnotationView: View {
    @Bindable private var model: KitoAnnotationModel
    private let inks: [KitoInk]
    private let showsToolbar: Bool
    private let tint: Color?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pendingTextPoint: CGPoint?
    @State private var noteText = ""
    @State private var askingForText = false

    public init(model: KitoAnnotationModel, inks: [KitoInk] = KitoInk.markupInks, showsToolbar: Bool = true,
                tint: Color? = nil) {
        self.model = model
        self.inks = inks
        self.showsToolbar = showsToolbar
        self.tint = tint
    }

    private var accent: Color { tint ?? theme.colors.primary }

    public var body: some View {
        VStack(spacing: theme.spacing.sm) {
            if showsToolbar { topBar }
            photo
            if showsToolbar { toolBar }
        }
        .alert("Add a note", isPresented: $askingForText) {
            TextField("e.g. Box dented", text: $noteText)
            Button("Add") { addNote() }
            Button("Cancel", role: .cancel) { noteText = "" }
        }
    }

    // MARK: Photo

    private var photo: some View {
        GeometryReader { proxy in
            let rect = KitoAnnotationGeometry.fitRect(for: model.image.size, in: proxy.size)
            let scale = model.image.size.width > 0 ? rect.width / model.image.size.width : 1
            ZStack(alignment: .topLeading) {
                Image(uiImage: model.image)
                    .resizable()
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .accessibilityLabel("Photo")
                marks(scale: scale)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(gesture(rect: rect, scale: scale))
        }
        .background(theme.colors.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Photo with \(model.annotations.count) marks")
        .accessibilityHint("Draw on the photo to mark it up.")
    }

    private func marks(scale: CGFloat) -> some View {
        let items = model.visibleAnnotations
        return Canvas { context, _ in
            context.scaleBy(x: scale, y: scale)
            for mark in items {
                draw(mark, in: &context)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ mark: KitoAnnotation, in context: inout GraphicsContext) {
        let color = mark.ink.color(adaptive: theme.colors.onSurface)
        switch mark.kind {
        case .pen(let points):
            context.fill(KitoAnnotationGeometry.linePath(points, width: mark.lineWidth), with: .color(color))
        case .highlight(let points):
            var layer = context
            layer.blendMode = .multiply
            layer.fill(KitoAnnotationGeometry.linePath(points, width: mark.lineWidth), with: .color(color))
        case .arrow(let from, let to):
            let path = KitoAnnotationGeometry.arrowPath(from: from.location, to: to.location, width: mark.lineWidth)
            let style = StrokeStyle(lineWidth: CGFloat(mark.lineWidth), lineCap: .round, lineJoin: .round)
            context.stroke(path, with: .color(color), style: style)
        case .text(let text, let at):
            drawLabel(text, at: at.location, mark: mark, color: color, in: &context)
        }
    }

    private func drawLabel(_ text: String, at center: CGPoint, mark: KitoAnnotation, color: Color,
                           in context: inout GraphicsContext) {
        let dark = KitoAnnotationGeometry.labelTextIsDark(on: mark.ink)
        let label = Text(text)
            .font(.system(size: CGFloat(mark.fontSize), weight: .bold))
            .foregroundStyle(dark ? Color.black : Color.white)
        let resolved = context.resolve(label)
        let size = resolved.measure(in: CGSize(width: 10_000, height: 10_000))
        let pill = KitoAnnotationDrawing.labelRect(textSize: size, center: center, fontSize: CGFloat(mark.fontSize))
        context.fill(Path(roundedRect: pill, cornerRadius: pill.height / 2), with: .color(color))
        context.draw(resolved, at: center, anchor: .center)
    }

    private func gesture(rect: CGRect, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard model.tool != .text else { return }
                let point = imagePoint(value.location, rect: rect, scale: scale)
                if model.draft == nil { model.begin(at: point) } else { model.extend(to: point) }
            }
            .onEnded { value in
                if model.tool == .text {
                    pendingTextPoint = imagePoint(value.location, rect: rect, scale: scale)
                    askingForText = true
                } else {
                    model.end()
                }
            }
    }

    private func imagePoint(_ location: CGPoint, rect: CGRect, scale: CGFloat) -> CGPoint {
        guard scale > 0 else { return location }
        let x = (location.x - rect.minX) / scale
        let y = (location.y - rect.minY) / scale
        let size = model.image.size
        return CGPoint(x: min(max(x, 0), size.width), y: min(max(y, 0), size.height))
    }

    private func addNote() {
        if let point = pendingTextPoint { model.addText(noteText, at: point) }
        noteText = ""
        pendingTextPoint = nil
    }

    // MARK: Toolbars

    private var topBar: some View {
        HStack(spacing: theme.spacing.xs) {
            Text("\(model.annotations.count) mark\(model.annotations.count == 1 ? "" : "s")")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.onBackground.opacity(0.55))
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy, value: model.annotations.count)
            Spacer()
            KitoSignatureToolButton("Undo", systemImage: "arrow.uturn.backward", isEnabled: model.canUndo) { model.undo() }
            KitoSignatureToolButton("Redo", systemImage: "arrow.uturn.forward", isEnabled: model.canRedo) { model.redo() }
            KitoSignatureToolButton("Clear", systemImage: "trash", isEnabled: !model.isEmpty) { model.clear() }
        }
    }

    private var toolBar: some View {
        VStack(spacing: theme.spacing.sm) {
            HStack(spacing: theme.spacing.sm) {
                ForEach(KitoAnnotationTool.allCases) { tool in
                    KitoSignatureToolButton(tool.title, systemImage: tool.systemImage,
                                            isSelected: model.tool == tool, tint: accent) {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
                            model.tool = tool
                        }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                KitoInkSwatches(inks, selection: $model.ink, tint: accent)
                    .padding(.horizontal, 2)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .padding(theme.spacing.sm)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous).fill(theme.colors.surface))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous)
            .strokeBorder(theme.colors.border.opacity(0.7), lineWidth: 0.5))
    }
}
