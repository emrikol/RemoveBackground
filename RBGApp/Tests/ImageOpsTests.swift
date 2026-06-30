// SPDX-FileCopyrightText: 2026 emrikol
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import CoreGraphics
@testable import RemoveBackground
import SwiftUI
import XCTest

final class ImageOpsTests: XCTestCase {
    private func cutout(_ w: Int = 6, _ h: Int = 4) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 0.5)) // semi-transparent
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    func testFlattenTransparentReturnsCutoutUnchanged() {
        let c = cutout()
        let out = flatten(c, on: .transparent)
        XCTAssertNotNil(out)
        XCTAssertEqual(out?.width, c.width)
        XCTAssertEqual(out?.height, c.height)
    }

    func testFlattenOnColorKeepsDimensions() {
        let c = cutout()
        let out = flatten(c, on: .color(.white))
        XCTAssertNotNil(out)
        XCTAssertEqual(out?.width, c.width)
        XCTAssertEqual(out?.height, c.height)
    }

    func testFlattenOnGradientProducesImage() {
        XCTAssertNotNil(flatten(cutout(), on: .gradient([.white, .black])))
    }
}
