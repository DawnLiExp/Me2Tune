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
    let onDismissed: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPresented: onPresented, onDismissed: onDismissed)
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
        private let onDismissed: @MainActor () -> Void

        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var visibilityObservation: NSKeyValueObservation?
        private var miniaturizedObservation: NSKeyValueObservation?
        private var stateEvaluationTask: Task<Void, Never>?
        private var isPresentationSessionActive = false

        init(
            onPresented: @escaping @MainActor () -> Void,
            onDismissed: @escaping @MainActor () -> Void
        ) {
            self.onPresented = onPresented
            self.onDismissed = onDismissed
        }

        func attach(to newWindow: NSWindow?) {
            if window !== newWindow {
                detach()
                window = newWindow
                guard let newWindow else { return }
                registerStateObservations(for: newWindow)
                registerObservers(for: newWindow)
            }

            scheduleStateEvaluation()
        }

        func detach() {
            stateEvaluationTask?.cancel()
            stateEvaluationTask = nil
            endPresentationSessionIfNeeded()
            visibilityObservation?.invalidate()
            miniaturizedObservation?.invalidate()
            visibilityObservation = nil
            miniaturizedObservation = nil
            removeObservers()
            window = nil
        }

        private func registerStateObservations(for window: NSWindow) {
            visibilityObservation = window.observe(\.isVisible, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.evaluatePresentationState()
                }
            }

            miniaturizedObservation = window.observe(\.isMiniaturized, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.evaluatePresentationState()
                }
            }
        }

        private func registerObservers(for window: NSWindow) {
            let center = NotificationCenter.default

            observers.append(
                center.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.scheduleStateEvaluation()
                    }
                }
            )

            observers.append(
                center.addObserver(
                    forName: NSWindow.didResignKeyNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.scheduleStateEvaluation()
                    }
                }
            )

            observers.append(
                center.addObserver(
                    forName: NSWindow.didMiniaturizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.endPresentationSessionIfNeeded()
                    }
                }
            )

            observers.append(
                center.addObserver(
                    forName: NSWindow.didDeminiaturizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.scheduleStateEvaluation()
                    }
                }
            )

            observers.append(
                center.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.scheduleStateEvaluation()
                    }
                }
            )

            observers.append(
                center.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.handleWindowClosed()
                    }
                }
            )
        }

        private func removeObservers() {
            let center = NotificationCenter.default
            for observer in observers {
                center.removeObserver(observer)
            }
            observers.removeAll()
        }

        private func handleWindowClosed() {
            detach()
        }

        private func scheduleStateEvaluation() {
            stateEvaluationTask?.cancel()
            stateEvaluationTask = Task { @MainActor [weak self] in
                await Task.yield()
                self?.evaluatePresentationState()
            }
        }

        private func evaluatePresentationState() {
            guard let window else { return }

            if isWindowPresented(window) {
                beginPresentationSessionIfNeeded()
            } else if shouldEndPresentationSession(for: window) {
                endPresentationSessionIfNeeded()
            }
        }

        private func isWindowPresented(_ window: NSWindow) -> Bool {
            guard window.isVisible, !window.isMiniaturized else { return false }
            return window.isKeyWindow || window.occlusionState.contains(.visible)
        }

        private func shouldEndPresentationSession(for window: NSWindow) -> Bool {
            !window.isVisible || window.isMiniaturized
        }

        private func beginPresentationSessionIfNeeded() {
            guard !isPresentationSessionActive else { return }
            isPresentationSessionActive = true
            onPresented()
        }

        private func endPresentationSessionIfNeeded() {
            guard isPresentationSessionActive else { return }
            isPresentationSessionActive = false
            onDismissed()
        }
    }
}
