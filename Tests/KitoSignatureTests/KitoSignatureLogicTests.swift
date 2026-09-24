//
//  KitoSignatureLogicTests.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import XCTest
import UIKit
@testable import KitoSignature

final class KitoSignatureValidatorTests: XCTestCase {
    private let validator = KitoSignatureValidator(minimumPoints: 10, minimumLength: 60, minimumSize: 32)

    func testEmpty() {
        XCTAssertEqual(validator.validate(KitoSignatureData()), .empty)
        XCTAssertNotNil(KitoSignatureValidation.empty.message)
    }

    func testDotIsTooShort() {
        let dot = KitoSignatureData(strokes: [KitoSignatureStroke(points: [KitoSignaturePoint(x: 5, y: 5)])])
        XCTAssertEqual(validator.validate(dot), .tooShort)
    }

    func testTinyScribbleIsTooSmall() {
        // Lots of ink packed into a 10 × 10 box.
        let points = (0..<40).map { KitoSignaturePoint(x: Double($0 % 2) * 10, y: Double($0 % 3) * 5) }
        let data = KitoSignatureData(strokes: [KitoSignatureStroke(points: points)])
        XCTAssertEqual(validator.validate(data), .tooSmall)
    }

    func testRealSignatureIsValid() {
        let result = validator.validate(Fixtures.signature)
        XCTAssertEqual(result, .valid)
        XCTAssertTrue(result.isValid)
        XCTAssertNil(result.message)
    }

    func testLenientAcceptsAnything() {
        let dot = KitoSignatureData(strokes: [KitoSignatureStroke(points: [KitoSignaturePoint(x: 5, y: 5)])])
        XCTAssertEqual(KitoSignatureValidator.lenient.validate(dot), .valid)
    }
}

final class KitoUndoStackTests: XCTestCase {
    func testUndoRedo() {
        var stack = KitoUndoStack(0)
        stack.push(1)
        stack.push(2)
        XCTAssertEqual(stack.undo(), 1)
        XCTAssertEqual(stack.undo(), 0)
        XCTAssertNil(stack.undo())
        XCTAssertEqual(stack.redo(), 1)
        XCTAssertEqual(stack.current, 1)
        XCTAssertTrue(stack.canUndo)
        XCTAssertTrue(stack.canRedo)
    }

    func testPushClearsRedo() {
        var stack = KitoUndoStack("a")
        stack.push("b")
        stack.undo()
        stack.push("c")
        XCTAssertFalse(stack.canRedo)
        XCTAssertEqual(stack.undo(), "a")
    }

    func testRepeatsAreIgnoredAndLimitHolds() {
        var stack = KitoUndoStack(0, limit: 3)
        stack.push(0)
        XCTAssertFalse(stack.canUndo)
        for value in 1...10 { stack.push(value) }
        XCTAssertEqual(stack.undoCount, 3)
        stack.reset(to: 42)
        XCTAssertEqual(stack.current, 42)
        XCTAssertFalse(stack.canUndo)
    }
}

final class KitoSignatureCaptionTests: XCTestCase {
    func testShortName() {
        XCTAssertEqual(KitoSignatureCaption.shortName("Wycliff Njenga"), "Wycliff N")
        XCTAssertEqual(KitoSignatureCaption.shortName("  amina  wanjiru odhiambo "), "amina O")
        XCTAssertEqual(KitoSignatureCaption.shortName("Cher"), "Cher")
        XCTAssertEqual(KitoSignatureCaption.shortName("   "), "")
    }

    func testCaptionText() {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 24
        components.hour = 12
        let date = Calendar(identifier: .gregorian).date(from: components) ?? Date()
        let posix = Locale(identifier: "en_US_POSIX")
        let caption = KitoSignatureCaption(signerName: "Wycliff Njenga", date: date, locale: posix)
        XCTAssertEqual(caption.text, "Signed by Wycliff N · 24 Sep 2026")
        let full = KitoSignatureCaption(signerName: "Wycliff Njenga", date: date, abbreviatesSurname: false, locale: posix)
        XCTAssertEqual(full.text, "Signed by Wycliff Njenga · 24 Sep 2026")
        XCTAssertEqual(KitoSignatureCaption(signerName: "", date: date, locale: posix).text, "Signed · 24 Sep 2026")
    }
}

@MainActor
final class KitoSignatureModelTests: XCTestCase {
    private func draw(_ model: KitoSignatureModel, from x: Double, count: Int = 10) {
        let start = Date(timeIntervalSince1970: 100)
        model.begin(at: CGPoint(x: x, y: 50), date: start)
        for step in 1..<count {
            let point = CGPoint(x: x + Double(step) * 10, y: 50 + Double(step % 2) * 20)
            model.extend(to: point, date: start.addingTimeInterval(Double(step) * 0.02))
        }
        model.end()
    }

    func testDrawingUndoRedoClear() {
        let model = KitoSignatureModel()
        XCTAssertTrue(model.isEmpty)
        draw(model, from: 0)
        draw(model, from: 20)
        XCTAssertEqual(model.strokes.count, 2)
        model.undo()
        XCTAssertEqual(model.strokes.count, 1)
        model.redo()
        XCTAssertEqual(model.strokes.count, 2)
        model.clear()
        XCTAssertTrue(model.isEmpty)
        model.undo()
        XCTAssertEqual(model.strokes.count, 2)
    }

    func testCloseSamplesAreSkipped() {
        let model = KitoSignatureModel()
        let now = Date()
        model.begin(at: .zero, date: now)
        model.extend(to: CGPoint(x: 0.3, y: 0), date: now)
        model.extend(to: CGPoint(x: 10, y: 0), date: now.addingTimeInterval(0.01))
        XCTAssertEqual(model.activeStroke?.points.count, 2)
        XCTAssertTrue(model.isDrawing)
        model.end()
        XCTAssertFalse(model.isDrawing)
    }

    func testTimestampsAreRelativeToTheFirstPoint() throws {
        let model = KitoSignatureModel()
        draw(model, from: 0)
        let stroke = try XCTUnwrap(model.strokes.first)
        XCTAssertEqual(stroke.points.first?.t, 0)
        XCTAssertEqual(try XCTUnwrap(stroke.points.last?.t), 0.18, accuracy: 1e-6)
    }

    func testStrokesUseTheCurrentInkAndPen() {
        let model = KitoSignatureModel(ink: .navy, pen: .fineliner)
        draw(model, from: 0)
        model.ink = .burgundy
        draw(model, from: 30)
        XCTAssertEqual(model.strokes.map(\.ink), [.navy, .burgundy])
        XCTAssertEqual(model.strokes[0].pen, .fineliner)
    }

    func testEraseRemovesTouchedStrokesAndUndoesInOneStep() {
        let model = KitoSignatureModel()
        draw(model, from: 0, count: 3)
        draw(model, from: 400, count: 3)
        model.erase(at: CGPoint(x: 10, y: 60), radius: 10)
        XCTAssertEqual(model.strokes.count, 1)
        model.commitErase()
        model.undo()
        XCTAssertEqual(model.strokes.count, 2)
    }

    func testValidationAndLoad() {
        let model = KitoSignatureModel()
        XCTAssertEqual(model.validation, .empty)
        model.load(Fixtures.signature)
        XCTAssertTrue(model.isValid)
        XCTAssertFalse(model.canUndo)
        XCTAssertEqual(model.data.strokes, Fixtures.signature.strokes)
    }
}

final class KitoTypedSignatureTests: XCTestCase {
    func testGlyphPathHasInk() {
        let value = KitoTypedSignatureValue(name: "Wycliff Njenga", style: .classic)
        XCTAssertTrue(value.isValid)
        let bounds = value.inkBounds
        XCTAssertFalse(bounds.isNull)
        XCTAssertGreaterThan(bounds.width, bounds.height)
        // Glyphs sit on the baseline with y pointing down, so they rise into negative y.
        XCTAssertLessThan(bounds.minY, 0)
    }

    func testEveryStyleRenders() {
        for style in KitoTypedSignatureStyle.allCases {
            let value = KitoTypedSignatureValue(name: "Amina", style: style)
            XCTAssertFalse(value.inkBounds.isNull, style.title)
            XCTAssertNotNil(value.svg(), style.title)
        }
    }

    func testEmptyAndSingleLetterNamesAreInvalid() {
        XCTAssertFalse(KitoTypedSignatureValue(name: "   ").isValid)
        XCTAssertFalse(KitoTypedSignatureValue(name: "W").isValid)
        XCTAssertTrue(KitoTypedSignatureValue(name: "   ").inkPaths().isEmpty)
        XCTAssertEqual(KitoTypedSignatureValue(name: "  Wycliff   Njenga ").trimmedName, "Wycliff Njenga")
    }

    func testCapturedRoundTrip() throws {
        let typed = KitoCapturedSignature.typed(KitoTypedSignatureValue(name: "Wycliff Njenga", style: .rounded, ink: .navy),
                                                signedAt: Date(timeIntervalSince1970: 1_790_000_000))
        let drawn = KitoCapturedSignature(content: .drawn(Fixtures.signature), signerName: "Wycliff",
                                          signedAt: Date(timeIntervalSince1970: 1_790_000_000), consent: "I agree")
        for signature in [typed, drawn] {
            let data = try JSONEncoder().encode(signature)
            XCTAssertEqual(try JSONDecoder().decode(KitoCapturedSignature.self, from: data), signature)
        }
        XCTAssertTrue(typed.isTyped)
        XCTAssertEqual(typed.signerName, "Wycliff Njenga")
        XCTAssertFalse(drawn.isTyped)
    }
}

final class KitoCanvasBackgroundTests: XCTestCase {
    private let rect = CGRect(x: 0, y: 0, width: 100, height: 60)

    func testLinedPaper() {
        let lines = KitoCanvasBackground.lined.lines(in: rect, spacing: 20)
        XCTAssertEqual(lines.map(\.start.y), [20, 40])
        XCTAssertEqual(KitoCanvasBackground.lined.marginX(in: rect, spacing: 20), 40)
    }

    func testGridHasRowsAndColumns() {
        let lines = KitoCanvasBackground.grid.lines(in: rect, spacing: 20)
        XCTAssertEqual(lines.count, 2 + 4)
        XCTAssertNil(KitoCanvasBackground.grid.marginX(in: rect, spacing: 20))
    }

    func testDotsAndBlank() {
        XCTAssertEqual(KitoCanvasBackground.dotted.dots(in: rect, spacing: 20).count, 2 * 4)
        XCTAssertTrue(KitoCanvasBackground.dotted.lines(in: rect, spacing: 20).isEmpty)
        XCTAssertTrue(KitoCanvasBackground.blank.lines(in: rect, spacing: 20).isEmpty)
        XCTAssertTrue(KitoCanvasBackground.blank.dots(in: rect, spacing: 20).isEmpty)
        XCTAssertTrue(KitoCanvasBackground.grid.lines(in: rect, spacing: 0).isEmpty)
    }
}

final class KitoAnnotationGeometryTests: XCTestCase {
    func testFitRectCentresTheImage() {
        let rect = KitoAnnotationGeometry.fitRect(for: CGSize(width: 400, height: 200), in: CGSize(width: 200, height: 200))
        XCTAssertEqual(rect, CGRect(x: 0, y: 50, width: 200, height: 100))
        XCTAssertEqual(KitoAnnotationGeometry.fitRect(for: .zero, in: CGSize(width: 10, height: 10)), .zero)
    }

    func testArrowHeadPointsBack() {
        let head = KitoAnnotationGeometry.arrowHead(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0),
                                                    length: 10, spread: .pi / 4)
        XCTAssertEqual(head.left.x, 100 - 10 * cos(.pi / 4), accuracy: 1e-9)
        XCTAssertEqual(head.left.y, 10 * sin(.pi / 4), accuracy: 1e-9)
        XCTAssertEqual(head.right.y, -10 * sin(.pi / 4), accuracy: 1e-9)
    }

    func testLabelContrast() {
        XCTAssertTrue(KitoAnnotationGeometry.labelTextIsDark(on: .yellow))
        XCTAssertFalse(KitoAnnotationGeometry.labelTextIsDark(on: .red))
    }
}

@MainActor
final class KitoAnnotationModelTests: XCTestCase {
    private func photo() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        }
    }

    func testMarksUndoAndFlatten() {
        let model = KitoAnnotationModel(image: photo())
        model.begin(at: CGPoint(x: 10, y: 10))
        model.extend(to: CGPoint(x: 40, y: 30))
        model.extend(to: CGPoint(x: 80, y: 20))
        model.end()
        model.tool = .arrow
        model.begin(at: CGPoint(x: 20, y: 80))
        model.extend(to: CGPoint(x: 150, y: 40))
        model.end()
        model.addText("Dented", at: CGPoint(x: 100, y: 50))
        XCTAssertEqual(model.annotations.count, 3)
        model.undo()
        XCTAssertEqual(model.annotations.count, 2)
        let flat = model.flattenedImage()
        XCTAssertEqual(flat.size, CGSize(width: 200, height: 100))
    }

    func testTinyArrowsAndBlankNotesAreDropped() {
        let model = KitoAnnotationModel(image: photo(), tool: .arrow)
        model.begin(at: CGPoint(x: 10, y: 10))
        model.extend(to: CGPoint(x: 11, y: 10))
        model.end()
        model.addText("   ", at: .zero)
        XCTAssertTrue(model.isEmpty)
    }

    func testHighlighterIsWideAndTranslucent() throws {
        let model = KitoAnnotationModel(image: photo(), tool: .highlighter, ink: .yellow)
        model.begin(at: CGPoint(x: 10, y: 10))
        model.extend(to: CGPoint(x: 90, y: 10))
        model.end()
        let mark = try XCTUnwrap(model.annotations.first)
        XCTAssertEqual(mark.ink.opacity, 0.4)
        XCTAssertEqual(mark.lineWidth, 2 * 3.5, accuracy: 1e-9)
    }
}
