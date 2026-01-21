//
//  PlaybackProgressState.swift
//  Me2Tune
//
//  播放进度状态 - 独立的 ObservableObject 避免触发全局刷新
//

import Foundation
import Combine

@MainActor
final class PlaybackProgressState: ObservableObject {
    @Published var currentTime: TimeInterval = 0
}
