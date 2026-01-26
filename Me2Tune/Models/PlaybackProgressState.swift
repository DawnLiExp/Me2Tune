//
//  PlaybackProgressState.swift
//  Me2Tune
//
//  播放进度状态 - Observation 框架版本
//

import Foundation
import Observation

@MainActor
@Observable
final class PlaybackProgressState {
    var currentTime: TimeInterval = 0
}
