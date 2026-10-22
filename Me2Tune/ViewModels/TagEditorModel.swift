import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class TagEditorModel: Identifiable {
    let id = UUID()
    let track: AudioTrack
    let player: PlayerViewModel
    private(set) var snapshot: TagSnapshot?
    var draft: [TagField: String] = [:]
    var artwork: Data?
    private(set) var isReading = false
    private(set) var isSaving = false
    private(set) var receipt: TagSaveReceipt?
    private(set) var fileWasSaved = false
    var message: String?
    var showUnsavedPrompt = false
    @ObservationIgnored var onDismiss: () -> Void = {}
    @ObservationIgnored private var terminationReply: ((Bool) -> Void)?
    @ObservationIgnored private let service: TrackTagService

    init(track: AudioTrack, player: PlayerViewModel, recovery: TagSaveReceipt? = nil,
         service: TrackTagService = .shared) {
        self.track = track; self.player = player; self.receipt = recovery; self.service = service
    }

    var isBusy: Bool { isReading || isSaving }
    var patch: TagPatch {
        guard let snapshot else { return TagPatch() }
        var fields: [String: String] = [:]
        for field in TagField.allCases where !snapshot.isReadOnly(field) {
            let value = draft[field] ?? ""
            if value != snapshot.text(field) {
                fields[field.rawValue] = field.isNumber ? Int(value).map(String.init) ?? value : value
            }
        }
        return TagPatch(fields: fields, artworkChanged: artwork != snapshot.artwork, artwork: artwork)
    }
    var isDirty: Bool { !patch.isEmpty && !fileWasSaved }
    var canSave: Bool {
        snapshot?.writableFormat == true && !player.isRestoring && !isBusy && receipt == nil && !patch.isEmpty && validationErrors.isEmpty
    }
    var validationErrors: [TagField: String] {
        guard let snapshot else { return [:] }
        var result: [TagField: String] = [:]
        for field in TagField.allCases where field.isNumber && patch.fields[field.rawValue] != nil {
            let value = draft[field] ?? ""
            if !value.isEmpty && (!value.allSatisfy { $0.isASCII && $0.isNumber } || !(1...65535).contains(Int(value) ?? 0)) {
                result[field] = String(localized: "tag_number_error")
            }
        }
        for (number, total) in [(TagField.trackNumber, TagField.trackTotal), (.discNumber, .discTotal)] {
            guard patch.fields[number.rawValue] != nil || patch.fields[total.rawValue] != nil else { continue }
            if let n = Int(draft[number] ?? snapshot.text(number)), let t = Int(draft[total] ?? snapshot.text(total)), n > t {
                result[number] = String(localized: "tag_total_error")
            }
        }
        return result
    }
    var localLyricsURL: URL? {
        let url = (snapshot?.url ?? track.url).deletingPathExtension().appendingPathExtension("lrc")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func load() async {
        guard !isBusy, receipt == nil else { return }
        isReading = true
        defer { isReading = false }
        do {
            let read = try await service.read(url: track.resolveURL() ?? track.url)
            snapshot = read
            draft = Dictionary(uniqueKeysWithValues: TagField.allCases.map { ($0, read.text($0)) })
            artwork = read.artwork
            message = nil
        } catch { snapshot = nil; message = error.localizedDescription }
    }

    func save() {
        guard canSave, let baseline = snapshot else { return }
        let changes = patch
        isSaving = true; message = nil
        Task {
            var playbackLocked = false
            defer {
                if playbackLocked { player.endTagSave() }
                isSaving = false
                if let reply = terminationReply {
                    terminationReply = nil
                    reply(false) // An unsuccessful save cancels a pending quit.
                }
            }
            do {
                try changes.validate(baseline: baseline)
                try await service.preflight(baseline: baseline)
                guard await player.beginTagSave() else { throw TagEditError.playbackBusy }
                playbackLocked = true
                let saved = try await service.save(trackID: track.id, baseline: baseline, patch: changes)
                receipt = saved
                fileWasSaved = true
                try await synchronize(saved)
                complete()
            } catch {
                if receipt == nil { receipt = try? await service.pendingRecovery() }
                let prefix = fileWasSaved ? String(localized: "tag_saved_sync_failed")
                    : (receipt != nil ? String(localized: "tag_recovery_needed") : String(localized: "tag_not_saved"))
                message = prefix + "\n" + error.localizedDescription
            }
        }
    }

    /// This path only reads the current file and retries database/cache synchronization.
    func retrySynchronization() {
        guard let receipt, !isBusy, !player.isRestoring else { return }
        isSaving = true; message = nil
        Task {
            var playbackLocked = false
            defer {
                if playbackLocked { player.endTagSave() }
                isSaving = false
                if let reply = terminationReply { terminationReply = nil; reply(false) }
            }
            do {
                guard await player.beginTagSave() else { throw TagEditError.playbackBusy }
                playbackLocked = true
                try await synchronize(receipt)
                complete()
            } catch {
                message = String(localized: "tag_recovery_needed") + "\n" + error.localizedDescription
            }
        }
    }

    private func synchronize(_ receipt: TagSaveReceipt) async throws {
        let current = try await service.read(url: receipt.url)
        try await player.refreshTrackMetadata(id: receipt.trackID, snapshot: current)
        try await service.finishSave(receipt: receipt)
        self.receipt = nil
    }

    private func complete() {
        let reply = terminationReply
        terminationReply = nil
        onDismiss()
        reply?(true)
    }

    func requestClose() {
        guard !isBusy else { return }
        if isDirty { showUnsavedPrompt = true }
        else { onDismiss() }
    }

    func requestTermination(reply: @escaping (Bool) -> Void) {
        terminationReply = reply
        if isBusy { return }
        if isDirty { showUnsavedPrompt = true }
        else { terminationReply = nil; reply(true) }
    }

    func discardAndClose() {
        showUnsavedPrompt = false
        let reply = terminationReply
        terminationReply = nil
        onDismiss()
        reply?(true)
    }

    func cancelClose() {
        showUnsavedPrompt = false
        let reply = terminationReply
        terminationReply = nil
        reply?(false)
    }

    func saveAndClose() {
        showUnsavedPrompt = false
        guard canSave else { cancelClose(); return }
        save()
    }

    func chooseArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do { self?.artwork = try Data(contentsOf: url) }
                catch { self?.message = error.localizedDescription }
            }
        }
    }

    func importLyrics() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "lrc") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    guard ["txt", "lrc"].contains(url.pathExtension.lowercased()) else { throw TagEditError.validation }
                    self?.draft[.lyrics] = try String(contentsOf: url, encoding: .utf8)
                } catch { self?.message = String(localized: "tag_import_failed") }
            }
        }
    }
}
