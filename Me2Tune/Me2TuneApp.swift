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
            .onChange(of: displayMode) { _, newMode in
                if let window = NSApp.windows.first {
                    if newMode == DisplayMode.mini.rawValue {
                        // 切换到 Mini 模式
                        configureWindowForMode(window: window)
                    } else {
                        // 从 Mini 切回 Full：重启应用以恢复干净状态
                        AppDelegate.restartApplication()
                    }
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
            // ===== Mini 模式：完全隐藏 titlebar =====
            window.styleMask.remove(.titled)
            window.styleMask.remove(.resizable)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.tabbingMode = .disallowed

            // 圆角效果
            window.isOpaque = false
            window.backgroundColor = .clear

            if let contentView = window.contentView {
                contentView.wantsLayer = true
                contentView.layer?.cornerRadius = 13
                contentView.layer?.masksToBounds = true
            }

            window.center()
            logger.info("🎵 Switched to Mini mode")
        }
        // Full 模式由 .windowStyle(.hiddenTitleBar) 和应用重启管理，无需配置
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
    private nonisolated(unsafe) var commandWMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureWindow()
        setupCommandWHandler()
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

    // MARK: - Command+W Handler

    private func setupCommandWHandler() {
        commandWMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 拦截 Command+W
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w" {
                if let window = NSApp.windows.first {
                    window.miniaturize(nil)
                    logger.debug("⌘+W → Minimize")
                }
                return nil
            }
            return event
        }
    }

    // MARK: - Application Restart

    static func restartApplication() {
        logger.info("🔄 Restarting application for mode switch")

        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 0.2; open '\(Bundle.main.bundlePath)'"]
        task.launch()

        NSApp.terminate(nil)
    }

    deinit {
        if let monitor = commandWMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - Window Interceptor

class WindowInterceptor: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.miniaturize(nil)
        return false
    }
}
