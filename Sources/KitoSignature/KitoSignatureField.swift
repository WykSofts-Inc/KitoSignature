//
//  KitoSignatureField.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// A form field for a signature. Empty, it invites a tap; tapping opens `KitoSignatureSheet`.
/// Signed, it shows the signature (written in once), "Signed ✓" and who signed when. Tap again
/// to re-sign.
///
/// ```swift
/// @State private var signature: KitoCapturedSignature?
///
/// KitoSignatureField("Parent or guardian", signature: $signature,
///                    signerName: "Amina Wanjiru", sheetTitle: "Sign the consent form")
/// ```
public struct KitoSignatureField: View {
    private let label: String
    @Binding private var signature: KitoCapturedSignature?
    private let signerName: String?
    private let prompt: String
    private let sheetTitle: String
    private let sheetMessage: String?
    private let consentText: String?
    private let modes: [KitoSignatureMode]
    private let isRequired: Bool
    private let tint: Color?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presenting = false
    @State private var justSigned = false

    public init(_ label: String = "Signature", signature: Binding<KitoCapturedSignature?>,
                signerName: String? = nil, prompt: String = "Tap to sign", sheetTitle: String = "Add your signature",
                sheetMessage: String? = nil, consentText: String? = "I agree this is my signature",
                modes: [KitoSignatureMode] = KitoSignatureMode.allCases, isRequired: Bool = false,
                tint: Color? = nil) {
        self.label = label
        self._signature = signature
        self.signerName = signerName
        self.prompt = prompt
        self.sheetTitle = sheetTitle
        self.sheetMessage = sheetMessage
        self.consentText = consentText
        self.modes = modes
        self.isRequired = isRequired
        self.tint = tint
    }

    private var accent: Color { tint ?? theme.colors.primary }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            titleRow
            Button { presenting = true } label: { card }
                .buttonStyle(KitoSignaturePressStyle())
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint(signature == nil ? "Opens the signing sheet." : "Opens the signing sheet to sign again.")
        }
        .kitoSignatureSheet(isPresented: $presenting, title: sheetTitle, message: sheetMessage,
                            signerName: signerName, consentText: consentText, modes: modes, tint: tint) { result in
            justSigned = true
            signature = result
        }
        .sensoryFeedback(.success, trigger: signature)
    }

    private var titleRow: some View {
        HStack(spacing: theme.spacing.xxs) {
            Text(label)
                .font(theme.typography.label)
                .foregroundStyle(theme.colors.onBackground.opacity(0.75))
            if isRequired {
                Text("*").font(theme.typography.label).foregroundStyle(theme.colors.danger)
            }
            Spacer()
            if signature != nil { signedBadge }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.6), value: signature != nil)
    }

    private var signedBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.seal.fill")
                .symbolEffect(.bounce, value: signature?.signedAt)
            Text("Signed")
        }
        .font(theme.typography.caption.weight(.semibold))
        .foregroundStyle(theme.colors.success)
        .padding(.horizontal, theme.spacing.sm)
        .padding(.vertical, 4)
        .background(Capsule().fill(theme.colors.success.opacity(0.14)))
        .transition(.scale(scale: 0.6).combined(with: .opacity))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous)
        Group {
            if let signature {
                signedContent(signature)
            } else {
                emptyContent
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .background(shape.fill(theme.colors.surface))
        .overlay {
            if signature == nil {
                shape.strokeBorder(accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            } else {
                shape.strokeBorder(theme.colors.border, lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(signature == nil ? 0 : 0.06), radius: 8, y: 3)
        .contentShape(shape)
    }

    private var emptyContent: some View {
        HStack(spacing: theme.spacing.sm) {
            Image(systemName: "signature")
                .font(.system(size: 22, weight: .medium))
                .frame(width: 44, height: 44)
                .background(Circle().fill(accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(prompt).font(theme.typography.bodyEmphasized)
                Text(modes.contains(.type) ? "Draw or type your name" : "Draw with your finger")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.onSurface.opacity(0.55))
            }
            .foregroundStyle(theme.colors.onSurface)
            Spacer()
            Image(systemName: "chevron.forward")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.colors.onSurface.opacity(0.35))
        }
        .foregroundStyle(accent)
        .padding(.horizontal, theme.spacing.md)
    }

    private func signedContent(_ signature: KitoCapturedSignature) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom) {
                KitoSignatureView(signature, replay: justSigned, padding: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.colors.onSurface.opacity(0.35))
                    .accessibilityHidden(true)
            }
            Rectangle()
                .fill(theme.colors.onSurface.opacity(0.15))
                .frame(height: 1)
            Text(signature.caption.text)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.onSurface.opacity(0.55))
                .lineLimit(1)
        }
        .padding(.horizontal, theme.spacing.md)
        .padding(.vertical, theme.spacing.sm)
        .transition(.opacity)
    }

    private var accessibilityLabel: String {
        guard let signature else { return "\(label), not signed. \(prompt)" }
        return "\(label), signed. \(signature.caption.text)"
    }
}
