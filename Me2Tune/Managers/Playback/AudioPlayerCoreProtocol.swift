//
//  AudioPlayerCoreProtocol.swift
//  Me2Tune
//
//  Playback core abstraction for coordinator and unit tests.
//

import AppKit
import Foundation

/// IMPORTANT: All methods must be invoked on @MainActor.
@MainActor
protocol AudioPlayerCoreProtocol: AnyObject {
    var delegate: (any AudioPlayerCoreDelegate)? { get set }
    var isPlaying: Bool { get }
    var repeatMode: RepeatMode { get set }

    func loadTrack(_ track: AudioTrack) async -> Bool
    func enqueueTrack(_ track: AudioTrack) async -> Bool
    func play()
    func pause()
    func seek(to time: TimeInterval)
    func setVolume(_ volume: Double)
    func prepareForTrackSwitch()
    func getCurrentPlaybackTime() -> TimeInterval
    func updateDockIcon(_ artwork: NSImage?)
}
