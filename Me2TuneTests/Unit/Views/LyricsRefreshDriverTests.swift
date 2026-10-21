import Testing
@testable import Me2Tune

@MainActor
@Suite("歌词可见期间刷新")
struct LyricsRefreshDriverTests {
    @Test("隐藏时不刷新，异步加载结束仍不启动，恢复立即校准")
    func visibilityAndLateLoad() {
        let state = LyricsWindowState()
        var ticks = 0
        state.refreshDriver.update(isVisible: state.isVisible) { ticks += 1 }
        #expect(ticks == 0)
        #expect(!state.refreshDriver.isRunning)
        state.isVisible = true
        state.refreshDriver.update(isVisible: state.isVisible) { ticks += 1 }
        #expect(ticks == 1)
        #expect(state.refreshDriver.isRunning)
        state.isVisible = false
        #expect(!state.refreshDriver.isRunning)
        // The load completion calls the same entry point as LyricsView.
        state.refreshDriver.update(isVisible: state.isVisible) { ticks += 1 }
        #expect(ticks == 1)
        #expect(!state.refreshDriver.isRunning)
        state.isVisible = true
        state.refreshDriver.update(isVisible: state.isVisible) { ticks += 1 }
        #expect(ticks == 2)
        state.refreshDriver.stop()
        #expect(!state.refreshDriver.isRunning)
    }

    @Test("停止后释放刷新回调捕获的对象")
    func stopReleasesCallback() {
        final class Marker {}
        let driver = LyricsRefreshDriver()
        weak var released: Marker?
        do {
            let marker = Marker()
            released = marker
            driver.update(isVisible: true) { _ = marker }
        }
        #expect(released != nil)
        driver.stop()
        #expect(released == nil)
    }
}
