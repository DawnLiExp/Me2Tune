//
//  Me2TuneApp.swift
//  Me2Tune
//
//  应用入口 - 支持完整版和 Mini 模式切换
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

    @AppStorage("displayMode") private var displayMode = DisplayMode.full.rawValue

    init() {
        let manager = CollectionManager()
        _collectionManager = StateObject(wrappedValue: manager)
        _playerViewModel = StateObject(wrappedValue: PlayerViewModel(collectionManager: manager))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if displayMode == DisplayMode.mini.rawValue {
                    MiniPlayerView()
                        .environmentObject(playerViewModel)
                } else {
                    ContentView()
                        .frame(minWidth: 495)
                        .environmentObject(playerViewModel)
                        .environmentObject(collectionManager)
                        .environmentObject(windowStateMonitor)
                        .onAppear {
                            setupFullMode()
                        }
                }
            }
            .onAppear {
                if let window = NSApp.windows.first {
                    appDelegate.window = window
                    configureWindowForMode(window: window)
                }
            }
            .onChange(of: displayMode) { _, _ in
                if let window = NSApp.windows.first {
                    configureWindowForMode(window: window)
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(
            displayMode == DisplayMode.mini.rawValue
                ? .contentSize
                : .automatic
        )
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
        }
    }

    // MARK: - Window Configuration

    private func configureWindowForMode(window: NSWindow) {
        if displayMode == DisplayMode.mini.rawValue {
            window.styleMask.remove(.resizable)
            window.isMovableByWindowBackground = true
            window.tabbingMode = .disallowed

            window.center()
            logger.info("🎵 Switched to Mini mode")

        } else {
            window.styleMask.insert(.resizable)

            window.minSize = NSSize(width: 495, height: 400)

            window.setContentSize(NSSize(width: 495, height: 800))
            window.isMovableByWindowBackground = false

            windowStateMonitor.startMonitoring(window: window)

            window.center()
            logger.info("🖥️ Switched to Full mode")
        }
    }

    private func setupFullMode() {
        guard let window = NSApp.windows.first else { return }

        windowStateMonitor.startMonitoring(window: window)

        // 延迟后台加载专辑列表
        Task {
            collectionManager.scheduleDelayedLoad(delay: 1.5)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowDelegate: WindowInterceptor?
    weak var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func configureWindow() {
        guard let window = NSApp.windows.first else { return }

        windowDelegate = WindowInterceptor()
        window.delegate = windowDelegate

        window.tabbingMode = .disallowed

        logger.info("🚀🚀 App launched")
    }
}

// MARK: - Window Interceptor

class WindowInterceptor: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.miniaturize(nil)
        return false
    }
}
