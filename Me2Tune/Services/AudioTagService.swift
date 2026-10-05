//
//  AudioTagService.swift
//  Me2Tune
//
//  音频文件详细 Tag 元数据读取与物理写回服务 - 基于 SFBAudioEngine (TagLib)
//

import AppKit
import Foundation
import OSLog
import SFBAudioEngine

extension Notification.Name {
    static let audioTrackMetadataDidUpdate = Notification.Name("audioTrackMetadataDidUpdate")
}

actor AudioTagService {
    static let shared = AudioTagService()

    private let logger = Logger(subsystem: "com.me2tune.app", category: "AudioTagService")

    private init() {}

    // MARK: - Read Metadata

    func readDetailedMetadata(from url: URL) async throws -> DetailedAudioMetadata {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let fileAttrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (fileAttrs?[.size] as? NSNumber)?.int64Value ?? 0

        let audioFile: AudioFile
        do {
            audioFile = try AudioFile(readingPropertiesAndMetadataFrom: url)
        } catch {
            logger.error("Failed to read audio file metadata from \(url.lastPathComponent): \(error.localizedDescription)")
            throw error
        }

        let props = audioFile.properties
        let metadata = audioFile.metadata

        // 音频属性
        let formatName = props.formatName ?? url.pathExtension.uppercased()
        let duration = props.duration ?? 0
        let sampleRate = props.sampleRate
        let channels = props.channelCount.map { Int($0) }
        let bitDepth = props.bitDepth
        let bitrate = props.bitrate.map { Int($0) }

        // 标签字段
        let title = metadata.title ?? ""
        let artist = metadata.artist ?? ""
        let album = metadata.albumTitle ?? ""
        let albumArtist = metadata.albumArtist ?? ""
        let composer = metadata.composer ?? ""
        let genre = metadata.genre ?? ""
        let year = metadata.releaseDate ?? ""
        let trackNumber = metadata.trackNumber
        let trackTotal = metadata.trackTotal
        let discNumber = metadata.discNumber
        let discTotal = metadata.discTotal
        let bpm = metadata.bpm
        let comment = metadata.comment ?? ""
        let compilation = metadata.isCompilation ?? false
        let lyrics = metadata.lyrics ?? ""

        // 封面图片
        var artworkData: Data?
        var artworkMIMEType: String?
        var artworkDimensions: CGSize?

        if let firstPicture = metadata.attachedPictures.first {
            artworkData = firstPicture.imageData
            if let data = artworkData, let image = NSImage(data: data) {
                artworkDimensions = image.size
                if data.prefix(3) == Data([0xFF, 0xD8, 0xFF]) {
                    artworkMIMEType = "image/jpeg"
                } else if data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
                    artworkMIMEType = "image/png"
                }
            }
        }

        return DetailedAudioMetadata(
            fileURL: url,
            fileSize: fileSize,
            fileFormatName: formatName,
            duration: duration,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            channels: channels,
            bitrate: bitrate,
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            composer: composer,
            genre: genre,
            year: year,
            trackNumber: trackNumber,
            trackTotal: trackTotal,
            discNumber: discNumber,
            discTotal: discTotal,
            bpm: bpm,
            comment: comment,
            compilation: compilation,
            lyrics: lyrics,
            artworkData: artworkData,
            artworkMIMEType: artworkMIMEType,
            artworkDimensions: artworkDimensions,
            isArtworkModified: false
        )
    }

    // MARK: - Write Metadata

    func writeMetadata(_ updatedMetadata: DetailedAudioMetadata, to url: URL) async throws {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard FileManager.default.isWritableFile(atPath: url.path) else {
            logger.error("File is not writable at path: \(url.path)")
            throw CocoaError(.fileWriteNoPermission)
        }

        let audioFile: AudioFile
        do {
            audioFile = try AudioFile(readingPropertiesAndMetadataFrom: url)
        } catch {
            logger.error("Failed to open audio file for writing: \(url.lastPathComponent), error: \(error.localizedDescription)")
            throw error
        }

        let meta = audioFile.metadata

        // 回填文本标签
        meta.title = cleanString(updatedMetadata.title)
        meta.artist = cleanString(updatedMetadata.artist)
        meta.albumTitle = cleanString(updatedMetadata.album)
        meta.albumArtist = cleanString(updatedMetadata.albumArtist)
        meta.composer = cleanString(updatedMetadata.composer)
        meta.genre = cleanString(updatedMetadata.genre)
        meta.releaseDate = cleanString(updatedMetadata.year)
        meta.comment = cleanString(updatedMetadata.comment)
        meta.lyrics = cleanString(updatedMetadata.lyrics)

        meta.trackNumber = updatedMetadata.trackNumber
        meta.trackTotal = updatedMetadata.trackTotal
        meta.discNumber = updatedMetadata.discNumber
        meta.discTotal = updatedMetadata.discTotal
        meta.bpm = updatedMetadata.bpm
        meta.isCompilation = updatedMetadata.compilation ? true : nil

        // 处理封面修改
        if updatedMetadata.isArtworkModified {
            meta.removeAllAttachedPictures()
            if let data = updatedMetadata.artworkData, !data.isEmpty {
                let picture = AttachedPicture(imageData: data, type: .frontCover)
                meta.attachPicture(picture)
            }
        }

        // 物理写回
        do {
            try audioFile.writeMetadata()
            logger.info("Successfully wrote metadata to: \(url.lastPathComponent)")
        } catch {
            logger.error("Failed to writeMetadata: \(error.localizedDescription)")
            throw error
        }

        // 刷新缓存并分发通知
        await FileMetadataReader.shared.invalidate(url: url)
        await ArtworkCacheService.shared.invalidateArtwork(for: url)

        await MainActor.run {
            NotificationCenter.default.post(
                name: .audioTrackMetadataDidUpdate,
                object: nil,
                userInfo: [
                    "url": url,
                    "metadata": updatedMetadata
                ]
            )
        }
    }

    private func cleanString(_ str: String) -> String? {
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
