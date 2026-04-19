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

        // 第一次展示：先设置可见状态，再 attach（KVO .initial 会触发）
        window.setTestVisible(true)
        window.testIsKeyWindow = true

        coordinator.attach(to: window)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(recorder.presentedCount == 1)
        #expect(recorder.dismissedCount == 0)

        // 隐藏窗口（KVO 触发 evaluatePresentationState）
        window.setTestVisible(false)
        window.testIsKeyWindow = false
        try? await Task.sleep(for: .milliseconds(50))

        #expect(recorder.presentedCount == 1)
        #expect(recorder.dismissedCount == 1)

        // 再次展示（KVO 触发）
        window.setTestVisible(true)
        window.testIsKeyWindow = true
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
    private var _testIsVisible = false
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
        _testIsVisible
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

    /// KVO-compatible setter — 手动发送 willChange/didChange 以触发 KVO 观察
    func setTestVisible(_ value: Bool) {
        willChangeValue(forKey: "visible")
        _testIsVisible = value
        didChangeValue(forKey: "visible")
    }
}
