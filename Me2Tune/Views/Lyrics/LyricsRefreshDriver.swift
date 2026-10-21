import Foundation

@MainActor
final class LyricsRefreshDriver {
    private var timer: Timer?
    private var refresh: (@MainActor () -> Void)?

    var isRunning: Bool { timer != nil }

    func update(isVisible: Bool, refresh: @escaping @MainActor () -> Void) {
        stop()
        guard isVisible else { return }
        self.refresh = refresh
        refresh()
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh?() }
        }
        timer.tolerance = 0.06
        self.timer = timer
        RunLoop.main.add(timer, forMode: .default)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        refresh = nil
    }
}
