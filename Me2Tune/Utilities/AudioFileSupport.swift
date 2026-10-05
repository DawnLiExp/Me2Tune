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

    /// 递归扫描指定目录及其所有子目录中的受支持音频文件
    static func scanAudioFiles(in directoryURL: URL) -> [URL] {
        let fileManager = FileManager.default
        var audioURLs: [URL] = []
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return audioURLs
        }

        while let fileURL = enumerator.nextObject() as? URL {
            if isSupportedAudioFile(fileURL) {
                audioURLs.append(fileURL)
            }
        }
        return audioURLs
    }
}
