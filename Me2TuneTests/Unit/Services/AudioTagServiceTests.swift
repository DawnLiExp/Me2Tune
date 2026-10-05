//
//  AudioTagServiceTests.swift
//  Me2TuneTests
//
//  AudioTagService 单元测试 - 标签读取与物理写回验证
//

import AVFoundation
import AppKit
import Foundation
import SFBAudioEngine
import Testing
@testable import Me2Tune

@MainActor
@Suite("AudioTagService 单元测试")
struct AudioTagServiceTests {
    private func createTestWavFile(seconds: Double = 1.0) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        let frames = AVAudioFrameCount(seconds * 44100)
        let output = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<2 {
            buffer.floatChannelData?[channel].initialize(repeating: 0, count: Int(frames))
        }
        try output.write(from: buffer)
        return url
    }

    @Test("读取音频文件的基本属性和初始元数据")
    func readDetailedMetadataFromWav() async throws {
        let url = try createTestWavFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let metadata = try await AudioTagService.shared.readDetailedMetadata(from: url)

        #expect(metadata.fileURL == url)
        #expect(metadata.fileSize > 0)
        #expect(metadata.channels == 2)
        #expect(metadata.sampleRate == 44100)
        #expect(metadata.duration > 0.9)
    }

    @Test("修改文本标签并写回文件，重新读取验证持久化")
    func writeAndReadbackMetadata() async throws {
        let url = try createTestWavFile()
        defer { try? FileManager.default.removeItem(at: url) }

        var meta = try await AudioTagService.shared.readDetailedMetadata(from: url)
        meta.title = "Test Title"
        meta.artist = "Test Artist"
        meta.album = "Test Album"
        meta.albumArtist = "Test Album Artist"
        meta.composer = "Test Composer"
        meta.genre = "Classical"
        meta.year = "2026"
        meta.trackNumber = 3
        meta.trackTotal = 12
        meta.discNumber = 1
        meta.discTotal = 2
        meta.bpm = 128
        meta.comment = "Unit test comment"
        meta.lyrics = "[00:01.00]Hello World"

        try await AudioTagService.shared.writeMetadata(meta, to: url)

        // 重新读取验证
        let reloaded = try await AudioTagService.shared.readDetailedMetadata(from: url)
        #expect(reloaded.title == "Test Title")
        #expect(reloaded.artist == "Test Artist")
        #expect(reloaded.album == "Test Album")
        #expect(reloaded.albumArtist == "Test Album Artist")
        #expect(reloaded.composer == "Test Composer")
        #expect(reloaded.genre == "Classical")
        #expect(reloaded.year == "2026")
        #expect(reloaded.trackNumber == 3)
        #expect(reloaded.trackTotal == 12)
        #expect(reloaded.discNumber == 1)
        #expect(reloaded.discTotal == 2)
        #expect(reloaded.bpm == 128)
        #expect(reloaded.comment == "Unit test comment")
        #expect(reloaded.lyrics == "[00:01.00]Hello World")
    }

    @Test("修改封面插图并验证写回与清除")
    func writeAndRemoveArtwork() async throws {
        let url = try createTestWavFile()
        defer { try? FileManager.default.removeItem(at: url) }

        // 生成测试用的 10x10 PNG 图像数据
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 10, height: 10))
        image.unlockFocus()
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            Issue.record("Failed to generate test PNG data")
            return
        }

        var meta = try await AudioTagService.shared.readDetailedMetadata(from: url)
        meta.artworkData = pngData
        meta.isArtworkModified = true

        try await AudioTagService.shared.writeMetadata(meta, to: url)

        let reloadedWithCover = try await AudioTagService.shared.readDetailedMetadata(from: url)
        #expect(reloadedWithCover.artworkData != nil)
        #expect(reloadedWithCover.artworkDimensions?.width == 10)

        // 移除封面
        var metaToRemove = reloadedWithCover
        metaToRemove.artworkData = nil
        metaToRemove.isArtworkModified = true

        try await AudioTagService.shared.writeMetadata(metaToRemove, to: url)

        let reloadedWithoutCover = try await AudioTagService.shared.readDetailedMetadata(from: url)
        #expect(reloadedWithoutCover.artworkData == nil)
    }

    @Test("不存在的文件读取时抛出错误")
    func nonExistentFileThrowsError() async {
        let fakeURL = URL(fileURLWithPath: "/tmp/non_existent_\(UUID().uuidString).mp3")
        await #expect(throws: Error.self) {
            _ = try await AudioTagService.shared.readDetailedMetadata(from: fakeURL)
        }
    }
}
