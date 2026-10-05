//
//  MusicSourceManagerTests.swift
//  Me2TuneTests
//
//  Unit tests for MusicSourceManager and AudioFileSupport recursive scanning
//

import Foundation
import Testing
@testable import Me2Tune

@MainActor
struct MusicSourceManagerTests {

    // MARK: - Helper Methods

    private func createTempFolder(name: String = UUID().uuidString) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func cleanupFolder(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Folder Management Tests

    @Test("添加音乐源文件夹与去重")
    func testAddFolderAndDeduplication() throws {
        let folder1 = try createTempFolder(name: "SourceTest1")
        defer { cleanupFolder(folder1) }

        let manager = MusicSourceManager.shared

        // 清理已有状态
        for folder in manager.sourceFolders {
            manager.removeFolder(folder)
        }
        #expect(manager.sourceFolders.isEmpty)

        // 添加文件夹
        manager.addFolder(folder1)
        #expect(manager.sourceFolders.count == 1)

        let addedPath = manager.sourceFolders.first?.standardizedFileURL.path
        let expectedPath = folder1.standardizedFileURL.resolvingSymlinksInPath().path
        #expect(addedPath == expectedPath)

        // 重复添加同一个文件夹不应增加记录
        manager.addFolder(folder1)
        #expect(manager.sourceFolders.count == 1)

        // 清理
        manager.removeFolder(folder1)
        #expect(manager.sourceFolders.isEmpty)
    }

    @Test("删除音乐源记录")
    func testRemoveFolder() throws {
        let folderA = try createTempFolder(name: "SourceA")
        let folderB = try createTempFolder(name: "SourceB")
        defer {
            cleanupFolder(folderA)
            cleanupFolder(folderB)
        }

        let manager = MusicSourceManager.shared

        // 清理已有状态
        for folder in manager.sourceFolders {
            manager.removeFolder(folder)
        }

        manager.addFolder(folderA)
        manager.addFolder(folderB)
        #expect(manager.sourceFolders.count == 2)

        // 删除一条记录
        manager.removeFolder(folderA)
        #expect(manager.sourceFolders.count == 1)
        #expect(manager.sourceFolders.first?.standardizedFileURL.path == folderB.standardizedFileURL.resolvingSymlinksInPath().path)

        manager.removeFolder(folderB)
        #expect(manager.sourceFolders.isEmpty)
    }

    @Test("子路径判断逻辑 isUnderAnySourceFolder")
    func testIsUnderAnySourceFolder() throws {
        let baseFolder = try createTempFolder(name: "MusicBase")
        let otherFolder = try createTempFolder(name: "MusicBaseOther")
        defer {
            cleanupFolder(baseFolder)
            cleanupFolder(otherFolder)
        }

        let manager = MusicSourceManager.shared
        for folder in manager.sourceFolders {
            manager.removeFolder(folder)
        }

        manager.addFolder(baseFolder)

        let childFile = baseFolder.appendingPathComponent("artist/album/song.mp3")
        let nonChildFile = otherFolder.appendingPathComponent("song.mp3")

        #expect(manager.isUnderAnySourceFolder(childFile))
        #expect(!manager.isUnderAnySourceFolder(nonChildFile))

        manager.removeFolder(baseFolder)
    }

    @Test("自动监视开关切换")
    func testAutoWatchToggle() {
        let manager = MusicSourceManager.shared
        let originalState = manager.isAutoWatchEnabled

        manager.setAutoWatchEnabled(true)
        #expect(manager.isAutoWatchEnabled == true)

        manager.setAutoWatchEnabled(false)
        #expect(manager.isAutoWatchEnabled == false)

        manager.setAutoWatchEnabled(originalState)
    }

    // MARK: - Recursive Scanning Tests

    @Test("递归扫描文件夹及所有子文件夹中的音频文件")
    func testRecursiveScanAudioFiles() throws {
        let rootFolder = try createTempFolder(name: "ScanRoot")
        defer { cleanupFolder(rootFolder) }

        // Root level audio file
        let file1 = rootFolder.appendingPathComponent("song1.mp3")
        try "test".write(to: file1, atomically: true, encoding: .utf8)

        // Root level non-audio file (should be ignored)
        let docFile = rootFolder.appendingPathComponent("notes.txt")
        try "text".write(to: docFile, atomically: true, encoding: .utf8)

        // Level 1 subfolder
        let subDir1 = rootFolder.appendingPathComponent("Rock", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir1, withIntermediateDirectories: true)
        let file2 = subDir1.appendingPathComponent("song2.flac")
        try "test".write(to: file2, atomically: true, encoding: .utf8)

        // Level 2 subfolder (deep nested)
        let subDir2 = subDir1.appendingPathComponent("1970s", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir2, withIntermediateDirectories: true)
        let file3 = subDir2.appendingPathComponent("song3.wav")
        try "test".write(to: file3, atomically: true, encoding: .utf8)

        // Hidden audio file (should be ignored)
        let hiddenFile = subDir2.appendingPathComponent("._hidden.mp3")
        try "hidden".write(to: hiddenFile, atomically: true, encoding: .utf8)

        let scannedURLs = AudioFileSupport.scanAudioFiles(in: rootFolder)
        let scannedFileNames = Set(scannedURLs.map(\.lastPathComponent))

        #expect(scannedFileNames.contains("song1.mp3"))
        #expect(scannedFileNames.contains("song2.flac"))
        #expect(scannedFileNames.contains("song3.wav"))
        #expect(!scannedFileNames.contains("notes.txt"))
        #expect(!scannedFileNames.contains("._hidden.mp3"))
        #expect(scannedURLs.count == 3)
    }
}
