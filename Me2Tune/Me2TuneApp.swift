//
//  Me2TuneApp.swift
//  Me2Tune
//
//  应用入口 - 使用 ViewModel 架构
//

import OSLog
import SwiftUI

private let logger = Logger.app

@main
struct Me2TuneApp: App {
    @StateObject private var collectionManager = CollectionManager()
    @StateObject private var playerViewModel: PlayerViewModel
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        let manager = CollectionManager()
        _collectionManager = StateObject(wrappedValue: manager)
        _playerViewModel = StateObject(wrappedValue: PlayerViewModel(collectionManager: manager))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(playerViewModel)
                .environmentObject(collectionManager)
                .onAppear {
                    appDelegate.window = NSApp.windows.first
                    
                    // 延迟 2.5 秒后台加载专辑列表
                    Task {
                        collectionManager.scheduleDelayedLoad(delay: 2.5)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
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

        window.minSize = NSSize(width: 495, height: 800)
        window.maxSize = NSSize(width: 495, height: CGFloat.greatestFiniteMagnitude)
        window.isMovableByWindowBackground = false

        logger.info("🚀 App launched")
    }
}

// MARK: - Window Interceptor

class WindowInterceptor: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.miniaturize(nil)
        return false
    }
}
