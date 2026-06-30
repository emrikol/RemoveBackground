// SPDX-FileCopyrightText: 2026 emrikol
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

@testable import RemoveBackground
import XCTest

final class ModelsTests: XCTestCase {
    func testLookupAndFallback() {
        XCTAssertEqual(Models.by(id: "rmbg2").id, "rmbg2")
        XCTAssertEqual(Models.by(id: "birefnet_matting").id, "birefnet_matting")
        XCTAssertEqual(Models.by(id: "no-such-model").id, Models.all[0].id, "unknown id falls back to the first model")
    }

    func testRegistryWellFormed() {
        XCTAssertFalse(Models.all.isEmpty)
        let ids = Models.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "model ids must be unique")
        for m in Models.all {
            XCTAssertFalse(m.id.isEmpty)
            XCTAssertFalse(m.name.isEmpty)
            XCTAssertFalse(m.license.isEmpty)
            XCTAssertGreaterThan(m.inputSize, 0)
        }
    }
}
