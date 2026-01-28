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
    // ✅ 使用 @State (Observation)
    @State private var collectionManager: CollectionManager
    @State private var playerViewModel: PlayerViewModel
    @StateObject private var windowStateMonitor = WindowStateMonitor()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        logger.debug("🚀 Me2TuneApp.init() START") 
        // ✅ 单一初始化路径：先创建 CollectionManager，再创建 PlayerViewModel
        let manager = CollectionManager()
        _collectionManager = State(wrappedValue: manager)

        let viewModel = PlayerViewModel(collectionManager: manager)
        _playerViewModel = State(wrappedValue: viewModel)

        logger.debug("✅ Me2TuneApp initialized - PlayerViewModel migrated to @Observable")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 495)
                .environment(playerViewModel) // ✅ 使用 .environment() (Observation)
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

        logger.info("🚀 App launched - @Observable migration complete")
    }
}
