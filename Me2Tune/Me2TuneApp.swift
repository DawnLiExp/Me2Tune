//
//  Me2TuneApp.swift
//  Me2Tune
//
//  应用入口
//

import SwiftUI
import OSLog

private let logger = Logger(subsystem: "me2.Me2Tune", category: "Me2TuneApp")

@main
struct Me2TuneApp: App {
    @StateObject private var playerManager = AudioPlayerManager()
    @StateObject private var collectionManager = CollectionManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(playerManager)
                .environmentObject(collectionManager)
                .onAppear {
                    appDelegate.window = NSApp.windows.first
                }
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

        window.minSize = NSSize(width: 495, height: 775)
        window.isMovableByWindowBackground = true
        
        logger.debug("Window configured")
    }
}

// MARK: - Window Interceptor

class WindowInterceptor: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.miniaturize(nil)
        return false
    }
}
