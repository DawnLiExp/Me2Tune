//
//  AudioPlayerCoreProtocol.swift
//  Me2Tune
//
//  Playback core abstraction for coordinator and unit tests.
//

import AppKit
import Foundation

enum AudioEnqueueResult {
    case enqueued(UUID)
    case occupied(UUID)
    case failed

    var enqueued: Bool {
        if case .enqueued = self { return true }
        return false
    }
}

/// IMPORTANT: All methods must be invoked on @MainActor.
@MainActor
protocol AudioPlayerCoreProtocol: AnyObject {
    var delegate: (any AudioPlayerCoreDelegate)? { get set }
    var isPlaying: Bool { get }
    var canSeek: Bool { get }
    var repeatMode: RepeatMode { get set }

    func loadTrack(_ track: AudioTrack, startingAt time: TimeInterval) async -> Bool
    func enqueueTrack(_ track: AudioTrack) -> AudioEnqueueResult
    func play()
    func pause()
    func seek(to time: TimeInterval)
    func setVolume(_ volume: Double)
    func prepareForTrackSwitch()
    func getCurrentPlaybackTime() -> TimeInterval
    func updateDockIcon(_ artwork: NSImage?)
}

extension AudioPlayerCoreProtocol {
    func loadTrack(_ track: AudioTrack) async -> Bool {
        await loadTrack(track, startingAt: 0)
    }
}
