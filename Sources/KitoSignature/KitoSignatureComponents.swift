//
//  KitoSignatureComponents.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// A row of ink swatches. The selected one grows a ring that slides between swatches.
public struct KitoInkSwatches: View {
    private let inks: [KitoInk]
    @Binding private var selection: KitoInk
    private let tint: Color?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ring

    public init(_ inks: [KitoInk] = KitoInk.signatureInks, selection: Binding<KitoInk>, tint: Color? = nil) {
        self.inks = inks
        self._selection = selection
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: theme.spacing.sm) {
            ForEach(inks) { ink in
                swatch(ink)
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func swatch(_ ink: KitoInk) -> some View {
        let selected = ink == selection
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7)) { selection = ink }
        } label: {
            ZStack {
                if selected {
                    Circle()
                        .strokeBorder(tint ?? theme.colors.primary, lineWidth: 2)
                        .matchedGeometryEffect(id: "ring", in: ring)
                }
                Circle()
                    .fill(ink.color(adaptive: theme.colors.onSurface))
                    .overlay(Circle().strokeBorder(theme.colors.border.opacity(0.6), lineWidth: 0.5))
                    .padding(selected ? 5 : 3)
                    .shadow(color: .black.opacity(selected ? 0.18 : 0.06), radius: selected ? 3 : 1, y: 1)
            }
            .frame(width: 30, height: 30)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ink.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A round toolbar button (undo, redo, clear…) that bounces its symbol when tapped.
public struct KitoSignatureToolButton: View {
    private let title: String
    private let systemImage: String
    private let isEnabled: Bool
    private let isSelected: Bool
    private let tint: Color?
    private let action: () -> Void

    @Environment(\.kitoTheme) private var theme
    @State private var taps = 0

    public init(_ title: String, systemImage: String, isEnabled: Bool = true, isSelected: Bool = false,
                tint: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.isSelected = isSelected
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .symbolEffect(.bounce, value: taps)
                .foregroundStyle(foreground)
                .frame(width: 38, height: 38)
                .background(Circle().fill(background))
                .overlay(Circle().strokeBorder(theme.colors.border.opacity(isSelected ? 0 : 0.5), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(KitoSignaturePressStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foreground: Color {
        isSelected ? theme.colors.onPrimary : theme.colors.onSurface
    }

    private var background: Color {
        isSelected ? (tint ?? theme.colors.primary) : theme.colors.surface
    }
}

/// Presses shrink a little and spring back.
struct KitoSignaturePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// "I agree this is my signature" — a checkbox whose tick draws itself in.
public struct KitoConsentCheckbox: View {
    @Binding private var isOn: Bool
    private let text: String
    private let tint: Color?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isOn: Binding<Bool>, text: String = "I agree this is my signature", tint: Color? = nil) {
        self._isOn = isOn
        self.text = text
        self.tint = tint
    }

    public var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.65)) { isOn.toggle() }
        } label: {
            HStack(alignment: .top, spacing: theme.spacing.sm) {
                box
                Text(text)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.onSurface)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityValue(isOn ? "Checked" : "Not checked")
        .accessibilityAddTraits(.isButton)
    }

    private var box: some View {
        let accent = tint ?? theme.colors.primary
        return ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isOn ? accent : theme.colors.surface)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isOn ? accent : theme.colors.border, lineWidth: 1.5)
            KitoSignatureCheckmark()
                .trim(from: 0, to: isOn ? 1 : 0)
                .stroke(theme.colors.onPrimary, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .padding(6)
        }
        .frame(width: 24, height: 24)
        .scaleEffect(isOn ? 1 : 0.94)
    }
}

/// A tick, drawn left to right so `trim` animates it like a pen.
struct KitoSignatureCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY - rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.08))
        return path
    }
}

/// The "✕ ─────── Sign here" line across a pad.
struct KitoSignatureBaseline: View {
    let label: String
    let highlighted: Bool
    let tint: Color

    @Environment(\.kitoTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: theme.spacing.xs) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(highlighted ? tint : theme.colors.onSurface.opacity(0.55))
                Rectangle()
                    .fill(lineGradient)
                    .frame(height: 1.5)
            }
            Text(label)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.onSurface.opacity(0.5))
                .padding(.leading, 20)
        }
        .accessibilityHidden(true)
    }

    private var lineGradient: LinearGradient {
        let base = highlighted ? tint : theme.colors.onSurface.opacity(0.35)
        return LinearGradient(colors: [base, base.opacity(0.15)], startPoint: .leading, endPoint: .trailing)
    }
}

/// A two or more option switcher with a sliding pill, for Draw / Type.
struct KitoSignatureSegmented<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    let systemImage: (Option) -> String
    let tint: Color

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                segment(option)
            }
        }
        .padding(4)
        .background(Capsule().fill(theme.colors.surfaceMuted))
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func segment(_ option: Option) -> some View {
        let selected = option == selection
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.78)) { selection = option }
        } label: {
            Label(title(option), systemImage: systemImage(option))
                .font(theme.typography.label)
                .foregroundStyle(selected ? theme.colors.onPrimary : theme.colors.onSurface.opacity(0.7))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background {
                    if selected {
                        Capsule()
                            .fill(tint)
                            .shadow(color: tint.opacity(0.3), radius: 6, y: 2)
                            .matchedGeometryEffect(id: "pill", in: pill)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Paper-like card used behind pads and previews.
struct KitoSignaturePaper: ViewModifier {
    let isActive: Bool
    let tint: Color

    @Environment(\.kitoTheme) private var theme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous)
        return content
            .background(shape.fill(paperGradient))
            .overlay(shape.strokeBorder(isActive ? tint.opacity(0.55) : theme.colors.border.opacity(0.8),
                                        lineWidth: isActive ? 1.5 : 1))
            .shadow(color: .black.opacity(isActive ? 0.12 : 0.06), radius: isActive ? 14 : 8, y: isActive ? 6 : 3)
    }

    private var paperGradient: LinearGradient {
        LinearGradient(colors: [theme.colors.surface, theme.colors.surfaceMuted.opacity(0.55)],
                       startPoint: .top, endPoint: .bottom)
    }
}

extension View {
    func kitoSignaturePaper(isActive: Bool = false, tint: Color) -> some View {
        modifier(KitoSignaturePaper(isActive: isActive, tint: tint))
    }
}
