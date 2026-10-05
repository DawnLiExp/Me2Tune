//
//  MusicSourceManager.swift
//  Me2Tune
//
//  音乐源管理 - 文件夹路径列表维护、递归扫描、FSEvents 实时监控与更新
//

import AppKit
import CoreServices
import Foundation
import Observation
import OSLog

private let logger = Logger.viewModel

@MainActor
@Observable
final class MusicSourceManager {
    static let shared = MusicSourceManager()

    // MARK: - Constants / Keys

    private enum Key {
        static let sourceFolderPaths = "musicSourceFolderPaths"
        static let autoWatchEnabled = "autoWatchMusicSources"
    }

    // MARK: - Properties

    private(set) var sourceFolders: [URL] = []
    var isAutoWatchEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutoWatchEnabled, forKey: Key.autoWatchEnabled)
            handleAutoWatchToggled()
        }
    }

    private(set) var isScanning: Bool = false
    private(set) var statusMessage: String?

    // MARK: - Dependencies

    weak var playerViewModel: PlayerViewModel?

    // MARK: - File Monitoring

    @ObservationIgnored
    private let monitor = FolderMonitor()
    @ObservationIgnored
    private var debounceTask: Task<Void, Never>?
    @ObservationIgnored
    private var pendingChangedPaths: Set<String> = []

    // MARK: - Init

    private init() {
        self.isAutoWatchEnabled = UserDefaults.standard.bool(forKey: Key.autoWatchEnabled)
        loadSavedFolders()
        logger.debug("✅ MusicSourceManager initialized with \(self.sourceFolders.count) sources")
    }

    // MARK: - Configuration

    func configure(playerViewModel: PlayerViewModel) {
        self.playerViewModel = playerViewModel
        logger.debug("MusicSourceManager configured with PlayerViewModel")

        if isAutoWatchEnabled && !sourceFolders.isEmpty {
            startMonitoring()
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await self.reconcileAllSources()
            }
        }
    }

    // MARK: - Folder Management

    func addFolder(_ url: URL) {
        let standardized = url.standardizedFileURL.resolvingSymlinksInPath()

        // 避免重复添加
        guard !sourceFolders.contains(where: { $0.standardizedFileURL.resolvingSymlinksInPath() == standardized }) else {
            logger.notice("Folder already in music sources: \(standardized.path)")
            return
        }

        sourceFolders.append(standardized)
        saveFolders()
        logger.info("📁 Added music source folder: \(standardized.path)")

        // 递归扫描该文件夹并添加到播放列表
        scanAndAddFolder(standardized)

        // 若启用了自动监视，重新启动监控以覆盖新目录
        if isAutoWatchEnabled {
            restartMonitoring()
        }
    }

    func removeFolder(_ url: URL) {
        let standardized = url.standardizedFileURL.resolvingSymlinksInPath()
        sourceFolders.removeAll(where: { $0.standardizedFileURL.resolvingSymlinksInPath() == standardized })
        saveFolders()
        logger.info("🗑️ Removed music source folder: \(standardized.path)")

        if isAutoWatchEnabled {
            if sourceFolders.isEmpty {
                stopMonitoring()
            } else {
                restartMonitoring()
            }
        }
    }

    func setAutoWatchEnabled(_ enabled: Bool) {
        isAutoWatchEnabled = enabled
    }

    // MARK: - Scanning

    func scanAndAddFolder(_ folderURL: URL) {
        guard let playerViewModel else {
            logger.warning("PlayerViewModel not configured, skipping scan")
            return
        }

        isScanning = true
        statusMessage = String(localized: "scanning_music_source")

        Task { @MainActor [weak self] in
            guard let self else { return }
            let audioURLs = AudioFileSupport.scanAudioFiles(in: folderURL)
            logger.info("🔍 Scanned \(audioURLs.count) audio files in \(folderURL.path)")

            if !audioURLs.isEmpty {
                await playerViewModel.addTracksToPlaylist(urls: audioURLs)
            }

            self.isScanning = false
            self.statusMessage = nil
        }
    }

    // MARK: - Auto-Watch Handlers

    private func handleAutoWatchToggled() {
        if isAutoWatchEnabled {
            logger.info("👀 Auto-watch enabled for music sources")
            startMonitoring()
            Task { @MainActor [weak self] in
                await self?.reconcileAllSources()
            }
        } else {
            logger.info("🛑 Auto-watch disabled for music sources")
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        guard !sourceFolders.isEmpty else { return }
        let paths = sourceFolders.map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
        logger.debug("Starting folder monitor for \(paths.count) path(s)")

        monitor.start(paths: paths) { [weak self] changedPaths in
            Task { @MainActor [weak self] in
                self?.handleFileEvents(changedPaths)
            }
        }
    }

    private func stopMonitoring() {
        monitor.stop()
        debounceTask?.cancel()
        debounceTask = nil
        pendingChangedPaths.removeAll()
    }

    private func restartMonitoring() {
        stopMonitoring()
        startMonitoring()
    }

    private func handleFileEvents(_ paths: [String]) {
        pendingChangedPaths.formUnion(paths)

        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s 防抖
            guard !Task.isCancelled, let self else { return }
            let pathsToProcess = self.pendingChangedPaths
            self.pendingChangedPaths.removeAll()
            await self.processChangedPaths(pathsToProcess)
        }
    }

    // MARK: - Reconciliation

    /// 处理 FSEvents 上报的变更路径
    private func processChangedPaths(_ paths: Set<String>) async {
        guard let playerViewModel, !sourceFolders.isEmpty else { return }

        logger.debug("Processing \(paths.count) changed path(s)")

        let fileManager = FileManager.default
        let currentTracks = playerViewModel.playlistManager.tracks
        let currentURLs = Set(currentTracks.map { $0.url.standardizedFileURL.path })

        // 1. 检查删除的文件：
        // 凡是属于音乐源、但在磁盘上已不存在的曲目，均予移除
        var urlsToRemove: Set<URL> = []
        for track in currentTracks {
            if isUnderAnySourceFolder(track.url) {
                if !fileManager.fileExists(atPath: track.url.path) {
                    urlsToRemove.insert(track.url)
                }
            }
        }

        if !urlsToRemove.isEmpty {
            logger.info("🗑️ Auto-watch: removing \(urlsToRemove.count) deleted track(s)")
            playerViewModel.removeTracksFromPlaylist(urls: urlsToRemove)
        }

        // 2. 检查新增的文件：
        var candidateURLsToAdd: [URL] = []
        for path in paths {
            let fileURL = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            guard isUnderAnySourceFolder(fileURL) else { continue }

            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    let files = AudioFileSupport.scanAudioFiles(in: fileURL)
                    for file in files {
                        if !currentURLs.contains(file.standardizedFileURL.path) {
                            candidateURLsToAdd.append(file)
                        }
                    }
                } else if AudioFileSupport.isSupportedAudioFile(fileURL) {
                    if !currentURLs.contains(fileURL.path) {
                        // 避免 0 字节半写入文件
                        if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                           let size = attrs[.size] as? UInt64, size > 0 {
                            candidateURLsToAdd.append(fileURL)
                        }
                    }
                }
            }
        }

        if !candidateURLsToAdd.isEmpty {
            let uniqueToAdd = Array(Set(candidateURLsToAdd))
            logger.info("➕ Auto-watch: adding \(uniqueToAdd.count) new track(s)")
            await playerViewModel.addTracksToPlaylist(urls: uniqueToAdd)
        }
    }

    /// 全量核对所有音乐源文件夹，处理新增和删除
    private func reconcileAllSources() async {
        guard let playerViewModel, !sourceFolders.isEmpty else { return }

        logger.info("🔄 Running full reconciliation for music sources")
        let fileManager = FileManager.default
        let currentTracks = playerViewModel.playlistManager.tracks
        let currentURLs = Set(currentTracks.map { $0.url.standardizedFileURL.path })

        // 1. 删除已不存在的文件
        var urlsToRemove: Set<URL> = []
        for track in currentTracks {
            if isUnderAnySourceFolder(track.url) {
                if !fileManager.fileExists(atPath: track.url.path) {
                    urlsToRemove.insert(track.url)
                }
            }
        }

        if !urlsToRemove.isEmpty {
            logger.info("🗑️ Reconcile: removing \(urlsToRemove.count) deleted track(s)")
            playerViewModel.removeTracksFromPlaylist(urls: urlsToRemove)
        }

        // 2. 扫描发现新文件
        var newURLs: [URL] = []
        for folder in sourceFolders {
            let scanned = AudioFileSupport.scanAudioFiles(in: folder)
            for url in scanned {
                if !currentURLs.contains(url.standardizedFileURL.path) {
                    newURLs.append(url)
                }
            }
        }

        if !newURLs.isEmpty {
            let uniqueNewURLs = Array(Set(newURLs))
            logger.info("➕ Reconcile: adding \(uniqueNewURLs.count) newly found track(s)")
            await playerViewModel.addTracksToPlaylist(urls: uniqueNewURLs)
        }
    }

    // MARK: - Helpers

    func isUnderAnySourceFolder(_ fileURL: URL) -> Bool {
        let filePath = fileURL.standardizedFileURL.resolvingSymlinksInPath().path
        return sourceFolders.contains { folder in
            let folderPath = folder.standardizedFileURL.resolvingSymlinksInPath().path
            if filePath == folderPath { return true }
            let prefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
            return filePath.hasPrefix(prefix)
        }
    }

    private func saveFolders() {
        let paths = sourceFolders.map { $0.standardizedFileURL.path }
        UserDefaults.standard.set(paths, forKey: Key.sourceFolderPaths)
    }

    private func loadSavedFolders() {
        guard let paths = UserDefaults.standard.stringArray(forKey: Key.sourceFolderPaths) else {
            return
        }
        self.sourceFolders = paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
    }
}

// MARK: - Folder Monitor (FSEvents)

nonisolated private final class FolderMonitor: @unchecked Sendable {
    private var streamRef: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.me2tune.fsevents", qos: .utility)
    private var eventHandler: (([String]) -> Void)?

    func start(paths: [String], onEvents: @escaping ([String]) -> Void) {
        stop()
        guard !paths.isEmpty else { return }
        self.eventHandler = onEvents

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        let pathsToWatch = paths as CFArray
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
                guard let clientCallBackInfo else { return }
                let monitor = Unmanaged<FolderMonitor>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
                guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
                monitor.eventHandler?(paths)
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        ) else {
            return
        }

        self.streamRef = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        if let stream = streamRef {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.streamRef = nil
        }
        eventHandler = nil
    }

    deinit {
        stop()
    }
}
