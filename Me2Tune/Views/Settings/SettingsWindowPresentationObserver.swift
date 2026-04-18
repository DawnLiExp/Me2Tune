//
//  SettingsWindowPresentationObserver.swift
//  Me2Tune
//
//  设置窗口展示观察器 - 仅在窗口新一轮展示时触发一次回调
//

import AppKit
import SwiftUI

struct SettingsWindowPresentationObserver: NSViewRepresentable {
    let onPresented: @MainActor () -> Void
    let onClosed: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPresented: onPresented, onClosed: onClosed)
    }

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.coordinator = context.coordinator
    }
}

extension SettingsWindowPresentationObserver {
    final class ObserverView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.attach(to: window)
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil {
                coordinator?.detach()
            }
            super.viewWillMove(toWindow: newWindow)
        }
    }

    @MainActor
    final class Coordinator {
        private let onPresented: @MainActor () -> Void
        private let onClosed: @MainActor () -> Void

        private weak var window: NSWindow?
        private var closeObserver: NSObjectProtocol?
        private var didNotifyPresentation = false

        init(
            onPresented: @escaping @MainActor () -> Void,
            onClosed: @escaping @MainActor () -> Void
        ) {
            self.onPresented = onPresented
            self.onClosed = onClosed
        }

        func attach(to newWindow: NSWindow?) {
            guard window !== newWindow else { return }

            detach()
            window = newWindow
            guard newWindow != nil else { return }

            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: newWindow,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleWindowClosed()
                }
            }

            Task { @MainActor [weak self] in
                await Task.yield()
                self?.notifyPresentationIfNeeded()
            }
        }

        func detach() {
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }
            closeObserver = nil
            window = nil
            didNotifyPresentation = false
        }

        private func handleWindowClosed() {
            onClosed()
            detach()
        }

        private func notifyPresentationIfNeeded() {
            guard let window, window.isVisible, !didNotifyPresentation else { return }
            didNotifyPresentation = true
            onPresented()
        }
    }
}
