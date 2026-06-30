// SPDX-FileCopyrightText: 2026 emrikol
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import AppKit
@testable import RemoveBackground
import XCTest

@MainActor
final class AppModelTests: XCTestCase {
    /// A tiny CGImage-backed NSImage so `load`'s decodability check passes.
    private func img(_ w: Int = 8, _ h: Int = 8) -> NSImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: w, height: h))
    }

    func testLoadSingle() {
        let m = AppModel()
        m.load(img())
        XCTAssertEqual(m.items.count, 1)
        XCTAssertFalse(m.isBatch)
        XCTAssertEqual(m.pendingCount, 1)
        XCTAssertEqual(m.doneCount, 0)
        XCTAssertEqual(m.selectedIndex, 0)
        XCTAssertNotNil(m.inputImage)
    }

    func testLoadManyIsBatch() {
        let m = AppModel()
        m.load([img(), img(), img()])
        XCTAssertEqual(m.items.count, 3)
        XCTAssertTrue(m.isBatch)
        XCTAssertEqual(m.pendingCount, 3)
        XCTAssertEqual(m.selectedIndex, 0)
    }

    func testLoadAppendsAndSelectsNew() {
        let m = AppModel()
        m.load([img(), img()])
        m.load(img())
        XCTAssertEqual(m.items.count, 3)
        XCTAssertEqual(m.selectedIndex, 2, "a freshly added image becomes the selected one")
    }

    func testSwitchingModelClearsResults() {
        let m = AppModel()
        m.load(img())
        m.items[0].state = .done
        m.items[0].output = img()
        m.select("birefnet") // different from the default rmbg2
        XCTAssertEqual(m.selectedID, "birefnet")
        XCTAssertEqual(m.items[0].state, .pending)
        XCTAssertNil(m.items[0].output)
    }

    func testSelectItemIgnoresOutOfRange() {
        let m = AppModel()
        m.load([img(), img()])
        m.selectItem(99)
        XCTAssertEqual(m.selectedIndex, 0)
        m.selectItem(1)
        XCTAssertEqual(m.selectedIndex, 1)
    }

    func testReset() {
        let m = AppModel()
        m.load([img(), img()])
        m.reset()
        XCTAssertTrue(m.items.isEmpty)
        XCTAssertNil(m.inputImage)
        XCTAssertFalse(m.hasOutput)
    }

    func testFriendlyErrorMapping() {
        let m = AppModel()
        let network = NSError(domain: NSURLErrorDomain, code: -1009)
        XCTAssertTrue(m.friendlyError(network).contains("Download failed"))
        let other = NSError(domain: "RBG", code: 1)
        XCTAssertTrue(m.friendlyError(other).contains("Run Again to retry"))
    }

    func testRemoveItemKeepsSelectionAndFallsBackToEmpty() {
        let m = AppModel()
        m.load([img(), img(), img()])
        m.selectItem(2)
        m.removeItem(0) // removing before the selected shifts it down
        XCTAssertEqual(m.items.count, 2)
        XCTAssertEqual(m.selectedIndex, 1)
        m.removeItem(1) // remove the selected (last) → clamps
        XCTAssertEqual(m.items.count, 1)
        XCTAssertEqual(m.selectedIndex, 0)
        XCTAssertFalse(m.isBatch)
        m.removeItem(0) // remove the last → empty state
        XCTAssertTrue(m.items.isEmpty)
        XCTAssertNil(m.inputImage)
    }
}
