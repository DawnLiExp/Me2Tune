//
//  FailedTrackRegistryTests.swift
//  Me2TuneTests
//
//  Unit tests for failed track registry behavior.
//

import Foundation
import Testing
@testable import Me2Tune

@MainActor
@Suite("FailedTrackRegistry 单元测试")
struct FailedTrackRegistryTests {
    @Test("mark/isMarked/clear")
    func testMarkAndClear() {
        let registry = FailedTrackRegistry()
        let id = UUID()

        #expect(!registry.isMarked(id))
        registry.mark(id)
        #expect(registry.isMarked(id))
        registry.clear(id)
        #expect(!registry.isMarked(id))
    }

    @Test("pruneStale 只保留 live IDs")
    func testPruneStaleKeepsLiveIDs() {
        let registry = FailedTrackRegistry()
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        registry.mark(id1)
        registry.mark(id2)
        registry.mark(id3)

        registry.pruneStale(keeping: [id2])

        #expect(!registry.isMarked(id1))
        #expect(registry.isMarked(id2))
        #expect(!registry.isMarked(id3))
    }

    @Test("pruneStale 空集合清空所有")
    func testPruneStaleEmpty() {
        let registry = FailedTrackRegistry()
        let id = UUID()
        registry.mark(id)

        registry.pruneStale(keeping: [])
        #expect(!registry.isMarked(id))
    }
}
