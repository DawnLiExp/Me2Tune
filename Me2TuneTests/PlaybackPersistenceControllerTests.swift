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
        var savedVolumes: [Double?] = []

        let controller = PlaybackPersistenceController(
            saveDebounce: .milliseconds(40),
            volumeDebounce: .milliseconds(20),
            periodicInterval: .milliseconds(50),
            saveHandler: { volume in
                savedVolumes.append(volume)
            },
            volumeApplyHandler: { _ in }
        )

        controller.scheduleSave(volume: 0.1)
        controller.scheduleSave(volume: 0.9)

        let didSave = await waitUntil {
            !savedVolumes.isEmpty
        }

        #expect(didSave)
        #expect(savedVolumes.last == 0.9)
    }

    @Test("scheduleVolumeApply 去抖只应用最后一次")
    func testVolumeDebounce() async {
        var appliedVolumes: [Double] = []

        let controller = PlaybackPersistenceController(
            saveDebounce: .milliseconds(20),
            volumeDebounce: .milliseconds(40),
            periodicInterval: .milliseconds(50),
            saveHandler: { _ in },
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

    @Test("start/stopPeriodicSave 按周期执行并可停止")
    func testPeriodicStartStop() async {
        var savedVolumes: [Double?] = []
        var volume = 0.3

        let controller = PlaybackPersistenceController(
            saveDebounce: .milliseconds(20),
            volumeDebounce: .milliseconds(20),
            periodicInterval: .milliseconds(50),
            saveHandler: { current in
                savedVolumes.append(current)
            },
            volumeApplyHandler: { _ in }
        )

        controller.startPeriodicSave { volume }
        let hasPeriodicTick = await waitUntil {
            !savedVolumes.isEmpty
        }
        #expect(hasPeriodicTick)

        volume = 0.7
        let receivedNewVolume = await waitUntil {
            savedVolumes.last == 0.7
        }
        #expect(receivedNewVolume)
        #expect(savedVolumes.last == 0.7)

        controller.stopPeriodicSave()
        let countAfterStop = savedVolumes.count
        try? await Task.sleep(for: .milliseconds(150))
        #expect(savedVolumes.count <= countAfterStop + 1)
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
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
