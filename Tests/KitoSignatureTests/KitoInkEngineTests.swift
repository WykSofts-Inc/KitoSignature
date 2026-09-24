//
//  KitoInkEngineTests.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import XCTest
@testable import KitoSignature

final class KitoPenStyleTests: XCTestCase {
    func testWidthFollowsVelocity() {
        let pen = KitoPenStyle(minWidth: 1, maxWidth: 5, slowVelocity: 100, fastVelocity: 500)
        XCTAssertEqual(pen.width(forVelocity: 0), 5)
        XCTAssertEqual(pen.width(forVelocity: 100), 5)
        XCTAssertEqual(pen.width(forVelocity: 300), 3, accuracy: 0.0001)
        XCTAssertEqual(pen.width(forVelocity: 500), 1)
        XCTAssertEqual(pen.width(forVelocity: 10_000), 1)
    }

    func testScalingScalesWidthsAndSpeeds() {
        let pen = KitoPenStyle(minWidth: 1, maxWidth: 4, slowVelocity: 50, fastVelocity: 1_000, minDistance: 1)
        let doubled = pen.scaled(by: 2)
        XCTAssertEqual(doubled.minWidth, 2)
        XCTAssertEqual(doubled.maxWidth, 8)
        XCTAssertEqual(doubled.slowVelocity, 100)
        XCTAssertEqual(doubled.fastVelocity, 2_000)
        XCTAssertEqual(doubled.minDistance, 2)
        XCTAssertEqual(doubled.responsiveness, pen.responsiveness)
    }

    func testInitClampsNonsense() {
        let pen = KitoPenStyle(minWidth: 4, maxWidth: 2, slowVelocity: 500, fastVelocity: 100, responsiveness: 3)
        XCTAssertEqual(pen.maxWidth, 4)
        XCTAssertGreaterThan(pen.fastVelocity, pen.slowVelocity)
        XCTAssertEqual(pen.responsiveness, 1)
    }
}

final class KitoInkEngineTests: XCTestCase {
    private func line(speed: Double, count: Int = 30, spacing: Double = 5) -> [KitoSignaturePoint] {
        // Points `spacing` apart; the time between them sets the speed.
        (0..<count).map { KitoSignaturePoint(x: Double($0) * spacing, y: 0, t: Double($0) * spacing / speed) }
    }

    func testSlowStrokesAreThickerThanFastOnes() throws {
        let pen = KitoPenStyle.fountain
        let slow = try XCTUnwrap(KitoInkEngine.widths(for: line(speed: 40), pen: pen).last)
        let fast = try XCTUnwrap(KitoInkEngine.widths(for: line(speed: 3_000, spacing: 20), pen: pen).last)
        XCTAssertGreaterThan(slow, fast)
        XCTAssertEqual(slow, pen.maxWidth, accuracy: 0.05)
        XCTAssertEqual(fast, pen.minWidth, accuracy: 0.05)
    }

    func testWidthsEaseRatherThanJump() {
        let pen = KitoPenStyle(responsiveness: 0.3)
        var points = line(speed: 40, count: 10)
        let last = points[points.count - 1]
        points.append(KitoSignaturePoint(x: last.x + 200, y: 0, t: last.t + 0.01))
        let widths = KitoInkEngine.widths(for: points, pen: pen)
        let drop = widths[widths.count - 2] - widths[widths.count - 1]
        XCTAssertGreaterThan(drop, 0)
        XCTAssertLessThan(drop, (pen.maxWidth - pen.minWidth) * 0.5)
    }

    func testPressureScalesWidth() {
        let pen = KitoPenStyle.ballpoint
        let light = KitoInkEngine.widths(for: [KitoSignaturePoint(x: 0, y: 0, pressure: 0)], pen: pen)
        let heavy = KitoInkEngine.widths(for: [KitoSignaturePoint(x: 0, y: 0, pressure: 1)], pen: pen)
        XCTAssertLessThan(light[0], heavy[0])
    }

    func testSpeedIsDistanceOverTime() {
        let a = KitoSignaturePoint(x: 0, y: 0, t: 0)
        let b = KitoSignaturePoint(x: 30, y: 40, t: 0.5)
        XCTAssertEqual(KitoInkEngine.speed(from: a, to: b), 100, accuracy: 0.0001)
        // Same timestamp doesn't divide by zero.
        XCTAssertTrue(KitoInkEngine.speed(from: a, to: KitoSignaturePoint(x: 1, y: 0, t: 0)).isFinite)
    }

    func testCatmullRomPassesThroughControlPoints() {
        let samples = [
            KitoInkSample(x: 0, y: 0, width: 1), KitoInkSample(x: 10, y: 10, width: 2),
            KitoInkSample(x: 20, y: 0, width: 3), KitoInkSample(x: 30, y: 10, width: 4),
        ]
        let start = KitoInkEngine.catmullRom(samples[0], samples[1], samples[2], samples[3], t: 0)
        let end = KitoInkEngine.catmullRom(samples[0], samples[1], samples[2], samples[3], t: 1)
        XCTAssertEqual(start.x, 10, accuracy: 1e-9)
        XCTAssertEqual(start.y, 10, accuracy: 1e-9)
        XCTAssertEqual(end.x, 20, accuracy: 1e-9)
        XCTAssertEqual(end.y, 0, accuracy: 1e-9)
        let middle = KitoInkEngine.catmullRom(samples[0], samples[1], samples[2], samples[3], t: 0.5)
        XCTAssertEqual(middle.width, 2.5, accuracy: 1e-9)
    }

    func testSmoothingAddsPointsAndKeepsEnds() throws {
        let samples = (0..<5).map { KitoInkSample(x: Double($0) * 20, y: $0.isMultiple(of: 2) ? 0 : 20, width: 2) }
        let smooth = KitoInkEngine.smoothed(samples, spacing: 2)
        XCTAssertGreaterThan(smooth.count, samples.count * 5)
        XCTAssertEqual(try XCTUnwrap(smooth.first), samples[0])
        let last = try XCTUnwrap(smooth.last)
        XCTAssertEqual(last.x, 80, accuracy: 1e-9)
        XCTAssertEqual(last.y, 0, accuracy: 1e-9)
    }

    func testSmoothingLeavesShortInputAlone() {
        let two = [KitoInkSample(x: 0, y: 0, width: 1), KitoInkSample(x: 5, y: 0, width: 1)]
        XCTAssertEqual(KitoInkEngine.smoothed(two), two)
    }

    func testOutlineWrapsTheLineWithItsWidth() {
        let samples = (0...10).map { KitoInkSample(x: Double($0) * 10, y: 50, width: 4) }
        let polygon = KitoInkEngine.outline(samples)
        let ys = polygon.map(\.y)
        let xs = polygon.map(\.x)
        XCTAssertEqual(ys.min() ?? 0, 48, accuracy: 0.001)
        XCTAssertEqual(ys.max() ?? 0, 52, accuracy: 0.001)
        // Round caps reach half a width past each end.
        XCTAssertEqual(xs.min() ?? 0, -2, accuracy: 0.1)
        XCTAssertEqual(xs.max() ?? 0, 102, accuracy: 0.1)
    }

    func testSinglePointBecomesADot() {
        let polygon = KitoInkEngine.outline([KitoInkSample(x: 10, y: 10, width: 4)])
        XCTAssertGreaterThanOrEqual(polygon.count, 6)
        for point in polygon {
            XCTAssertEqual(hypot(point.x - 10, point.y - 10), 2.4, accuracy: 0.001)
        }
    }

    func testDeduplicationDropsJitterButKeepsTheEnd() {
        let points = [
            KitoSignaturePoint(x: 0, y: 0), KitoSignaturePoint(x: 0.1, y: 0),
            KitoSignaturePoint(x: 5, y: 0), KitoSignaturePoint(x: 5.2, y: 0),
        ]
        let result = KitoInkEngine.deduplicated(points, minDistance: 1)
        XCTAssertEqual(result.map(\.x), [0, 5.2])
    }

    func testStrokePathIsNotEmpty() {
        let stroke = KitoSignatureStroke(points: line(speed: 200, count: 12))
        XCTAssertFalse(KitoInkEngine.path(for: stroke).isEmpty)
    }
}
