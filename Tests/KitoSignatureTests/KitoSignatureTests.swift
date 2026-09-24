//
//  KitoSignatureTests.swift
//  KitoSignature
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import XCTest
@testable import KitoSignature

final class KitoSignatureVersionTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(KitoSignature.version, "0.1.0")
    }
}
