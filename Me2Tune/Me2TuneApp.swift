//
//  Me2TuneApp.swift
//  Me2Tune
//
//  应用入口：Command+W 最小化而非关闭
//

import SwiftUI

@main
struct Me2TuneApp: App {
    @StateObject private var playerManager = AudioPlayerManager()
    @StateObject private var collectionManager = CollectionManager() // 新增
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(playerManager)
                .environmentObject(collectionManager) // 注入
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowDelegate: WindowInterceptor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func configureWindow() {
        guard let window = NSApp.windows.first else { return }

        // 拦截 Command+W
        windowDelegate = WindowInterceptor()
        window.delegate = windowDelegate

        // 固定宽度 350，高度可调
        window.minSize = NSSize(width: 350, height: 600)
        window.maxSize = NSSize(width: 350, height: CGFloat.greatestFiniteMagnitude)

        // 设置初始大小并居中
        window.setContentSize(NSSize(width: 350, height: 700))
        window.center()
    }
}

// MARK: - Window Interceptor

class WindowInterceptor: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 拦截 Command+W，改为最小化
        sender.miniaturize(nil)
        return false
    }
}
