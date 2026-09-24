# ``KitoSignature``

Signature capture, typed signatures, drawing canvases and photo markup for SwiftUI.

## Overview

KitoSignature covers everything from a single signature to free-form drawing. The quickest
route is the `kitoSignatureSheet(isPresented:title:message:signerName:consentText:modes:tint:onDone:)`
modifier, which presents ``KitoSignatureSheet`` with Draw and Type tabs and a consent checkbox,
and hands back a ``KitoCapturedSignature`` when the person taps Done.

```swift
struct DeliveryView: View {
    @State private var signing = false
    @State private var proof: KitoCapturedSignature?

    var body: some View {
        Button("Sign for your parcel") { signing = true }
            .kitoSignatureSheet(isPresented: $signing, title: "Sign for your parcel",
                                signerName: "Wycliff Njenga") { signature in
                proof = signature
            }
    }
}
```

Inside forms, ``KitoSignatureField`` opens the same sheet and shows the signature once it is
signed. For a pad embedded directly in a screen, ``KitoSignaturePad`` draws with a
velocity-sensitive pen backed by a ``KitoSignatureModel``, while ``KitoTypedSignature`` renders a
typed name in one of several handwriting styles, which is also the accessible way to sign.

Signatures are stored as `Codable` strokes in ``KitoSignatureData`` and re-render at any size with
``KitoSignatureView``. Anything that conforms to ``KitoSignatureRenderable`` exports as a
transparent PNG, a PNG on a background, PDF or SVG. Beyond signatures, ``KitoDrawingCanvas`` wraps
PencilKit with paper backgrounds, ``KitoSketchCanvas`` offers the same in pure SwiftUI, and
``KitoAnnotationView`` marks up a photo.

If your app also imports KitoOrderTracking, which declares its own `KitoSignaturePad`, write
`KitoSignature.KitoSignaturePad` to pick this one.

## Topics

### Essentials

- ``KitoSignatureSheet``
- ``KitoSignatureField``
- ``KitoCapturedSignature``
- ``KitoSignatureMode``

### Signature Pad

- ``KitoSignaturePad``
- ``KitoSignatureModel``
- ``KitoSignatureCaption``
- ``KitoSignatureValidator``
- ``KitoSignatureValidation``
- ``KitoInk``
- ``KitoPenStyle``

### Typed Signatures

- ``KitoTypedSignature``
- ``KitoTypedSignatureValue``
- ``KitoTypedSignatureStyle``

### Storage and Export

- ``KitoSignatureData``
- ``KitoSignatureStroke``
- ``KitoSignaturePoint``
- ``KitoSignatureView``
- ``KitoSignatureRenderable``
- ``KitoSignatureBackground``
- ``KitoInkPath``
- ``KitoSVG``

### Drawing and Markup

- ``KitoDrawingCanvas``
- ``KitoDrawingController``
- ``KitoDrawingTool``
- ``KitoSketchCanvas``
- ``KitoCanvasBackground``
- ``KitoCanvasBackgroundView``
- ``KitoCanvasLine``
- ``KitoAnnotationView``
- ``KitoAnnotationModel``
- ``KitoAnnotation``
- ``KitoAnnotationTool``
- ``KitoAnnotationGeometry``

### Building Blocks

- ``KitoInkSwatches``
- ``KitoSignatureToolButton``
- ``KitoConsentCheckbox``
- ``KitoInkEngine``
- ``KitoInkSample``
- ``KitoUndoStack``
