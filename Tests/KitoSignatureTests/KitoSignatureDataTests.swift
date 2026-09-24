//
//  KitoSignatureDataTests.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import XCTest
import UIKit
@testable import KitoSignature

enum Fixtures {
    /// Two strokes: a zig-zag from (10,20) to (110,60), then a short dash.
    static var signature: KitoSignatureData {
        let zigzag = (0...20).map { index in
            KitoSignaturePoint(x: 10 + Double(index) * 5, y: index.isMultiple(of: 2) ? 20 : 60, t: Double(index) * 0.02)
        }
        let dash = (0...4).map { KitoSignaturePoint(x: 40 + Double($0) * 5, y: 80, t: 1.4 + Double($0) * 0.02) }
        return KitoSignatureData(strokes: [
            KitoSignatureStroke(points: zigzag, ink: .royalBlue),
            KitoSignatureStroke(points: dash),
        ], canvasSize: CGSize(width: 300, height: 150), createdAt: Date(timeIntervalSince1970: 1_790_000_000))
    }
}

final class KitoSignatureDataTests: XCTestCase {
    func testBoundingBox() {
        XCTAssertEqual(Fixtures.signature.boundingBox, CGRect(x: 10, y: 20, width: 100, height: 60))
        XCTAssertTrue(KitoSignatureData().boundingBox.isNull)
    }

    func testEmptiness() {
        XCTAssertTrue(KitoSignatureData().isEmpty)
        XCTAssertTrue(KitoSignatureData(strokes: [KitoSignatureStroke(points: [])]).isEmpty)
        XCTAssertFalse(Fixtures.signature.isEmpty)
        XCTAssertEqual(Fixtures.signature.pointCount, 26)
    }

    func testStrokeLength() {
        let stroke = KitoSignatureStroke(points: [KitoSignaturePoint(x: 0, y: 0), KitoSignaturePoint(x: 3, y: 4),
                                                  KitoSignaturePoint(x: 3, y: 10)])
        XCTAssertEqual(stroke.length, 11, accuracy: 1e-9)
    }

    func testNormalizedFitsTheUnitSquareKeepingShape() {
        let normal = Fixtures.signature.normalized()
        let box = normal.boundingBox
        XCTAssertEqual(box.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(box.minY, 0, accuracy: 1e-9)
        XCTAssertEqual(box.width, 1, accuracy: 1e-9)
        XCTAssertEqual(box.height, 0.6, accuracy: 1e-9)
        XCTAssertEqual(normal.canvasSize.width, 1, accuracy: 1e-9)
        // Pen widths scale with the points.
        XCTAssertEqual(normal.strokes[0].pen.maxWidth, KitoPenStyle.fountain.maxWidth / 100, accuracy: 1e-9)
    }

    func testRescalingKeepsProportionalWidths() {
        let original = Fixtures.signature
        let doubled = original.transformed(scale: 2)
        let a = KitoInkEngine.widths(for: original.strokes[0].points, pen: original.strokes[0].pen)
        let b = KitoInkEngine.widths(for: doubled.strokes[0].points, pen: doubled.strokes[0].pen)
        for (small, large) in zip(a, b) {
            XCTAssertEqual(large, small * 2, accuracy: 1e-6)
        }
        XCTAssertEqual(doubled.canvasSize, CGSize(width: 600, height: 300))
    }

    func testFittedCentresInsideRect() {
        let fitted = Fixtures.signature.fitted(in: CGRect(x: 0, y: 0, width: 220, height: 220), padding: 10)
        let box = fitted.boundingBox
        XCTAssertEqual(box.width, 200, accuracy: 1e-6)
        XCTAssertEqual(box.height, 120, accuracy: 1e-6)
        XCTAssertEqual(box.midX, 110, accuracy: 1e-6)
        XCTAssertEqual(box.midY, 110, accuracy: 1e-6)
    }

    func testCodableRoundTrip() throws {
        var data = Fixtures.signature
        data.strokes[0].points[3].pressure = 0.7
        let json = try data.jsonData()
        let decoded = try KitoSignatureData(jsonData: json)
        XCTAssertEqual(decoded, data)
        XCTAssertEqual(decoded.strokes[0].ink, .royalBlue)
        XCTAssertEqual(decoded.strokes[0].points[3].pressure, 0.7)
        XCTAssertTrue(String(decoding: json, as: UTF8.self).contains("\"p\":0.7"))
    }

    func testReplayShortensPausesAndGrowsStrokes() {
        let data = Fixtures.signature
        // Stroke one lasts 0.4 s, the 1.0 s pause is shortened, stroke two lasts 0.08 s.
        XCTAssertEqual(data.replayDuration, 0.4 + KitoSignatureData.maxReplayPause + 0.08, accuracy: 1e-9)
        XCTAssertEqual(data.replayed(upTo: 0).strokes.count, 1)
        XCTAssertEqual(data.replayed(upTo: 0.21).strokes[0].points.count, 11)
        XCTAssertEqual(data.replayed(upTo: 0.5).strokes.count, 1)
        let done = data.replayed(upTo: 10)
        XCTAssertEqual(done.strokes, data.strokes)
    }

    func testStrokeDistanceForErasing() {
        let stroke = KitoSignatureStroke(points: [KitoSignaturePoint(x: 0, y: 0), KitoSignaturePoint(x: 100, y: 0)])
        XCTAssertEqual(stroke.distance(to: CGPoint(x: 50, y: 12)), 12, accuracy: 1e-9)
        XCTAssertEqual(stroke.distance(to: CGPoint(x: -3, y: 4)), 5, accuracy: 1e-9)
    }

    func testFitTransform() {
        let t = KitoSignatureGeometry.fitTransform(from: CGRect(x: 0, y: 0, width: 50, height: 10),
                                                   into: CGRect(x: 0, y: 0, width: 100, height: 100), padding: 0)
        XCTAssertEqual(t.a, 2)
        XCTAssertEqual(t.ty, 40)
    }
}

final class KitoSignatureRenderingTests: XCTestCase {
    func testInkBoundsIncludeLineWidth() {
        let bounds = Fixtures.signature.inkBounds
        XCTAssertLessThan(bounds.minX, 10)
        XCTAssertGreaterThan(bounds.maxX, 110)
    }

    func testImageCropsToInkPlusPadding() throws {
        let data = Fixtures.signature
        let image = try XCTUnwrap(data.image(padding: 10, scale: 1))
        XCTAssertEqual(image.size.width, ceil(data.inkBounds.width + 20))
        let sized = try XCTUnwrap(data.image(size: CGSize(width: 300, height: 100), scale: 2, background: .white))
        XCTAssertEqual(sized.size, CGSize(width: 300, height: 100))
        XCTAssertNotNil(data.pngData())
    }

    func testPDFStartsWithHeader() throws {
        let pdf = try XCTUnwrap(Fixtures.signature.pdfData())
        XCTAssertEqual(String(decoding: pdf.prefix(5), as: UTF8.self), "%PDF-")
    }

    func testEmptyExportsReturnNil() {
        XCTAssertNil(KitoSignatureData().image())
        XCTAssertNil(KitoSignatureData().svg())
    }

    func testSVGDocument() throws {
        let svg = try XCTUnwrap(Fixtures.signature.svg(size: CGSize(width: 200, height: 80)))
        XCTAssertTrue(svg.hasPrefix("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"80\""))
        XCTAssertEqual(svg.components(separatedBy: "<path ").count - 1, 2)
        XCTAssertTrue(svg.contains("fill=\"\(KitoInk.royalBlue.hex)\""))
        XCTAssertTrue(svg.hasSuffix("</svg>"))
    }
}

final class KitoSVGTests: XCTestCase {
    func testNumberFormatting() {
        XCTAssertEqual(KitoSVG.number(12, 2), "12")
        XCTAssertEqual(KitoSVG.number(3.5, 2), "3.5")
        XCTAssertEqual(KitoSVG.number(1.23456, 2), "1.23")
        XCTAssertEqual(KitoSVG.number(-0.001, 2), "0")
    }

    func testPolygonPathData() {
        let d = KitoSVG.pathData(polygon: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 5.25)])
        XCTAssertEqual(d, "M0 0 L10 0 L10 5.25 Z")
        XCTAssertEqual(KitoSVG.pathData(polygon: [CGPoint(x: 1, y: 1)]), "")
    }

    func testCenterlineUsesQuadratics() {
        let d = KitoSVG.centerlineData([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 0)])
        XCTAssertEqual(d, "M0 0 Q10 10 15 5 L20 0")
        XCTAssertEqual(KitoSVG.centerlineData([CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 2)]), "M0 0 L4 2")
    }

    func testCGPathData() {
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 4, y: 0))
        path.addQuadCurve(to: CGPoint(x: 8, y: 8), control: CGPoint(x: 8, y: 0))
        path.closeSubpath()
        XCTAssertEqual(KitoSVG.pathData(path), "M0 0 L4 0 Q8 0 8 8 Z")
    }

    func testInkHex() {
        XCTAssertEqual(KitoInk.white.hex, "#FFFFFF")
        XCTAssertEqual(KitoInk(name: "x", red: 1, green: 0, blue: 0.5).hex, "#FF0080")
    }
}
