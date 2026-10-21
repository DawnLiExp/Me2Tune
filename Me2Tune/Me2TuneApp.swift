//
//  Me2TuneApp.swift
//  Me2Tune
//
//  应用入口 - Full 模式主窗口 + 文件打开协调
//

import OSLog
import SwiftData
import SwiftUI

private let logger = Logger.app

@main
struct Me2TuneApp: App {
    @State private var isMigrationFailed: Bool
    @State private var collectionManager: CollectionManager
    @State private var playerViewModel: PlayerViewModel
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        logger.debug("🚀 Me2TuneApp.init() START")

        _isMigrationFailed = State(wrappedValue: DataService.shared.isMigrationFailed)

        // ✅ 单一初始化路径：CollectionManager -> PlaybackCoordinator -> PlayerViewModel
        let manager = CollectionManager()
        _collectionManager = State(wrappedValue: manager)

        let coordinator = PlaybackCoordinator(collectionManager: manager)
        let viewModel = PlayerViewModel(coordinator: coordinator)
        _playerViewModel = State(wrappedValue: viewModel)

        logger.debug("✅ Me2TuneApp initialized - @Observable architecture")
    }

    var body: some Scene {
        Window("Me2Tune", id: "main") {
            ContentView(isMigrationFailed: isMigrationFailed)
                .frame(minWidth: 495)
                .environment(playerViewModel)
                .environment(\.playbackProgressState, playerViewModel.playbackProgressState)
                .environment(collectionManager)
                .background(MainWindowReader(onResolve: setupAppDelegate))
                // ✅ 双保险：捕获 SwiftUI 层级的 URL 打开事件
                // (AirDrop、Handoff、拖拽到 Dock 图标等场景可能走这里)
                .onOpenURL { url in
                    logger.debug("🔗 SwiftUI onOpenURL triggered: \(url.lastPathComponent)")
                    // 转发给 AppDelegate 统一处理
                    appDelegate.application(NSApp, open: [url])
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultSize(width: 495, height: 800)
        .defaultPosition(.center)
        .modelContainer(DataService.shared.modelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .windowArrangement) {
                Button(String(localized: "lyrics_menu_item")) {
                    LyricsWindowController.shared.show()
                }
                .keyboardShortcut("l", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }

    // MARK: - Setup

    /// ✅ 优化：更清晰的初始化顺序和日志
    private func setupAppDelegate(window: NSWindow) {
        guard appDelegate.fullModeWindow !== window else { return }

        // 设置窗口标识符，用于后续查找
        window.identifier = NSUserInterfaceItemIdentifier("main")

        // ✅ 按依赖顺序设置 AppDelegate 属性
        appDelegate.registerFullModeWindow(window)
        appDelegate.playerViewModel = playerViewModel
        appDelegate.collectionManager = collectionManager

        // ✅ 创建并启动 WindowStateMonitor
        let monitor = WindowStateMonitor()
        appDelegate.windowStateMonitor = monitor
        monitor.startMonitoring(window: window)

        playerViewModel.injectWindowStateMonitor(monitor)

        // ✅ 设置歌词窗口控制器
        LyricsWindowController.shared.setup(playerViewModel: playerViewModel, dockingCoordinator: appDelegate.dockingCoordinator)

        logger.info("🚀 App initialization complete - @Observable architecture active")
    }
}

private struct MainWindowReader: NSViewRepresentable {
    let onResolve: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {
        nsView.onResolve = onResolve
    }

    final class ReaderView: NSView {
        var onResolve: (@MainActor (NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            Task { @MainActor [weak self, weak window] in
                await Task.yield()
                guard let self, let window, self.window === window else { return }
                self.onResolve?(window)
            }
        }
    }
}
