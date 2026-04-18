//
//  SettingsWindowPresentationObserverTests.swift
//  Me2TuneTests
//
//  Unit tests for settings presentation session detection.
//

import AppKit
import Testing
@testable import Me2Tune

@MainActor
@Suite("SettingsWindowPresentationObserver 单元测试")
struct SettingsWindowPresentationObserverTests {
    @Test("同一窗口再次展示时会重新触发 presented")
    func reopeningSameWindowTriggersPresentedAgain() async {
        let recorder = PresentationRecorder()
        let coordinator = SettingsWindowPresentationObserver.Coordinator(
            onPresented: {
                recorder.presentedCount += 1
            },
            onDismissed: {
                recorder.dismissedCount += 1
            }
        )

        let window = TestSettingsWindow()
        window.testIsVisible = true
        window.testIsKeyWindow = true

        coordinator.attach(to: window)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(recorder.presentedCount == 1)
        #expect(recorder.dismissedCount == 0)

        window.testIsVisible = false
        window.testIsKeyWindow = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(recorder.presentedCount == 1)
        #expect(recorder.dismissedCount == 1)

        window.testIsVisible = true
        window.testIsKeyWindow = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(recorder.presentedCount == 2)
        #expect(recorder.dismissedCount == 1)
    }
}

@MainActor
private final class PresentationRecorder {
    var presentedCount = 0
    var dismissedCount = 0
}

private final class TestSettingsWindow: NSWindow {
    var testIsVisible = false
    var testIsMiniaturized = false
    var testIsKeyWindow = false
    var testOcclusionState: NSWindow.OcclusionState = []

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
    }

    override var isVisible: Bool {
        testIsVisible
    }

    override var isMiniaturized: Bool {
        testIsMiniaturized
    }

    override var isKeyWindow: Bool {
        testIsKeyWindow
    }

    override var occlusionState: NSWindow.OcclusionState {
        testOcclusionState
    }
}
