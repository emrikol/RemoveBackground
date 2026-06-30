// SPDX-FileCopyrightText: 2026 emrikol
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import Foundation
@testable import RemoveBackground
import XCTest

final class SecurityTests: XCTestCase {
    /// ModelStore.verify accepts a matching hash, skips when nil, and rejects + deletes a mismatch.
    func testModelHashVerification() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bin")
        let hello = Data("hello".utf8)
        let helloSHA = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"

        try hello.write(to: tmp)
        XCTAssertNoThrow(try ModelStore.verify(tmp, expected: helloSHA, name: "t"), "matching hash passes")
        XCTAssertNoThrow(try ModelStore.verify(tmp, expected: nil, name: "t"), "nil expected skips the check")

        XCTAssertThrowsError(try ModelStore.verify(tmp, expected: String(repeating: "0", count: 64), name: "t"),
                             "a wrong hash must throw")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path), "a tampered download must be deleted")
    }

    /// Regression guard: every model must pin an immutable commit SHA and a 64-hex SHA-256.
    func testEveryModelIsIntegrityPinned() {
        for m in Models.all {
            XCTAssertEqual(m.sha256?.count, 64, "\(m.id) must pin a 64-char SHA-256")
            let url = m.downloadURL?.absoluteString ?? m.coremlBaseURL ?? ""
            XCTAssertFalse(url.isEmpty, "\(m.id) must have a download URL")
            XCTAssertFalse(url.contains("/resolve/main/"), "\(m.id) must pin a commit SHA, not a mutable branch")
        }
    }
}
