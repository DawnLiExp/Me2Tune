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
    @StateObject private var collectionManager = CollectionManager()
    @StateObject private var playerViewModel: PlayerViewModel
    @StateObject private var windowStateMonitor = WindowStateMonitor()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        let manager = CollectionManager()
        _collectionManager = StateObject(wrappedValue: manager)
        _playerViewModel = StateObject(wrappedValue: PlayerViewModel(collectionManager: manager))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 495)
                .environmentObject(playerViewModel)
                .environmentObject(collectionManager)
                .environmentObject(windowStateMonitor)
                .onAppear {
                    setupAppDelegate()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
            
            // ✅ 新增：歌词菜单
            CommandGroup(after: .windowArrangement) {
                Button("Lyrics") {
                    LyricsWindowController.shared.show()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
        }
    }

    // MARK: - Setup

    private func setupAppDelegate() {
        guard let window = NSApp.windows.first else { return }
        
        // 传递引用给 AppDelegate
        appDelegate.fullModeWindow = window
        appDelegate.playerViewModel = playerViewModel
        appDelegate.collectionManager = collectionManager
        appDelegate.windowStateMonitor = windowStateMonitor
        
        // ✅ 新增：初始化歌词窗口控制器
        LyricsWindowController.shared.setup(playerViewModel: playerViewModel)
        
        logger.info("🚀 App launched")
    }
    }
