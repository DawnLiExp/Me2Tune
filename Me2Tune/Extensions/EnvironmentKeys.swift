//
//  EnvironmentKeys.swift
//  Me2Tune
//
//  自定义 Environment 键 - 用于 Observation 框架
//

import SwiftUI

// MARK: - PlaybackProgressState

private struct PlaybackProgressStateKey: EnvironmentKey {
    static let defaultValue = PlaybackProgressState()
}

extension EnvironmentValues {
    var playbackProgressState: PlaybackProgressState {
        get { self[PlaybackProgressStateKey.self] }
        set { self[PlaybackProgressStateKey.self] = newValue }
    }
}
