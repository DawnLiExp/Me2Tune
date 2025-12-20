//
//  Me2TuneApp.swift
//  Me2Tune
//
//  应用入口：Command+W 最小化而非关闭，动态窗口高度，UI状态预加载
//

import Combine
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "me2.Me2Tune", category: "Me2TuneApp")

@main
struct Me2TuneApp: App {
    @StateObject private var playerManager = AudioPlayerManager()
    @StateObject private var collectionManager = CollectionManager()
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            if appState.isUIStateLoaded {
                ContentView(initialUIState: appState.uiState)
                    .environmentObject(playerManager)
                    .environmentObject(collectionManager)
                    .onAppear {
                        appDelegate.window = NSApp.windows.first
                        appDelegate.updateWindowSize(for: appState.uiState)
                    }
            } else {
                ProgressView()
                    .frame(width: 350, height: 200)
                    .onAppear {
                        Task {
                            await appState.loadUIState()
                        }
                    }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    @Published var uiState: UIState = .default
    @Published var isUIStateLoaded = false

    private let persistenceService = PersistenceService()

    func loadUIState() async {
        do {
            let loadedState = try await persistenceService.loadUIState()
            uiState = loadedState
            logger.info("UI state loaded: artwork=\(loadedState.isArtworkExpanded), playlist=\(loadedState.isPlaylistVisible), height=\(loadedState.windowHeight), pos=(\(loadedState.windowX ?? 0), \(loadedState.windowY ?? 0))")
        } catch {
            logger.notice("No existing UI state, using defaults")
            uiState = .default
        }
        isUIStateLoaded = true
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

        window.minSize = NSSize(width: 350, height: 150)
        window.maxSize = NSSize(width: 350, height: 2000)
    }

    func updateWindowSize(for uiState: UIState) {
        guard let window = NSApp.windows.first else { return }

        // 使用保存的高度，但确保不小于最小高度
        var height = uiState.windowHeight

        let minHeight: CGFloat = {
            var h: CGFloat = 0
            h += uiState.isArtworkExpanded ? 350 : 64
            h += 1 // Divider
            h += 112 // Player controls

            if uiState.isPlaylistVisible {
                h += 1 // Divider
                h += 300 // Playlist min height
            }
            return h
        }()

        height = max(height, minHeight)

        // 恢复窗口位置和大小
        if let x = uiState.windowX, let y = uiState.windowY {
            // 使用保存的位置
            let frame = NSRect(x: x, y: y, width: 350, height: height)
            window.setFrame(frame, display: true)
            logger.debug("Window restored to position: (\(x), \(y)), height: \(height)")
        } else {
            // 首次启动，居中显示
            window.setContentSize(NSSize(width: 350, height: height))
            window.center()
            logger.debug("Window centered with height: \(height)")
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
