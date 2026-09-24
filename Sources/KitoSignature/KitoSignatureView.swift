//
//  KitoSignatureView.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// Shows a saved signature scaled to fit, at any size. With `replay`, a drawn signature writes
/// itself stroke by stroke at the speed it was signed, and a typed one is revealed like ink
/// flowing from a pen. Reduce Motion shows it straight away.
///
/// ```swift
/// KitoSignatureView(captured, replay: true)
///     .frame(height: 80)
/// ```
public struct KitoSignatureView: View {
    private let signature: KitoCapturedSignature.Content
    private let signerName: String?
    private let replay: Bool
    private let speed: Double
    private let padding: CGFloat
    private let tint: Color?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var revealed = false
    @State private var finished = false

    public init(_ signature: KitoCapturedSignature, replay: Bool = false, speed: Double = 1.4,
                padding: CGFloat = 6, tint: Color? = nil) {
        self.signature = signature.content
        self.signerName = signature.signerName
        self.replay = replay
        self.speed = max(speed, 0.1)
        self.padding = padding
        self.tint = tint
    }

    public init(data: KitoSignatureData, replay: Bool = false, speed: Double = 1.4, padding: CGFloat = 6,
                tint: Color? = nil) {
        self.init(KitoCapturedSignature(content: .drawn(data), signedAt: .distantPast), replay: replay,
                  speed: speed, padding: padding, tint: tint)
    }

    public init(typed: KitoTypedSignatureValue, replay: Bool = false, padding: CGFloat = 6, tint: Color? = nil) {
        self.init(KitoCapturedSignature(content: .typed(typed), signerName: typed.trimmedName, signedAt: .distantPast),
                  replay: replay, padding: padding, tint: tint)
    }

    public var body: some View {
        content
            .onAppear { restart() }
            .onChange(of: signature) {
                // Typing a name shouldn't re-run the reveal on every keystroke.
                if isTyped { revealed = true } else { restart() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder
    private var content: some View {
        switch signature {
        case .drawn(let data) where animates:
            replayingCanvas(data)
        case .typed where animates:
            staticCanvas(paths)
                .mask(alignment: .leading) { revealMask }
        default:
            staticCanvas(paths)
        }
    }

    private var paths: [KitoInkPath] {
        switch signature {
        case .drawn(let data): data.inkPaths()
        case .typed(let value): value.inkPaths()
        }
    }

    private var isTyped: Bool {
        if case .typed = signature { return true }
        return false
    }

    private var animates: Bool { replay && !reduceMotion }

    private func staticCanvas(_ paths: [KitoInkPath]) -> some View {
        let bounds = paths.reduce(CGRect.null) { $0.union($1.path.boundingRect) }
        return Canvas { context, size in
            draw(paths, bounds: bounds, in: &context, size: size)
        }
    }

    private func replayingCanvas(_ data: KitoSignatureData) -> some View {
        let bounds = data.inkBounds
        let duration = data.replayDuration / speed
        return TimelineView(.animation(minimumInterval: nil, paused: finished)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            let partial = finished || elapsed >= duration ? data : data.replayed(upTo: elapsed * speed)
            Canvas { context, size in
                draw(partial.inkPaths(), bounds: bounds, in: &context, size: size)
            }
        }
    }

    private var revealMask: some View {
        GeometryReader { proxy in
            LinearGradient(stops: [.init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: revealed ? proxy.size.width * 1.2 : 0)
        }
    }

    private func draw(_ paths: [KitoInkPath], bounds: CGRect, in context: inout GraphicsContext, size: CGSize) {
        guard !bounds.isNull else { return }
        let rect = CGRect(origin: .zero, size: size)
        let transform = KitoSignatureGeometry.fitTransform(from: bounds, into: rect, padding: padding)
        for item in paths {
            let color = item.ink.color(adaptive: theme.colors.onSurface)
            context.fill(item.path.applying(transform), with: .color(color))
        }
    }

    private func restart() {
        let startedAt = Date()
        start = startedAt
        revealed = false
        finished = !animates
        guard animates else { revealed = true; return }
        withAnimation(.easeOut(duration: 1.1).delay(0.1)) { revealed = true }
        guard case .drawn(let data) = signature else { return }
        let delay = data.replayDuration / speed + 0.15
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            if start == startedAt { finished = true }
        }
    }

    private var accessibilityText: String {
        let kind = isTyped ? "Typed signature" : "Handwritten signature"
        if let name = signerName, !name.isEmpty { return "\(kind) of \(name)" }
        return kind
    }
}
