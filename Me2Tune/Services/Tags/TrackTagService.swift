import Foundation
import ImageIO
import SFBAudioEngine

nonisolated enum TagField: String, CaseIterable, Codable, Sendable {
    case title = "TITLE", artist = "ARTIST", album = "ALBUM", albumArtist = "ALBUMARTIST"
    case composer = "COMPOSER", genre = "GENRE", date = "DATE"
    case trackNumber = "TRACKNUMBER", trackTotal = "TRACKTOTAL", discNumber = "DISCNUMBER", discTotal = "DISCTOTAL"
    case comment = "COMMENT", lyrics = "LYRICS"

    var label: String { String(localized: String.LocalizationValue("tag_\(rawValue.lowercased())")) }
    var isNumber: Bool { [.trackNumber, .trackTotal, .discNumber, .discTotal].contains(self) }
}

nonisolated struct TagFingerprint: Codable, Equatable, Sendable {
    let size: UInt64
    let modified: Date
    let inode: UInt64

    init(url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? UInt64,
              let modified = attributes[.modificationDate] as? Date,
              let inode = attributes[.systemFileNumber] as? UInt64 else { throw TagEditError.unreadable }
        self.size = size; self.modified = modified; self.inode = inode
    }
}

nonisolated struct TagPicture: Equatable, Sendable {
    let data: Data
    let type: Int
}

nonisolated struct TagSnapshot: Sendable {
    let url: URL
    let fingerprint: TagFingerprint
    let writableFormat: Bool
    let fields: [String: [String]]
    let readOnlyFields: Set<String>
    let pictures: [TagPicture]
    let primaryPicture: Int?

    func values(_ field: TagField) -> [String] { fields[field.rawValue] ?? [] }
    func isReadOnly(_ field: TagField) -> Bool { !writableFormat || values(field).count > 1 || readOnlyFields.contains(field.rawValue) }
    func text(_ field: TagField) -> String { values(field).joined(separator: "\n") }
    var artwork: Data? { primaryPicture.flatMap { pictures.indices.contains($0) ? pictures[$0].data : nil } }
}

nonisolated struct TagPatch: Sendable {
    var fields: [String: String] = [:]
    var artworkChanged = false
    var artwork: Data?
    var isEmpty: Bool { fields.isEmpty && !artworkChanged }

    func validate(baseline: TagSnapshot) throws {
        if artworkChanged, let artwork {
            guard let source = CGImageSourceCreateWithData(artwork as CFData, nil),
                  CGImageSourceGetCount(source) == 1,
                  let type = CGImageSourceGetType(source) as String?,
                  ["public.jpeg", "public.png"].contains(type),
                  CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 256
                  ] as CFDictionary) != nil else { throw TagEditError.validation }
        }
        for field in TagField.allCases where field.isNumber {
            guard let value = fields[field.rawValue], !value.isEmpty else { continue }
            guard value.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(value),
                  (1...65535).contains(number) else { throw TagEditError.validation }
        }
        for (number, total) in [(TagField.trackNumber, TagField.trackTotal), (.discNumber, .discTotal)] {
            guard fields[number.rawValue] != nil || fields[total.rawValue] != nil else { continue }
            let n = Int(fields[number.rawValue] ?? baseline.text(number))
            let t = Int(fields[total.rawValue] ?? baseline.text(total))
            if let n, let t, n > t { throw TagEditError.validation }
        }
    }
}

nonisolated struct TagSaveReceipt: Codable, Sendable, Identifiable {
    let id: UUID
    let trackID: UUID
    let url: URL
    let temporaryURL: URL
    let backupURL: URL
}

nonisolated enum TagEditError: LocalizedError {
    case unreadable, conflict, readOnly, unsupported, pendingRecovery, validation, emptyPatch, playbackBusy
    var errorDescription: String? {
        let key: String = switch self {
        case .unreadable: "tag_error_read"
        case .conflict: "tag_error_conflict"
        case .readOnly: "tag_error_permission"
        case .unsupported: "tag_error_format"
        case .pendingRecovery: "tag_error_recovery"
        case .validation: "tag_error_validation"
        case .emptyPatch: "tag_error_no_changes"
        case .playbackBusy: "tag_error_playback_busy"
        }
        return String(localized: String.LocalizationValue(key))
    }
}

nonisolated enum TagSaveStage: Sendable { case copy, write, verify, replace }

actor TrackTagService {
    static let shared = TrackTagService()
    private let recoveryURL: URL
    private let beforeStage: @Sendable (TagSaveStage) throws -> Void
    // A synchronous actor operation owns every TagLib object; none cross suspension points.
    init(recoveryURL: URL? = nil, beforeStage: @escaping @Sendable (TagSaveStage) throws -> Void = { _ in }) {
        self.beforeStage = beforeStage
        self.recoveryURL = recoveryURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Me2Tune/TagEditing/pending.json")
    }

    func read(url: URL) throws -> TagSnapshot {
        let url = url.resolvingSymlinksInPath()
        let before = try TagFingerprint(url: url)
        let supported = ["mp3", "flac", "m4a"].contains(url.pathExtension.lowercased())
        let fields: [String: [String]]
        var writable = supported
        var readOnlyFields: Set<String> = []
        var pictures: [TagPicture] = []
        var primary: Int?
        if supported {
            let raw = try MTTagLibBridge.read(url)
            readOnlyFields = Set(raw["readonly"] as? [String] ?? [])
            writable = raw["writable"] as? Bool ?? true
            fields = raw["fields"] as? [String: [String]] ?? [:]
            pictures = (raw["pictures"] as? [[String: Any]] ?? []).compactMap {
                guard let data = $0["data"] as? Data, let type = $0["type"] as? Int else { return nil }
                return TagPicture(data: data, type: type)
            }
            if let index = raw["primary"] as? Int, pictures.indices.contains(index) { primary = index }
        } else {
            let file = try SFBAudioEngine.AudioFile(readingPropertiesAndMetadataFrom: url)
            fields = [TagField.title.rawValue: file.metadata.title.map { [$0] } ?? [],
                      TagField.artist.rawValue: file.metadata.artist.map { [$0] } ?? [],
                      TagField.album.rawValue: file.metadata.albumTitle.map { [$0] } ?? [],
                      TagField.lyrics.rawValue: file.metadata.lyrics.map { [$0] } ?? []]
        }
        guard before == (try TagFingerprint(url: url)) else { throw TagEditError.conflict }
        return TagSnapshot(url: url, fingerprint: before, writableFormat: writable, fields: fields, readOnlyFields: readOnlyFields, pictures: pictures, primaryPicture: primary)
    }

    func preflight(baseline: TagSnapshot) throws {
        guard baseline.writableFormat else { throw TagEditError.unsupported }
        guard !FileManager.default.fileExists(atPath: recoveryURL.path) else { throw TagEditError.pendingRecovery }
        guard baseline.fingerprint == (try TagFingerprint(url: baseline.url)) else { throw TagEditError.conflict }
        let values = try baseline.url.resourceValues(forKeys: [.isWritableKey, .isUserImmutableKey, .isSystemImmutableKey])
        guard values.isWritable == true, values.isUserImmutable != true, values.isSystemImmutable != true,
              FileManager.default.isWritableFile(atPath: baseline.url.deletingLastPathComponent().path) else { throw TagEditError.readOnly }
    }

    func save(trackID: UUID, baseline: TagSnapshot, patch: TagPatch) throws -> TagSaveReceipt {
        guard !patch.isEmpty else { throw TagEditError.emptyPatch }
        try preflight(baseline: baseline)
        for (key, _) in patch.fields {
            guard let field = TagField(rawValue: key), !baseline.isReadOnly(field) else { throw TagEditError.validation }
        }
        try patch.validate(baseline: baseline)
        try Task.checkCancellation()
        let manager = FileManager.default
        let id = UUID()
        let directory = baseline.url.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".me2tune-\(id).\(baseline.url.pathExtension)")
        let backup = directory.appendingPathComponent(".me2tune-\(id).backup")
        let receipt = TagSaveReceipt(id: id, trackID: trackID, url: baseline.url, temporaryURL: temporary, backupURL: backup)
        var recorded = false
        var preserveRecovery = false
        defer {
            if !preserveRecovery {
                do {
                    if manager.fileExists(atPath: temporary.path) { try manager.removeItem(at: temporary) }
                    if recorded { try manager.removeItem(at: recoveryURL) }
                } catch {
                    // Keep the record if cleanup fails, so a later save cannot hide these materials.
                }
            }
        }
        try beforeStage(.copy)
        try manager.createDirectory(at: recoveryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Exclusive creation prevents another service/process from replacing an unresolved receipt.
        // Record before copying: interruption during a large copy/write also leaves a discoverable path.
        try JSONEncoder().encode(receipt).write(to: recoveryURL, options: .withoutOverwriting)
        recorded = true
        try manager.copyItem(at: baseline.url, to: temporary)
        try beforeStage(.write)
        try MTTagLibBridge.write(temporary, fields: patch.fields, artworkChanged: patch.artworkChanged, artwork: patch.artwork)
        try beforeStage(.verify)
        _ = try read(url: temporary)
        try Task.checkCancellation()
        guard baseline.fingerprint == (try TagFingerprint(url: baseline.url)) else { throw TagEditError.conflict }
        // From this point replacement may have occurred even if the OS reports an error.
        preserveRecovery = true
        try beforeStage(.replace)
        _ = try manager.replaceItemAt(baseline.url, withItemAt: temporary, backupItemName: backup.lastPathComponent,
                                     options: [.withoutDeletingBackupItem])
        return receipt
    }

    func pendingRecovery() throws -> TagSaveReceipt? {
        guard FileManager.default.fileExists(atPath: recoveryURL.path) else { return nil }
        return try JSONDecoder().decode(TagSaveReceipt.self, from: Data(contentsOf: recoveryURL))
    }

    func finishSave(receipt: TagSaveReceipt) throws {
        guard let pending = try pendingRecovery(), pending.id == receipt.id else { throw TagEditError.pendingRecovery }
        for url in [receipt.backupURL, receipt.temporaryURL] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.removeItem(at: recoveryURL)
    }
}
