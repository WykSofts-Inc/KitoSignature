# KitoSignature

**[Documentation](https://wyksofts-inc.github.io/KitoSignature/documentation/kitosignature/)**

Signing and drawing for SwiftUI: a signature pad that writes like a pen, typed signatures in
handwriting styles, a bottom-sheet signing flow with consent, a form field, a PencilKit canvas with
paper backgrounds, a pure-SwiftUI sketch canvas, and photo markup. Signatures store as `Codable`
strokes and export as transparent PNG, PNG on white, PDF or SVG. Part of the
[Kito](https://github.com/WykSofts-Inc/KitoDevKit) ecosystem.

## Sign in a sheet

```swift
@State private var signing = false
@State private var proof: KitoCapturedSignature?

Button("Sign for your parcel") { signing = true }
    .kitoSignatureSheet(isPresented: $signing, title: "Sign for your parcel",
                        message: "Order #KE-2291 · 3 items", signerName: "Wycliff Njenga") { signature in
        proof = signature
    }
```

The sheet has Draw and Type tabs, a "I agree this is my signature" checkbox and Done. Done stays
soft until the signature counts and the box is ticked; tapping it early shakes what's missing and
says why. Swipe-to-dismiss is off so a downward stroke never closes the sheet.

## A signature field in a form

```swift
@State private var guardian: KitoCapturedSignature?

KitoSignatureField("Parent or guardian", signature: $guardian, signerName: "Amina Wanjiru",
                   sheetTitle: "Sign the consent form", isRequired: true)
```

Empty, the field invites a tap. Signed, it writes the signature in, shows "Signed ✓" and
"Signed by Amina W · 24 Sep 2026". Tap again to re-sign.

## The pad

```swift
@State private var signature = KitoSignatureModel()

KitoSignaturePad(model: signature,
                 caption: KitoSignatureCaption(signerName: "Wycliff Njenga"),
                 onTypeInstead: { mode = .type })
Button("Save") { save(signature.data) }.disabled(!signature.isValid)
```

Lines thin out when you move fast and swell when you slow down, and Catmull-Rom smoothing turns
touch samples into curves. The pad has a "✕ Sign here" baseline, a hint that fades once you start,
ink colours, undo, redo and clear. `KitoPenStyle` sets the feel (`.fountain`, `.ballpoint`,
`.fineliner`, `.marker`) and `KitoSignatureValidator` decides what's too short to count as a
signature.

## Typed signatures

```swift
@State private var typed = KitoTypedSignatureValue(name: "Wycliff Njenga", style: .script)

KitoTypedSignature(value: $typed)
```

Six styles — Script, Casual, Elegant, Classic, Modern and Rounded — use handwriting fonts that ship
with iOS, falling back to slanted system fonts. The name becomes glyph outlines, so it previews
and exports exactly like a drawn signature. This is the accessible way to sign: with VoiceOver on,
the sheet opens on Type, and the pad offers a "Type your name instead" button.

## Store, re-render and export

```swift
let json = try signature.data.jsonData()                  // strokes with points, time and pressure
let saved = try KitoSignatureData(jsonData: json)

KitoSignatureView(data: saved, replay: true)              // any size; replays stroke by stroke
    .frame(height: 60)

saved.pngData()                                           // transparent, cropped to the ink
saved.image(size: CGSize(width: 600, height: 200), background: .white)
saved.pdfData()                                           // vector
saved.svg()                                               // <svg>…</svg>
saved.normalized()                                        // origin 0, longer side 1
saved.fitted(in: CGRect(x: 0, y: 0, width: 300, height: 100), padding: 8)
```

`KitoCapturedSignature` (from the sheet and field) and `KitoTypedSignatureValue` export the same
way — anything `KitoSignatureRenderable` does.

## Drawing canvas

```swift
@State private var sketch = KitoDrawingController(background: .grid)

KitoDrawingCanvas(controller: sketch)                    // PencilKit
    .frame(height: 420)
let png = sketch.image()?.pngData()
```

Pen, marker, pencil and eraser with colours, blank, grid, lined or dotted paper, undo/redo, and a
switch to Apple's own tool picker. Without PencilKit, `KitoSketchCanvas` does the same job in pure
SwiftUI with the signature pen engine:

```swift
@State private var notes = KitoSignatureModel(pen: .ballpoint, validator: .lenient)

KitoSketchCanvas(model: notes, background: .lined)
let image = notes.canvasImage(background: .lined)
```

## Mark up a photo

```swift
@State private var markup = KitoAnnotationModel(image: parcelPhoto)

KitoAnnotationView(model: markup)                        // pen, highlighter, arrow, text
let proof = markup.flattenedImage()                      // full resolution
```

## Accessibility and motion

Every control has a label, the pad has Undo and Clear accessibility actions, and signatures read
as "Handwritten signature of Wycliff Njenga". Replays, reveals and the sliding ink ring switch off
with Reduce Motion. Automatic ink follows the theme on screen and exports as black, so it works in
light and dark mode.

If your app also uses KitoOrderTracking, which has its own small `KitoSignaturePad` for delivery
proof, write `KitoSignature.KitoSignaturePad` to pick this one.

## Right-to-left

Toolbars, fields and the form row mirror automatically, and the disclosure chevron follows the reading direction.
Ink is never mirrored: strokes, photo marks and exported images keep the exact shape the person drew, in every layout.
The sketch eraser cursor stays under the finger and the consent tick keeps its usual shape in right-to-left layouts.
Nothing extra is needed from the app.

## Migrating from 0.1

0.2.0 makes the tick drawn inside the "I agree" checkbox private to the package. It used to be
exported as `KitoCheckmarkShape`, which clashed with the shape of the same name in KitoButtons, so
a file importing both packages got "ambiguous" errors. If you drew that tick yourself, use
KitoButtons' `KitoCheckmarkShape` or your own `Shape`; nothing else changed.

## Installation

```swift
.package(url: "https://github.com/WykSofts-Inc/KitoSignature.git", from: "0.2.0")
```

## License

MIT — see [LICENSE](LICENSE).
