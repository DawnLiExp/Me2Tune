//
//  Me2TuneApp.swift
//  Me2Tune
//
//  应用入口 - Full 模式主窗口
//

import OSLog
import SwiftUI

private let logger = Logger.app

@main
struct Me2TuneApp: App {
    // ✅ 阶段2：CollectionManager/PlaylistManager 使用 @State (Observation)
    @State private var collectionManager = CollectionManager()
    @StateObject private var playerViewModel: PlayerViewModel
    @StateObject private var windowStateMonitor = WindowStateMonitor()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // ✅ 单一初始化：CollectionManager 先创建
        let manager = CollectionManager()
        _collectionManager = State(wrappedValue: manager)
        _playerViewModel = StateObject(wrappedValue: PlayerViewModel(collectionManager: manager))

        logger.debug("✅ Me2TuneApp initialized - Observation migration stage 2")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 495)
                .environmentObject(playerViewModel) // ✅ PlayerViewModel 仍用 @StateObject (阶段4迁移)
                .environment(\.playbackProgressState, playerViewModel.playbackProgressState)
                .environment(collectionManager) // ✅ 使用 .environment() (Observation)
                .environmentObject(windowStateMonitor) // ✅ 保留 @StateObject
                .onAppear {
                    setupAppDelegate()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultSize(width: 495, height: 800)
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

    private func setupAppDelegate() {
        guard let window = NSApp.windows.first else { return }

        appDelegate.fullModeWindow = window
        appDelegate.playerViewModel = playerViewModel
        appDelegate.collectionManager = collectionManager
        appDelegate.windowStateMonitor = windowStateMonitor

        LyricsWindowController.shared.setup(playerViewModel: playerViewModel)

        logger.info("🚀 App launched (Observation stage 2)")
    }
}
