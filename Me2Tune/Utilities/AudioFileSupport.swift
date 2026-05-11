//
//  AudioFileSupport.swift
//  Me2Tune
//
//  Supported audio file format gate shared by import, drag-and-drop, and file-open flows.
//

import Foundation

enum AudioFileSupport {
    static let supportedExtensions: Set<String> = [
        "mp3",
        "m4a",
        "aac",
        "wav",
        "aiff",
        "aif",
        "flac",
        "ape",
        "wv",
        "tta",
        "mpc",
        "ogg",
    ]

    static func isSupportedAudioFile(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
