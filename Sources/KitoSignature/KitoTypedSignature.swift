//
//  KitoTypedSignature.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// Type your name and pick a handwriting style — the accessible alternative to drawing. The name
/// is turned into glyph outlines, so it previews, exports and stores exactly like a drawn
/// signature.
///
/// ```swift
/// @State private var typed = KitoTypedSignatureValue(name: "Wycliff Njenga")
///
/// KitoTypedSignature(value: $typed)
/// ```
public struct KitoTypedSignature: View {
    @Binding private var value: KitoTypedSignatureValue
    private let styles: [KitoTypedSignatureStyle]
    private let inks: [KitoInk]
    private let placeholder: String
    private let caption: KitoSignatureCaption?
    private let previewHeight: CGFloat
    private let tint: Color?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @Namespace private var ring

    public init(value: Binding<KitoTypedSignatureValue>,
                styles: [KitoTypedSignatureStyle] = KitoTypedSignatureStyle.allCases,
                inks: [KitoInk] = KitoInk.signatureInks, placeholder: String = "Type your full name",
                caption: KitoSignatureCaption? = nil, previewHeight: CGFloat = 150, tint: Color? = nil) {
        self._value = value
        self.styles = styles
        self.inks = inks
        self.placeholder = placeholder
        self.caption = caption
        self.previewHeight = previewHeight
        self.tint = tint
    }

    private var accent: Color { tint ?? theme.colors.primary }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            preview
            nameField
            styleStrip
            if inks.count > 1 {
                KitoInkSwatches(inks, selection: $value.ink, tint: accent)
            }
        }
    }

    // MARK: Preview

    private var preview: some View {
        ZStack(alignment: .bottomLeading) {
            if value.trimmedName.isEmpty {
                Text("Your signature appears here")
                    .font(theme.typography.label)
                    .foregroundStyle(theme.colors.onSurface.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, theme.spacing.lg)
            } else {
                KitoSignatureView(typed: value, replay: true, padding: 0)
                    .id(value.style)
                    .padding(.horizontal, theme.spacing.xl)
                    .padding(.top, theme.spacing.lg)
                    .padding(.bottom, theme.spacing.xl + theme.spacing.md)
                    .transition(.opacity)
            }
            KitoSignatureBaseline(label: caption?.text ?? "Sign here", highlighted: focused, tint: accent)
                .padding(.horizontal, theme.spacing.lg)
                .padding(.bottom, theme.spacing.md)
        }
        .frame(height: previewHeight)
        .kitoSignaturePaper(isActive: focused, tint: accent)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: value.style)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(previewLabel)
    }

    private var previewLabel: String {
        let name = value.trimmedName
        return name.isEmpty ? "Signature preview, empty" : "Signature preview: \(name) in \(value.style.title) style"
    }

    // MARK: Field

    private var nameField: some View {
        HStack(spacing: theme.spacing.sm) {
            Image(systemName: "person.text.rectangle")
                .foregroundStyle(focused ? accent : theme.colors.onSurface.opacity(0.5))
            TextField(placeholder, text: $value.name)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.onSurface)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .accessibilityLabel("Full name")
            if !value.name.isEmpty {
                Button { value.name = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.colors.onSurface.opacity(0.35))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear name")
            }
        }
        .padding(.horizontal, theme.spacing.md)
        .frame(height: 50)
        .background(RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous).fill(theme.colors.surface))
        .overlay(fieldBorder)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: focused)
    }

    private var fieldBorder: some View {
        RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous)
            .strokeBorder(focused ? accent : theme.colors.border, lineWidth: focused ? 1.5 : 1)
    }

    // MARK: Styles

    private var styleStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing.sm) {
                ForEach(styles) { style in
                    styleCard(style)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
        .sensoryFeedback(.selection, trigger: value.style)
    }

    private func styleCard(_ style: KitoTypedSignatureStyle) -> some View {
        let selected = style == value.style
        let sample = KitoTypedSignatureValue(name: sampleName, style: style, ink: value.ink)
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75)) { value.style = style }
        } label: {
            VStack(spacing: 6) {
                KitoSignatureView(typed: sample, padding: 0)
                    .frame(height: 34)
                Text(style.title)
                    .font(theme.typography.caption)
                    .foregroundStyle(selected ? accent : theme.colors.onSurface.opacity(0.6))
            }
            .padding(.horizontal, theme.spacing.sm)
            .padding(.vertical, theme.spacing.sm)
            .frame(width: 122, height: 78)
            .background(styleBackground(selected))
            .scaleEffect(selected && !reduceMotion ? 1.03 : 1)
        }
        .buttonStyle(KitoSignaturePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(style.title) style")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func styleBackground(_ selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.radii.md, style: .continuous)
        return ZStack {
            shape.fill(theme.colors.surface)
            if selected {
                shape.strokeBorder(accent, lineWidth: 2)
                    .matchedGeometryEffect(id: "ring", in: ring)
            } else {
                shape.strokeBorder(theme.colors.border, lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(selected ? 0.1 : 0.03), radius: selected ? 8 : 2, y: 2)
    }

    private var sampleName: String {
        let name = value.trimmedName
        return name.isEmpty ? "Your Name" : name
    }
}
