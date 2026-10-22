import Foundation
import Testing
@testable import Me2Tune

@Suite("Tag editing file transactions")
struct TrackTagServiceTests {
    static let names = ["id3v3.mp3", "id3v4.mp3", "vorbis.flac", "aac.m4a", "alac.m4a"]
    static var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/Tags")
    }
    func setup(_ name: String) throws -> (URL, TrackTagService) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TagTest-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try FileManager.default.copyItem(at: Self.fixtures.appendingPathComponent(name), to: url)
        return (url, TrackTagService(recoveryURL: dir.appendingPathComponent("recovery/pending.json")))
    }

    @Test("Selective edit preserves multiple values, second artwork, lyrics and file backup", arguments: names)
    func roundTrip(_ name: String) async throws {
        let (url, service) = try setup(name)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = try Data(contentsOf: url)
        let before = try await service.read(url: url)
        #expect(before.values(.artist).count == 2)
        #expect(before.pictures.count == 2)
        #expect(before.text(.trackTotal) == "12")
        let patch = TagPatch(fields: ["TITLE":"中文标题 🎵", "COMMENT":"", "TRACKTOTAL":"15"], artworkChanged: true, artwork: nil)
        let receipt = try await service.save(trackID: UUID(), baseline: before, patch: patch)
        #expect(try Data(contentsOf: receipt.backupURL) == original)
        let after = try await service.read(url: url)
        #expect(after.text(.title) == "中文标题 🎵")
        #expect(after.text(.comment).isEmpty)
        #expect(after.text(.trackTotal) == "15")
        #expect(after.text(.trackNumber) == "2")
        #expect(after.values(.artist) == before.values(.artist))
        #expect(after.values(.lyrics) == before.values(.lyrics))
        #expect(after.pictures == Array(before.pictures.dropFirst()))
        if name.hasPrefix("id3") {
            #expect(try Data(contentsOf: url)[3] == (name == "id3v3.mp3" ? 3 : 4))
        }
        try await service.finishSave(receipt: receipt)
        #expect(try await service.pendingRecovery() == nil)
        #expect(!FileManager.default.fileExists(atPath: receipt.backupURL.path))
    }

    @Test("Artwork and single embedded lyrics can be replaced", arguments: names)
    func artworkAndLyrics(_ name: String) async throws {
        let (url, service) = try setup(name)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let before = try await service.read(url: url)
        let png = try Data(contentsOf: Self.fixtures.appendingPathComponent("cover.png"))
        let receipt = try await service.save(trackID: UUID(), baseline: before,
            patch: TagPatch(fields: ["LYRICS":"[00:01.00] 新歌词\n[00:02.00] 第二行"], artworkChanged: true, artwork: png))
        let after = try await service.read(url: url)
        #expect(after.artwork == png)
        #expect(after.pictures.count == before.pictures.count)
        #expect(after.text(.lyrics).contains("新歌词"))
        try await service.finishSave(receipt: receipt)
    }

    @Test("Empty, invalid, multi-value, and conflicting patches never touch source")
    func rejectedPatches() async throws {
        let (url, service) = try setup("multiple-lyrics.mp3")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let before = try await service.read(url: url)
        let original = try Data(contentsOf: url)
        #expect(before.values(.lyrics).count == 2)
        for patch in [TagPatch(), TagPatch(fields: ["ARTIST":"overwrite"]), TagPatch(fields: ["LYRICS":"overwrite"]),
                      TagPatch(fields: ["TRACKNUMBER":"13"]), TagPatch(fields: ["TRACKNUMBER":"-1"]),
                      TagPatch(artworkChanged: true, artwork: Data([1,2,3]))] {
            await #expect(throws: (any Error).self) { try await service.save(trackID: UUID(), baseline: before, patch: patch) }
            #expect(try Data(contentsOf: url) == original)
            #expect(try await service.pendingRecovery() == nil)
        }
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: url.path)
        await #expect(throws: (any Error).self) {
            try await service.save(trackID: UUID(), baseline: before, patch: TagPatch(fields: ["TITLE":"conflict"]))
        }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test("Unfinished transaction survives service recreation and blocks a second save")
    func recovery() async throws {
        let (url, service) = try setup("aac.m4a")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let before = try await service.read(url: url)
        let receipt = try await service.save(trackID: UUID(), baseline: before, patch: TagPatch(fields: ["TITLE":"saved"]))
        let restarted = TrackTagService(recoveryURL: url.deletingLastPathComponent().appendingPathComponent("recovery/pending.json"))
        #expect(try await restarted.pendingRecovery()?.id == receipt.id)
        let newBaseline = try await restarted.read(url: url)
        await #expect(throws: (any Error).self) {
            try await restarted.save(trackID: UUID(), baseline: newBaseline, patch: TagPatch(fields: ["TITLE":"blocked"]))
        }
        #expect(try await restarted.read(url: url).text(.title) == "saved")
        try await restarted.finishSave(receipt: receipt)
    }
    @Test("Failure at each transaction stage preserves source or recovery material", arguments: [TagSaveStage.copy, .write, .verify, .replace])
    func failures(stage: TagSaveStage) async throws {
        let (url, _) = try setup("aac.m4a")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = try Data(contentsOf: url)
        let service = TrackTagService(recoveryURL: url.deletingLastPathComponent().appendingPathComponent("pending.json"),
            beforeStage: { if $0 == stage { throw CocoaError(.fileWriteUnknown) } })
        let baseline = try await service.read(url: url)
        await #expect(throws: (any Error).self) {
            try await service.save(trackID: UUID(), baseline: baseline, patch: TagPatch(fields: ["TITLE":"new"]))
        }
        #expect(try Data(contentsOf: url) == original)
        if stage == .replace {
            let pending = try #require(try await service.pendingRecovery())
            #expect(FileManager.default.fileExists(atPath: pending.temporaryURL.path))
            try await service.finishSave(receipt: pending)
        } else { #expect(try await service.pendingRecovery() == nil) }
    }

    @Test("External change during write prevents replacement")
    func conflictDuringSave() async throws {
        let (url, _) = try setup("aac.m4a")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = try Data(contentsOf: url)
        let service = TrackTagService(recoveryURL: url.deletingLastPathComponent().appendingPathComponent("pending.json"),
            beforeStage: { stage in
                if stage == .verify { try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path) }
            })
        let baseline = try await service.read(url: url)
        await #expect(throws: (any Error).self) {
            try await service.save(trackID: UUID(), baseline: baseline, patch: TagPatch(fields: ["TITLE":"new"]))
        }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test("Read-only file is rejected before creating recovery materials")
    func readOnly() async throws {
        let (url, service) = try setup("aac.m4a")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        let baseline = try await service.read(url: url)
        await #expect(throws: (any Error).self) { try await service.preflight(baseline: baseline) }
        #expect(try await service.pendingRecovery() == nil)
    }

    @Test("All scalar fields round trip and explicit deletion removes legacy values", arguments: names)
    func scalars(_ name: String) async throws {
        let (url, service) = try setup(name)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let fields = ["TITLE":"标题", "ALBUM":"新专辑", "ALBUMARTIST":"专辑艺术家", "COMPOSER":"作曲者", "GENRE":"测试流派",
                      "DATE":"2026-10-22", "TRACKNUMBER":"3", "TRACKTOTAL":"20", "DISCNUMBER":"1", "DISCTOTAL":"2", "COMMENT":"备注"]
        var baseline = try await service.read(url: url)
        let receipt = try await service.save(trackID: UUID(), baseline: baseline, patch: TagPatch(fields: fields))
        baseline = try await service.read(url: url)
        for (key, value) in fields { #expect(baseline.fields[key]?.first == value) }
        try await service.finishSave(receipt: receipt)
        let cleared = try await service.save(trackID: UUID(), baseline: baseline,
            patch: TagPatch(fields: fields.mapValues { _ in "" }))
        let after = try await service.read(url: url)
        for key in fields.keys { #expect((after.fields[key]?.first ?? "").isEmpty) }
        try await service.finishSave(receipt: cleared)
    }

    @Test("ffprobe and decoded audio agree after editing", .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/local/bin/ffmpeg")), arguments: names)
    func independentValidation(_ name: String) async throws {
        let (url, service) = try setup(name)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let before = try command("ffmpeg", ["-v","error","-i",url.path,"-map","0:a:0","-f","hash","-hash","sha256","-"])
        let snapshot = try await service.read(url: url)
        let receipt = try await service.save(trackID: UUID(), baseline: snapshot,
            patch: TagPatch(fields: ["TITLE":"交叉验证", "LYRICS":"[00:01.00] 中文歌词"]))
        let after = try command("ffmpeg", ["-v","error","-i",url.path,"-map","0:a:0","-f","hash","-hash","sha256","-"])
        #expect(before == after)
        let probe = try command("ffprobe", ["-v","error","-show_format","-show_streams","-of","json",url.path])
        let json = try #require(try JSONSerialization.jsonObject(with: probe) as? [String: Any])
        let format = try #require(json["format"] as? [String: Any])
        let tags = try #require(format["tags"] as? [String: String])
        #expect(tags.first { $0.key.lowercased() == "title" }?.value == "交叉验证")
        try await service.finishSave(receipt: receipt)
    }

    private func command(_ name: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/" + name)
        process.arguments = arguments
        let pipe = Pipe(); process.standardOutput = pipe
        try process.run()
        let result = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return result
    }

    @Test("Native synchronized lyrics are displayed without allowing destructive conversion")
    func structuredLyrics() async throws {
        let (url, service) = try setup("synchronized-lyrics.mp3")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let snapshot = try await service.read(url: url)
        #expect(snapshot.text(.lyrics) == "Synchronized text")
        #expect(snapshot.isReadOnly(.lyrics))
        await #expect(throws: (any Error).self) {
            try await service.save(trackID: UUID(), baseline: snapshot, patch: TagPatch(fields: ["LYRICS":"replace"]))
        }
        let receipt = try await service.save(trackID: UUID(), baseline: snapshot, patch: TagPatch(fields: ["TITLE":"changed"]))
        #expect(try await service.read(url: url).text(.lyrics) == "Synchronized text")
        try await service.finishSave(receipt: receipt)
    }

}
