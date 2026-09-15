//
//  AudioPlayerEvents.swift
//  Me2Tune
//
//  Transfers delegate events in delivery order without operating on decoders across actors.
//

import Foundation
import SFBAudioEngine

// Retains identity until the event is consumed, preventing object-address reuse after a load.
// The retained object is never exposed or accessed through this wrapper.
nonisolated final class DecoderReference: @unchecked Sendable {
    private let object: AnyObject
    let id: ObjectIdentifier

    init(_ object: AnyObject) {
        self.object = object
        id = ObjectIdentifier(object)
    }
}

nonisolated enum AudioPlayerEvent: Sendable {
    case stateChanged
    case nowPlaying(DecoderReference?, time: TimeInterval)
    case decoded(DecoderReference)
    case rendered(DecoderReference)
    case canceled(DecoderReference)
    case aborted(DecoderReference, Error)
    case sought(DecoderReference, time: TimeInterval)
    case end
    case error(Error)
}

nonisolated final class AudioPlayerEvents: NSObject, AudioPlayer.Delegate {
    let stream: AsyncStream<AudioPlayerEvent>
    private let continuation: AsyncStream<AudioPlayerEvent>.Continuation

    override init() {
        (stream, continuation) = AsyncStream.makeStream()
        super.init()
    }

    deinit { continuation.finish() }

    func audioPlayer(_ audioPlayer: AudioPlayer, playbackStateChanged playbackState: AudioPlayer.PlaybackState) {
        continuation.yield(.stateChanged)
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, nowPlayingChanged nowPlaying: PCMDecoding?) {
        continuation.yield(.nowPlaying(nowPlaying.map { DecoderReference($0) }, time: audioPlayer.currentTime ?? 0))
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, decodingComplete decoder: PCMDecoding) {
        continuation.yield(.decoded(DecoderReference(decoder)))
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, renderingComplete decoder: PCMDecoding) {
        continuation.yield(.rendered(DecoderReference(decoder)))
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, decoderCanceled decoder: PCMDecoding, framesRendered: AVAudioFramePosition) {
        continuation.yield(.canceled(DecoderReference(decoder)))
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, decodingAborted decoder: PCMDecoding,
                     error: Error, framesRendered: AVAudioFramePosition) {
        continuation.yield(.aborted(DecoderReference(decoder), error))
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, didSeek decoder: PCMDecoding, toFrame frame: AVAudioFramePosition) {
        let time = Double(frame) / decoder.processingFormat.sampleRate
        continuation.yield(.sought(DecoderReference(decoder), time: time))
    }

    func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
        continuation.yield(.end)
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: Error) {
        continuation.yield(.error(error))
    }
}
