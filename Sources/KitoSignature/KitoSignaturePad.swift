//
//  KitoSignaturePad.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// A signature pad that draws like a pen: lines thin out when you move fast and swell when you
/// slow down, smoothed into curves. It has a "✕ Sign here" baseline, a hint that fades once you
/// start, ink colours, undo, redo and clear, and an optional "Signed by …" caption.
///
/// ```swift
/// @State private var signature = KitoSignatureModel()
///
/// KitoSignaturePad(model: signature,
///                  caption: KitoSignatureCaption(signerName: "Wycliff Njenga"),
///                  onTypeInstead: { mode = .type })
/// ```
///
/// VoiceOver users get a "Type your name instead" button in the pad when you pass
/// `onTypeInstead` — pair it with `KitoTypedSignature`.
public struct KitoSignaturePad: View {
    @Bindable private var model: KitoSignatureModel
    private let placeholder: String
    private let baselineLabel: String?
    private let caption: KitoSignatureCaption?
    private let inks: [KitoInk]
    private let showsToolbar: Bool
    private let height: CGFloat
    private let tint: Color?
    private let onTypeInstead: (() -> Void)?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var ghost: [KitoInkPath] = []
    @State private var ghostFading = false
    @State private var strokeCount = 0

    public init(model: KitoSignatureModel, placeholder: String = "Sign with your finger",
                baselineLabel: String? = "Sign here", caption: KitoSignatureCaption? = nil,
                inks: [KitoInk] = KitoInk.signatureInks, showsToolbar: Bool = true, height: CGFloat = 210,
                tint: Color? = nil, onTypeInstead: (() -> Void)? = nil) {
        self.model = model
        self.placeholder = placeholder
        self.baselineLabel = baselineLabel
        self.caption = caption
        self.inks = inks
        self.showsToolbar = showsToolbar
        self.height = height
        self.tint = tint
        self.onTypeInstead = onTypeInstead
    }

    private var accent: Color { tint ?? theme.colors.primary }

    public var body: some View {
        VStack(spacing: theme.spacing.sm) {
            pad
            if showsToolbar { toolbar }
        }
    }

    // MARK: Pad

    private var pad: some View {
        GeometryReader { proxy in
            let scale = drawingScale(for: proxy.size)
            ZStack(alignment: .bottomLeading) {
                hint
                baseline
                ghostLayer(scale: scale)
                inkLayer(scale: scale)
                captionLayer
            }
            .contentShape(Rectangle())
            .gesture(drawGesture(scale: scale))
            .onAppear { adopt(proxy.size) }
            .onChange(of: proxy.size) { _, size in adopt(size) }
        }
        .frame(height: height)
        .kitoSignaturePaper(isActive: model.isDrawing, tint: accent)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.isDrawing)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: strokeCount)
        .accessibilityElement(children: voiceOver && onTypeInstead != nil ? .contain : .ignore)
        .accessibilityLabel("Signature pad")
        .accessibilityValue(model.isEmpty ? "Empty" : "\(model.strokes.count) strokes drawn")
        .accessibilityHint("Draw your signature with one finger.")
        .accessibilityAction(named: "Undo") { model.undo() }
        .accessibilityAction(named: "Clear") { clear() }
    }

    @ViewBuilder
    private var hint: some View {
        if voiceOver, let onTypeInstead {
            Button(action: onTypeInstead) {
                Label("Type your name instead", systemImage: "keyboard")
                    .font(theme.typography.bodyEmphasized)
                    .padding(.horizontal, theme.spacing.md)
                    .padding(.vertical, theme.spacing.sm)
                    .background(Capsule().fill(accent.opacity(0.12)))
                    .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: theme.spacing.xs) {
                Image(systemName: "signature")
                    .font(.system(size: 26, weight: .regular))
                    .symbolEffect(.pulse, options: .repeating, isActive: model.isEmpty && !reduceMotion)
                Text(placeholder)
                    .font(theme.typography.label)
            }
            .foregroundStyle(theme.colors.onSurface.opacity(0.35))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, theme.spacing.xl)
            .opacity(model.isEmpty ? 1 : 0)
            .scaleEffect(model.isEmpty || reduceMotion ? 1 : 0.92)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.isEmpty)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var baseline: some View {
        if let baselineLabel {
            KitoSignatureBaseline(label: baselineLabel, highlighted: model.isDrawing, tint: accent)
                .padding(.horizontal, theme.spacing.lg)
                .padding(.bottom, caption == nil ? theme.spacing.md : theme.spacing.xl)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var captionLayer: some View {
        if let caption, !model.isEmpty {
            Text(caption.text)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.onSurface.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, theme.spacing.lg)
                .padding(.bottom, theme.spacing.sm)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .allowsHitTesting(false)
        }
    }

    private func inkLayer(scale: CGFloat) -> some View {
        let strokes = model.allStrokes
        let adaptive = theme.colors.onSurface
        return Canvas { context, _ in
            context.scaleBy(x: scale, y: scale)
            for stroke in strokes {
                context.fill(model.path(for: stroke), with: .color(stroke.ink.color(adaptive: adaptive)))
            }
        }
        .allowsHitTesting(false)
    }

    private func ghostLayer(scale: CGFloat) -> some View {
        let adaptive = theme.colors.onSurface
        let paths = ghost
        return Canvas { context, _ in
            context.scaleBy(x: scale, y: scale)
            for item in paths {
                context.fill(item.path, with: .color(item.ink.color(adaptive: adaptive)))
            }
        }
        .opacity(ghostFading ? 0 : 1)
        .blur(radius: ghostFading ? 6 : 0)
        .offset(y: ghostFading ? -14 : 0)
        .allowsHitTesting(false)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: theme.spacing.xs) {
            if inks.count > 1 {
                KitoInkSwatches(inks, selection: $model.ink, tint: accent)
            }
            Spacer(minLength: theme.spacing.sm)
            KitoSignatureToolButton("Undo", systemImage: "arrow.uturn.backward", isEnabled: model.canUndo) {
                model.undo()
            }
            KitoSignatureToolButton("Redo", systemImage: "arrow.uturn.forward", isEnabled: model.canRedo) {
                model.redo()
            }
            KitoSignatureToolButton("Clear", systemImage: "trash", isEnabled: !model.isEmpty) {
                clear()
            }
        }
    }

    // MARK: Input

    private func drawGesture(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let location = CGPoint(x: value.location.x / scale, y: value.location.y / scale)
                if model.isDrawing {
                    model.extend(to: location, date: value.time)
                } else {
                    model.begin(at: location, date: value.time)
                    strokeCount += 1
                }
            }
            .onEnded { _ in model.end() }
    }

    /// Strokes saved on a different-sized pad are scaled to fit this one.
    private func drawingScale(for size: CGSize) -> CGFloat {
        let canvas = model.canvasSize
        guard canvas.width > 0, canvas.height > 0, size.width > 0 else { return 1 }
        return min(size.width / canvas.width, size.height / canvas.height)
    }

    private func adopt(_ size: CGSize) {
        if model.isEmpty || model.canvasSize == .zero { model.canvasSize = size }
    }

    private func clear() {
        guard !model.isEmpty else { return }
        if reduceMotion {
            model.clear()
            return
        }
        ghost = model.data.inkPaths()
        ghostFading = false
        model.clear()
        withAnimation(.easeIn(duration: 0.35)) { ghostFading = true } completion: {
            ghost = []
            ghostFading = false
        }
    }
}
