//
//  ClipmonTests.swift
//  ClipmonTests
//
//  Created by Ved on 02/05/26.
//

import Testing
@testable import Clipmon

struct ClipmonTests {

    @Test func fingerprintIsStableForSameContent() async throws {
        let first = ClipboardEntry.fingerprint(
            kind: .text,
            textContent: "hello world",
            fileName: nil,
            fileURLString: nil,
            payloadData: nil,
            utiIdentifier: nil
        )
        let second = ClipboardEntry.fingerprint(
            kind: .text,
            textContent: "hello world",
            fileName: nil,
            fileURLString: nil,
            payloadData: nil,
            utiIdentifier: nil
        )

        #expect(first == second)
    }

    @Test func previewCollapsesWhitespace() async throws {
        let entry = ClipboardEntry(kind: .text, textContent: "  hello\nworld  ")

        #expect(entry.preview == "hello world")
    }

}
