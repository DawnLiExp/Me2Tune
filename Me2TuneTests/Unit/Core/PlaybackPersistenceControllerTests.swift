//
//  PlaybackPersistenceControllerTests.swift
//  Me2TuneTests
//
//  Unit tests for playback persistence scheduling behavior.
//

import Foundation
import Testing
@testable import Me2Tune

@MainActor
@Suite("PlaybackPersistenceController 单元测试")
struct PlaybackPersistenceControllerTests {
    @Test("scheduleSave 去抖只执行最后一次")
    func testScheduleSaveDebounce() async {
        var saveCount = 0

        let controller = PlaybackPersistenceController(
            saveDebounce: .milliseconds(40),
            volumeDebounce: .milliseconds(20),
            saveHandler: {
                saveCount += 1
            },
            volumeApplyHandler: { _ in }
        )

        controller.scheduleSave()
        controller.scheduleSave()

        let didSave = await waitUntil {
            saveCount > 0
        }

        #expect(didSave)
        #expect(saveCount == 1)
    }

    @Test("scheduleVolumeApply 去抖只应用最后一次")
    func testVolumeDebounce() async {
        var appliedVolumes: [Double] = []

        let controller = PlaybackPersistenceController(
            saveDebounce: .milliseconds(20),
            volumeDebounce: .milliseconds(40),
            saveHandler: {},
            volumeApplyHandler: { volume in
                appliedVolumes.append(volume)
            }
        )

        controller.scheduleVolumeApply(0.2)
        controller.scheduleVolumeApply(0.6)

        let didApply = await waitUntil {
            !appliedVolumes.isEmpty
        }

        #expect(didApply)
        #expect(appliedVolumes.last == 0.6)
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        interval: Duration = .milliseconds(10),
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let start = ContinuousClock.now
        while ContinuousClock.now - start < timeout {
            if condition() {
                return true
            }
            try? await Task.sleep(for: interval)
        }
        return condition()
    }
}
