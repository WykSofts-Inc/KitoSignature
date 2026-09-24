//
//  KitoSignatureSheet.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// How a signature is captured.
public enum KitoSignatureMode: String, CaseIterable, Sendable, Identifiable {
    case draw
    case type

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .draw: "Draw"
        case .type: "Type"
        }
    }

    public var systemImage: String {
        switch self {
        case .draw: "scribble.variable"
        case .type: "keyboard"
        }
    }
}

/// The whole signing flow for a bottom sheet: Draw and Type tabs, a consent checkbox and Done,
/// which hands back a `KitoCapturedSignature`. VoiceOver users start on Type.
///
/// ```swift
/// .kitoSignatureSheet(isPresented: $signing, title: "Sign for your parcel",
///                     signerName: "Wycliff Njenga") { signature in
///     proof = signature
/// }
/// ```
public struct KitoSignatureSheet: View {
    private let title: String
    private let message: String?
    private let signerName: String?
    private let consentText: String?
    private let modes: [KitoSignatureMode]
    private let showsCaption: Bool
    private let doneTitle: String
    private let tint: Color?
    private let onCancel: (() -> Void)?
    private let onDone: (KitoCapturedSignature) -> Void

    @Environment(\.kitoTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    @State private var model: KitoSignatureModel
    @State private var typed: KitoTypedSignatureValue
    @State private var mode: KitoSignatureMode
    @State private var agreed = false
    @State private var attempted = false
    @State private var shakes = 0
    @State private var didChooseMode = false

    public init(title: String = "Add your signature", message: String? = nil, signerName: String? = nil,
                consentText: String? = "I agree this is my signature",
                modes: [KitoSignatureMode] = KitoSignatureMode.allCases, initialMode: KitoSignatureMode? = nil,
                showsCaption: Bool = true, doneTitle: String = "Done",
                validator: KitoSignatureValidator = KitoSignatureValidator(), tint: Color? = nil,
                onCancel: (() -> Void)? = nil, onDone: @escaping (KitoCapturedSignature) -> Void) {
        let available = modes.isEmpty ? KitoSignatureMode.allCases : modes
        self.title = title
        self.message = message
        self.signerName = signerName
        self.consentText = consentText
        self.modes = available
        self.showsCaption = showsCaption
        self.doneTitle = doneTitle
        self.tint = tint
        self.onCancel = onCancel
        self.onDone = onDone
        _model = State(initialValue: KitoSignatureModel(validator: validator))
        _typed = State(initialValue: KitoTypedSignatureValue(name: signerName ?? ""))
        let first = initialMode.flatMap { available.contains($0) ? $0 : nil } ?? available[0]
        _mode = State(initialValue: first)
        _didChooseMode = State(initialValue: initialMode != nil)
    }

    private var accent: Color { tint ?? theme.colors.primary }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            header
            if modes.count > 1 {
                KitoSignatureSegmented(options: modes, selection: $mode, title: \.title,
                                       systemImage: \.systemImage, tint: accent)
            }
            capture
            footer
        }
        .padding(.horizontal, theme.spacing.lg)
        .padding(.top, theme.spacing.lg)
        .padding(.bottom, theme.spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.colors.background.ignoresSafeArea())
        .onAppear(perform: preferTypingForVoiceOver)
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top, spacing: theme.spacing.sm) {
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text(title)
                    .font(theme.typography.titleMedium)
                    .foregroundStyle(theme.colors.onBackground)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    Text(message)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.onBackground.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Button(action: cancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.colors.onSurface.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(theme.colors.surfaceMuted))
            }
            .buttonStyle(KitoSignaturePressStyle())
            .accessibilityLabel("Cancel")
        }
    }

    @ViewBuilder
    private var capture: some View {
        ZStack(alignment: .top) {
            switch mode {
            case .draw:
                KitoSignaturePad(model: model, caption: caption, tint: accent,
                                 onTypeInstead: modes.contains(.type) ? { switchTo(.type) } : nil)
                    .transition(slide(from: .leading))
            case .type:
                ScrollView {
                    KitoTypedSignature(value: $typed, caption: caption, tint: accent)
                        .padding(.vertical, 2)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
                .transition(slide(from: .trailing))
            }
        }
        .frame(maxHeight: mode == .type ? .infinity : nil, alignment: .top)
        .modifier(KitoShakeEffect(shakes: CGFloat(attempted && !signatureReady ? shakes : 0)))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            if mode == .draw { Spacer(minLength: 0) }
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle.fill")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.danger)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if let consentText {
                KitoConsentCheckbox(isOn: $agreed, text: consentText, tint: accent)
                    .modifier(KitoShakeEffect(shakes: CGFloat(attempted && !agreed && signatureReady ? shakes : 0)))
            }
            doneButton
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: problem)
    }

    private var doneButton: some View {
        Button(action: finish) {
            HStack(spacing: theme.spacing.xs) {
                Image(systemName: canFinish ? "checkmark" : "signature")
                    .contentTransition(.symbolEffect(.replace))
                Text(doneTitle)
            }
            .font(theme.typography.button)
            .foregroundStyle(theme.colors.onPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(accent.opacity(canFinish ? 1 : 0.45)))
            .shadow(color: accent.opacity(canFinish ? 0.35 : 0), radius: 10, y: 4)
            .contentShape(Capsule())
        }
        .buttonStyle(KitoSignaturePressStyle())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: canFinish)
        .sensoryFeedback(.warning, trigger: shakes)
        .accessibilityHint(problem ?? "")
    }

    // MARK: Logic

    private var caption: KitoSignatureCaption? {
        guard showsCaption, let name = currentSignerName, !name.isEmpty else { return nil }
        return KitoSignatureCaption(signerName: name)
    }

    private var currentSignerName: String? {
        mode == .type ? typed.trimmedName : signerName
    }

    private var signatureReady: Bool {
        mode == .draw ? model.isValid : typed.isValid
    }

    private var canFinish: Bool {
        signatureReady && (consentText == nil || agreed)
    }

    private var problem: String? {
        guard attempted else { return nil }
        if !signatureReady {
            return mode == .draw ? model.validation.message : "Type your full name to sign."
        }
        if consentText != nil, !agreed { return "Tick the box to confirm it's your signature." }
        return nil
    }

    private func finish() {
        guard canFinish else {
            attempted = true
            withAnimation(reduceMotion ? nil : .linear(duration: 0.4)) { shakes += 1 }
            return
        }
        let content: KitoCapturedSignature.Content = mode == .draw ? .drawn(model.data) : .typed(typed)
        let result = KitoCapturedSignature(content: content, signerName: currentSignerName, signedAt: Date(),
                                           consent: consentText)
        onDone(result)
        dismiss()
    }

    private func cancel() {
        onCancel?()
        dismiss()
    }

    private func switchTo(_ newMode: KitoSignatureMode) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.8)) { mode = newMode }
    }

    private func preferTypingForVoiceOver() {
        guard voiceOver, !didChooseMode, modes.contains(.type) else { return }
        mode = .type
    }

    private func slide(from edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: edge).combined(with: .opacity),
                                              removal: .opacity)
    }
}

/// A horizontal wobble for "not yet" feedback.
struct KitoShakeEffect: GeometryEffect {
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }

    private var offset: CGFloat {
        8 * sin(shakes * .pi * 4)
    }
}

public extension View {
    /// Presents `KitoSignatureSheet` as a full-height bottom sheet. Swipe-to-dismiss is off so a
    /// downward stroke never closes the sheet; use the ✕ button instead.
    func kitoSignatureSheet(isPresented: Binding<Bool>, title: String = "Add your signature",
                            message: String? = nil, signerName: String? = nil,
                            consentText: String? = "I agree this is my signature",
                            modes: [KitoSignatureMode] = KitoSignatureMode.allCases, tint: Color? = nil,
                            onDone: @escaping (KitoCapturedSignature) -> Void) -> some View {
        sheet(isPresented: isPresented) {
            KitoSignatureSheet(title: title, message: message, signerName: signerName, consentText: consentText,
                               modes: modes, tint: tint, onDone: onDone)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .interactiveDismissDisabled()
        }
    }
}
