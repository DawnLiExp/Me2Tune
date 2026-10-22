import AppKit
import Foundation
import SwiftData
import Testing
@testable import Me2Tune

@MainActor
@Suite("Tag editor synchronization and close protection")
struct TagEditorModelTests {
    @Test("Tag field labels resolve actual keys and both shipped languages contain editor translations")
    func localizedLabels() throws {
        for field in TagField.allCases {
            #expect(field.label == Bundle.main.localizedString(forKey: field.localizationKey, value: nil, table: nil))
            #expect(!field.label.hasPrefix("tag_"))
        }
        for language in ["en", "zh-Hans"] {
            let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            for key in TagField.allCases.map(\.localizationKey) + ["tag_editor_title", "tag_save", "tag_stop_hint",
                "tag_saved_sync_failed", "tag_recovery_needed", "tag_retry_sync", "tag_read_current", "tag_error_write", "quit_app"] {
                #expect(bundle.localizedString(forKey: key, value: nil, table: nil) != key)
            }
            #expect(bundle.localizedString(forKey: "tag_title", value: nil, table: nil) == (language == "en" ? "Title" : "标题"))
        }
    }

    private func setup(useAlias: Bool = false, core: (any AudioPlayerCoreProtocol)? = nil,
                       stage: (@Sendable (TagSaveStage) throws -> Void)? = nil) async throws
        -> (TagEditorModel, FailingTagDataService, SDTrack, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("EditorTest-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("test.m4a")
        try FileManager.default.copyItem(at: TrackTagServiceTests.fixtures.appendingPathComponent("aac.m4a"), to: url)
        let data = FailingTagDataService(base: try createTestDataService())
        let reference = useAlias ? dir.appendingPathComponent("alias.m4a") : url
        if useAlias { try FileManager.default.createSymbolicLink(at: reference, withDestinationURL: url) }
        let dto = await AudioTrack(url: reference)
        let record = SDTrack(from: dto)
        record.isInPlaylist = true; record.playlistOrder = 7
        data.insert(record); try data.save()
        let manager = CollectionManager(dataService: data)
        let coordinator = PlaybackCoordinator(collectionManager: manager, dataService: data, playerCore: core,
            defaults: try #require(UserDefaults(suiteName: "TagEditorTest-\(UUID())")))
        let player = PlayerViewModel(coordinator: coordinator)
        while player.restorationPhase != .completed { await Task.yield() }
        let service = TrackTagService(recoveryURL: dir.appendingPathComponent("recovery.json"), beforeStage: stage ?? { _ in })
        let model = TagEditorModel(track: record.toAudioTrack(), player: player, service: service)
        await model.load()
        return (model, data, record, dir)
    }

    @Test("File commit survives database failure; retry only synchronizes and keeps stable identity")
    func databaseFailureRetry() async throws {
        let core = TagEditorPlaybackCore()
        let (model, data, record, dir) = try await setup(core: core)
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = record.stableId
        let oldRevision = model.player.playlistManager.tracks.first?.metadataRevision
        let unrelated = SDAlbum.makeSample(name: "Original album")
        data.insert(unrelated)
        let entry = SDAlbumTrackEntry(trackOrder: 3, album: unrelated, track: record)
        data.insert(entry); try data.save()
        model.player.playbackStateManager.switchToAlbum(unrelated.toAlbum(), selecting: 0)
        unrelated.name = "Unrelated pending change"
        let originalTitle = record.title
        model.draft[.title] = "已保存的新标题"
        data.failSaves = true
        model.save()
        #expect(await waitUntil { !model.isSaving })
        #expect(model.fileWasSaved)
        #expect(model.receipt != nil)
        #expect(record.title == originalTitle)
        #expect(unrelated.name == "Unrelated pending change")
        #expect(!model.player.isSavingTags)
        let savedFile = try Data(contentsOf: model.track.url)
        data.failSaves = false
        model.player.play()
        #expect(await waitUntil { model.player.isPlaying })
        let stops = core.stopCount
        var dismissed = false
        model.onDismiss = { dismissed = true }
        model.retrySynchronization()
        #expect(await waitUntil { !model.isSaving })
        #expect(dismissed)
        #expect(model.receipt == nil)
        #expect(model.player.isPlaying)
        #expect(core.stopCount == stops)
        #expect(try Data(contentsOf: model.track.url) == savedFile)
        #expect(record.stableId == id)
        #expect(record.playlistOrder == 7)
        #expect(record.albumEntries.first?.trackOrder == 3)
        #expect(model.player.currentTrack?.title == "已保存的新标题")
        #expect(model.player.currentTrack?.metadataRevision == model.player.playlistManager.tracks.first?.metadataRevision)
        #expect(record.title == "已保存的新标题")
        #expect(model.player.playlistManager.tracks.first?.metadataRevision != oldRevision)
        #expect(model.player.playlistManager.tracks.first?.id == id)
    }

    @Test("Save failure keeps draft, releases playback gate, and cancels deferred quit")
    func failureAndQuit() async throws {
        let (model, _, _, dir) = try await setup(stage: { if $0 == .write { throw CocoaError(.fileWriteUnknown) } })
        defer { try? FileManager.default.removeItem(at: dir) }
        model.draft[.title] = "draft"
        model.save()
        var reply: Bool?
        model.requestTermination { reply = $0 }
        #expect(reply == nil)
        #expect(await waitUntil { !model.isSaving })
        #expect(reply == false)
        #expect(model.isDirty)
        #expect(model.draft[.title] == "draft")
        #expect(!model.player.isSavingTags)
        #expect(!model.fileWasSaved)
    }

    @Test("Successful save completes deferred quit only after synchronization and cleanup")
    func successfulDeferredQuit() async throws {
        let (model, _, _, dir) = try await setup()
        defer { try? FileManager.default.removeItem(at: dir) }
        model.draft[.title] = "saved"
        model.save()
        var reply: Bool?
        model.requestTermination { reply = $0 }
        #expect(reply == nil)
        #expect(await waitUntil { !model.isSaving })
        #expect(reply == true)
        #expect(model.receipt == nil)
        #expect(!model.player.isSavingTags)
    }

    @Test("No-op, numeric errors, multivalue fields and dirty close are distinct")
    func draftAndClose() async throws {
        let (model, _, _, dir) = try await setup()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(!model.isDirty)
        #expect(!model.canSave)
        model.draft[.artist] = "should remain readonly"
        #expect(!model.isDirty)
        model.draft[.trackNumber] = "13"
        #expect(model.validationErrors[.trackNumber] != nil)
        #expect(!model.canSave)
        model.draft[.trackNumber] = "3"
        #expect(model.canSave)
        var dismissed = false
        model.onDismiss = { dismissed = true }
        model.requestClose()
        #expect(model.showUnsavedPrompt)
        #expect(!dismissed)
        model.cancelClose()
        #expect(model.isDirty)
        model.requestClose(); model.discardAndClose()
        #expect(dismissed)
    }

    @Test("Saving through a symbolic link preserves that library reference")
    func symbolicLinkReference() async throws {
        let (model, _, record, dir) = try await setup(useAlias: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let alias = model.track.url
        let localLyrics = alias.deletingPathExtension().appendingPathExtension("lrc")
        try "[00:01.00] Local lyrics".write(to: localLyrics, atomically: true, encoding: .utf8)
        #expect(model.localLyricsURL == localLyrics)
        model.draft[.title] = "Alias edit"
        model.save()
        #expect(await waitUntil { !model.isSaving })
        #expect(model.message == nil)
        #expect(record.urlString == alias.absoluteString)
        #expect(model.player.playlistManager.tracks.first?.url == alias)
        #expect(try FileManager.default.attributesOfItem(atPath: alias.path)[.type] as? FileAttributeType == .typeSymbolicLink)
    }

    @Test("Pending input is committed before save, close, or quit checks the draft")
    func markedInputBeforeActions() async throws {
        for action in ["close", "save", "quit"] {
            let (model, _, _, dir) = try await setup()
            defer { try? FileManager.default.removeItem(at: dir) }
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 280, height: 30))
            field.stringValue = model.draft[.title] ?? ""
            let delegate = TagInputCommitDelegate { model.draft[.title] = field.stringValue }
            field.delegate = delegate
            window.contentView?.addSubview(field)
            model.editingWindow = window
            #expect(window.makeFirstResponder(field))
            let editor = try #require(field.currentEditor() as? NSTextView)
            editor.setMarkedText("中文待确认", selectedRange: NSRange(location: 5, length: 0),
                                 replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
            #expect(editor.hasMarkedText())
            #expect(!model.isDirty)
            var dismissed = false
            var quitReply: Bool?
            model.onDismiss = { dismissed = true }
            switch action {
            case "save": model.save()
            case "quit": model.requestTermination { quitReply = $0 }
            default: model.requestClose()
            }
            #expect(model.draft[.title] == "中文待确认")
            if action == "save" {
                #expect(await waitUntil { !model.isSaving })
                #expect(model.fileWasSaved)
                #expect(dismissed)
                let saved = try await TrackTagService().read(url: model.track.url)
                #expect(saved.text(.title) == "中文待确认")
            } else {
                #expect(model.showUnsavedPrompt)
                #expect(!dismissed)
                #expect(quitReply == nil)
                model.cancelClose()
                #expect(model.isDirty)
                #expect(!model.showUnsavedPrompt)
                if action == "quit" { #expect(quitReply == false) }
                #expect(field.currentEditor() != nil)
            }
            withExtendedLifetime(delegate) {}
        }
    }

    @Test("The app quit entry checks the draft before starting native termination")
    func quitEntryProtectsDraft() async throws {
        let (model, _, _, dir) = try await setup()
        defer { try? FileManager.default.removeItem(at: dir) }
        let delegate = AppDelegate()
        delegate.tagEditor = model
        model.draft[.title] = "未保存的修改"
        var dismissed = false
        model.onDismiss = { dismissed = true }
        delegate.requestQuit()
        #expect(model.showUnsavedPrompt)
        #expect(!dismissed)
        model.cancelClose()
        #expect(model.isDirty)
        #expect(!dismissed)
    }

    @Test("Repeated quit requests resolve the earlier caller and keep the draft")
    func repeatedQuitRequests() async throws {
        let (model, _, _, dir) = try await setup()
        defer { try? FileManager.default.removeItem(at: dir) }
        model.draft[.title] = "未保存的修改"
        var first: Bool?
        var second: Bool?
        model.requestTermination { first = $0 }
        model.requestTermination { second = $0 }
        #expect(first == false)
        #expect(second == nil)
        #expect(model.showUnsavedPrompt)
        model.cancelClose()
        #expect(second == false)
        #expect(model.isDirty)
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        return condition()
    }
}

@MainActor
private final class TagInputCommitDelegate: NSObject, NSTextFieldDelegate {
    let commit: () -> Void
    init(commit: @escaping () -> Void) { self.commit = commit }
    func controlTextDidEndEditing(_ notification: Notification) { commit() }
}

@MainActor
private final class TagEditorPlaybackCore: AudioPlayerCoreProtocol {
    weak var delegate: (any AudioPlayerCoreDelegate)?
    var isPlaying = false
    var repeatMode: RepeatMode = .off
    var stopCount = 0
    func loadTrack(_ track: AudioTrack, startingAt time: TimeInterval) async -> Bool { true }
    func enqueueTrack(_ track: AudioTrack) -> AudioEnqueueResult { .enqueued(track.id) }
    func play() { isPlaying = true; delegate?.playerCoreDidUpdatePlaybackState(true) }
    func pause() { isPlaying = false; delegate?.playerCoreDidUpdatePlaybackState(false) }
    func prepareForTrackSwitch() { stopCount += 1; pause() }
    func seek(to time: TimeInterval) {}
    func setVolume(_ volume: Double) {}
    func getCurrentPlaybackTime() -> TimeInterval { 0 }
    func updateDockIcon(_ artwork: NSImage?) {}
}

@MainActor
private final class FailingTagDataService: DataServiceProtocol {
    let base: DataService
    var failSaves = false
    init(base: DataService) { self.base = base }
    var modelContext: ModelContext { base.modelContext }
    func insert(_ model: some PersistentModel) { base.insert(model) }
    func delete(_ model: some PersistentModel) { base.delete(model) }
    func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws(AppError) -> [T] { try base.fetch(descriptor) }
    func fetchCount(_ descriptor: FetchDescriptor<some PersistentModel>) throws(AppError) -> Int { try base.fetchCount(descriptor) }
    func save() throws(AppError) {
        if failSaves { throw AppError.swiftDataFailed(underlying: CocoaError(.fileWriteUnknown)) }
        try base.save()
    }
    func findTrack(byURL url: String) -> SDTrack? { base.findTrack(byURL: url) }
    func findTrack(byStableId id: UUID) -> SDTrack? { base.findTrack(byStableId: id) }
    func fetchPlaylistTracks() throws(AppError) -> [SDTrack] { try base.fetchPlaylistTracks() }
    func playlistTrackCount() throws(AppError) -> Int { try base.playlistTrackCount() }
    func fetchAlbums() throws(AppError) -> [SDAlbum] { try base.fetchAlbums() }
    func findAlbum(byFolderURL url: String) -> SDAlbum? { base.findAlbum(byFolderURL: url) }
    func findAlbum(byStableId id: UUID) -> SDAlbum? { base.findAlbum(byStableId: id) }
    func albumCount() throws(AppError) -> Int { try base.albumCount() }
}
