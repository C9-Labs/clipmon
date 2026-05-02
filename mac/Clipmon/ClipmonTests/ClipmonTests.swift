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

    @Test func sidebarLayoutBreakpointsSwitchBeforeCompression() async throws {
        let regular = SidebarLayout(width: 440)
        let compact = SidebarLayout(width: 380)
        let veryCompact = SidebarLayout(width: 300)

        #expect(regular.isCompact == false)
        #expect(regular.isVeryCompact == false)

        #expect(compact.isCompact == true)
        #expect(compact.isVeryCompact == false)

        #expect(veryCompact.isCompact == true)
        #expect(veryCompact.isVeryCompact == true)
    }

}
