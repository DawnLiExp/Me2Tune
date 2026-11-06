import CryptoKit
import Foundation
import Testing
@testable import Me2Tune

@MainActor
@Suite("Search snapshots, matching and cancellation")
struct SearchTests {
    @Test("Matches signatures captured from the baseline implementation")
    func baselineEquivalence() async throws {
        // Golden signatures use the same en_US locale and application resources.
        #expect(Locale.current.identifier == "en_US")
        #expect(String(localized: "unknown_artist") == "Unknown Artist")
        let data = SearchFixtures.data()
        for (query, expected) in SearchFixtures.golden {
            let results = try await SearchEngine(searchData: data).search(query: query)
            #expect(try SearchFixtures.digest(results, data: data) == expected, "Query: \(query)")
        }
    }

    @Test("Version includes metadata, order, album names, empty albums and source boundaries")
    func versions() {
        let a = SearchFixtures.track(1)
        let b = SearchFixtures.track(2)
        let album = SearchFixtures.album(1, tracks: [a, b])
        let original = SearchEngine.SearchData(playlist: [a, b], albums: [album])
        #expect(original.version == SearchEngine.SearchData(playlist: [a, b], albums: [album]).version)
        let edited = SearchFixtures.track(1, revision: 2, title: "Edited")
        #expect(a == edited) // DTO equality alone intentionally misses the edit.
        var renamed = album
        renamed.name = "Renamed"
        var reordered = album
        reordered.tracks.reverse()
        var retagged = album
        retagged.tracks[0] = edited
        let empty = SearchFixtures.album(2, tracks: [])
        let changed: [SearchEngine.SearchData] = [
            .init(playlist: [edited, b], albums: [album]),
            .init(playlist: [a, b], albums: [retagged]),
            .init(playlist: [a, b], albums: [renamed]),
            .init(playlist: [b, a], albums: [album]),
            .init(playlist: [a], albums: [album]),
            .init(playlist: [a, b, a], albums: [album]),
            .init(playlist: [a, b], albums: [reordered]),
            .init(playlist: [a, b], albums: [album, empty]),
            .init(playlist: [a, b], albums: []),
            .init(playlist: [a, b, a], albums: [SearchFixtures.album(1, tracks: [b])]),
            .init(playlist: [a, b], albums: [SearchFixtures.album(1, tracks: [a]), SearchFixtures.album(2, tracks: [b])])
        ]
        for snapshot in changed { #expect(snapshot.version != original.version) }
        let ordered = SearchEngine.SearchData(playlist: [], albums: [album, empty])
        #expect(ordered.version != SearchEngine.SearchData(playlist: [], albums: [empty, album]).version)
        #expect(SearchEngine.SearchData(playlist: [a], albums: []).version !=
                SearchEngine.SearchData(playlist: [], albums: [SearchFixtures.album(1, tracks: [a])]).version)
    }

    @Test("Old batches cannot display or dispatch after data changes")
    func resultActionsFollowSnapshot() async throws {
        let a = SearchFixtures.track(1, title: "Needle A")
        let b = SearchFixtures.track(2, title: "Needle B")
        let album = SearchFixtures.album(1, name: "Needle album", tracks: [a, b])
        let original = SearchEngine.SearchData(playlist: [a, b], albums: [album])
        let request = SearchEngine.Request(query: "needle", version: original.version)
        let results = try await SearchEngine(searchData: original).search(query: request.query)
        let batch = SearchEngine.Batch(request: request, results: results)
        #expect(batch.results(for: nil) == nil)
        #expect(batch.results(for: .init(query: "other", version: original.version)) == nil)
        let edited = SearchFixtures.track(1, revision: 2, title: "Needle edited")
        for data in [
            SearchEngine.SearchData(playlist: [b, a], albums: [album]),
            .init(playlist: [b], albums: [album]),
            .init(playlist: [edited, b], albums: [album]),
            .init(playlist: [a, b], albums: [SearchFixtures.album(1, name: "Renamed", tracks: [a, b])])
        ] {
            let current = SearchEngine.Request(query: "needle", version: data.version)
            #expect(batch.results(for: current) == nil)
            let fresh = try await SearchEngine(searchData: data).search(query: current.query)
            for result in fresh {
                switch result.action {
                case .playPlaylistTrack(let index):
                    #expect(result.title == data.playlist[index].title)
                case .playAlbumTrack(let selectedAlbum, let index):
                    #expect(result.title == selectedAlbum.tracks[index].title)
                    #expect(data.albums.contains { $0.id == selectedAlbum.id && $0.name == selectedAlbum.name })
                case .openAlbum(let selectedAlbum):
                    #expect(result.title == selectedAlbum.name)
                    #expect(data.albums.contains { $0.id == selectedAlbum.id && $0.name == selectedAlbum.name })
                }
            }
        }
    }

    @Test("Late cancelled query and data tasks cannot replace a newer batch", arguments: [false, true])
    func lateCompletion(dataChange: Bool) async {
        let data = SearchFixtures.data()
        let next = SearchEngine.SearchData(playlist: Array(data.playlist.reversed()), albums: data.albums)
        let oldRequest = SearchEngine.Request(query: "old", version: data.version)
        let newRequest = SearchEngine.Request(query: dataChange ? "old" : "new", version: dataChange ? next.version : data.version)
        let gate = SearchGate()
        var batch: SearchEngine.Batch?
        let old = Task {
            await SearchEngine.run(request: oldRequest, data: data, canPublish: { true }, compute: { _, _ in
                await gate.suspend()
                return [] // Deliberately ignores cancellation at the computation layer.
            }, publish: { batch = $0 })
        }
        await gate.waitUntilStarted()
        old.cancel()
        await SearchEngine.run(request: newRequest, data: dataChange ? next : data, canPublish: { true },
                               compute: { _, _ in [] }, publish: { batch = $0 })
        gate.finish()
        await old.value
        #expect(old.isCancelled)
        #expect(batch?.request == newRequest)
        #expect(batch?.results(for: oldRequest) == nil)
    }

    @Test("Closing animation rejects completion even before task cancellation")
    func closingAndReopening() async {
        let data = SearchFixtures.data()
        let request = SearchEngine.Request(query: "shared", version: data.version)
        let gate = SearchGate()
        var isClosing = false
        var batch: SearchEngine.Batch?
        let old = Task {
            await SearchEngine.run(request: request, data: data, canPublish: { !isClosing }, compute: { _, _ in
                await gate.suspend()
                return []
            }, publish: { batch = $0 })
        }
        await gate.waitUntilStarted()
        isClosing = true
        gate.finish()
        await old.value
        #expect(batch == nil)
        isClosing = false
        await SearchEngine.run(request: request, data: data, canPublish: { !isClosing }, publish: { batch = $0 })
        #expect(batch?.results.isEmpty == false)
    }

    @Test("Disappearance cancellation survives reopening with the same request")
    func disappearanceAndSameRequestReopen() async {
        let data = SearchFixtures.data()
        let request = SearchEngine.Request(query: "shared", version: data.version)
        let gate = SearchGate()
        var batch: SearchEngine.Batch?
        let old = Task {
            await SearchEngine.run(request: request, data: data, canPublish: { true }, compute: { _, _ in
                await gate.suspend()
                return []
            }, publish: { batch = $0 })
        }
        await gate.waitUntilStarted()
        old.cancel()
        await SearchEngine.run(request: request, data: data, canPublish: { true }, publish: { batch = $0 })
        let freshIDs = batch?.results.map(\.id)
        gate.finish()
        await old.value
        #expect(batch?.results.isEmpty == false)
        #expect(batch?.results.map(\.id) == freshIDs)
    }

    @Test("Already cancelled searches do not scan or publish")
    func cancelledBeforeStart() async {
        let data = SearchFixtures.data()
        let task = Task {
            await SearchEngine.run(request: .init(query: "shared", version: data.version), data: data,
                                   canPublish: { true }, compute: { _, _ in
                Issue.record("Cancelled execution should not compute")
                return []
            }, publish: { _ in Issue.record("Cancelled execution should not publish") })
            do {
                _ = try await SearchEngine(searchData: data).search(query: "shared")
                Issue.record("Engine must honor cancellation")
            } catch {
                #expect(error is CancellationError)
            }
        }
        task.cancel()
        await task.value
    }
}

@MainActor
private final class SearchGate {
    private var completion: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func suspend() async {
        await withCheckedContinuation { completion in
            self.completion = completion
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        if completion != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish() {
        completion?.resume()
        completion = nil
    }
}

// Shared verbatim with the standalone baseline signature capture.
@MainActor
private enum SearchFixtures {
    static func uuid(_ value: Int, prefix: String = "00000000") -> UUID {
        UUID(uuidString: String(format: "\(prefix)-0000-0000-0000-%012d", value))!
    }

    static func track(_ value: Int, revision: Int = 1, title: String? = nil) -> AudioTrack {
        AudioTrack(id: uuid(value), url: URL(fileURLWithPath: "/synthetic/\(value).flac"),
                   title: title ?? "Song \(value) 測試", artist: value % 3 == 0 ? nil : "Shared Artist 歌手",
                   albumTitle: value % 4 == 0 ? nil : "TagOnly 專輯", duration: Double(value),
                   format: AudioFormat(codec: "FLAC", bitrate: 700, sampleRate: 44100, bitDepth: 16, channels: 2),
                   bookmark: Data([1, 2, 3]), metadataRevision: uuid(value + revision * 1000, prefix: "11111111"))
    }

    static func album(_ value: Int, name: String? = nil, tracks: [AudioTrack]) -> Album {
        Album(id: uuid(value, prefix: "22222222"), name: name ?? "Shared Collection \(value) 專輯",
              folderURL: URL(fileURLWithPath: "/synthetic/album-\(value)"), tracks: tracks)
    }

    static func data() -> SearchEngine.SearchData {
        let tracks = (1...70).map { track($0) }
        let albums = (1...12).map { index in
            album(index, tracks: Array(tracks[(index - 1) * 5..<index * 5]))
        } + [album(13, name: "Empty 專輯", tracks: []), album(14, tracks: [track(99, title: "Tail unique_needle_詞")])]
        return .init(playlist: Array(tracks.prefix(35)), albums: albums)
    }

    static let queries = ["", " \n ", " SONG 1 ", "測試", "歌手", "tagonly", "shared", "專輯", "empty", "unique_needle_詞", "zz_no_match", "song 3"]

    static func trackSignature(_ track: AudioTrack) -> [String: Any] {
        ["id": track.id.uuidString, "url": track.url.absoluteString, "title": track.title,
         "artist": track.artist as Any? ?? NSNull(), "albumTitle": track.albumTitle as Any? ?? NSNull(),
         "duration": track.duration, "bookmark": track.bookmark?.base64EncodedString() as Any? ?? NSNull(),
         "metadataRevision": track.metadataRevision.uuidString,
         "format": ["codec": track.format.codec as Any? ?? NSNull(), "bitrate": track.format.bitrate as Any? ?? NSNull(),
                    "sampleRate": track.format.sampleRate as Any? ?? NSNull(), "bitDepth": track.format.bitDepth as Any? ?? NSNull(),
                    "channels": track.format.channels as Any? ?? NSNull()]]
    }

    static func albumSignature(_ album: Album) -> [String: Any] {
        ["id": album.id.uuidString, "name": album.name, "folderURL": album.folderURL?.absoluteString as Any? ?? NSNull(),
         "tracks": album.tracks.map(trackSignature)]
    }

    static func signatures(_ results: [SearchEngine.SearchResult], data: SearchEngine.SearchData) -> [[String: Any]] {
        results.map { result in
            let action: [String: Any]
            switch result.action {
            case .playPlaylistTrack(let index):
                action = ["source": "playlist", "index": index, "track": trackSignature(data.playlist[index])]
            case .playAlbumTrack(let album, let index):
                action = ["source": "albumTrack", "index": index, "album": albumSignature(album)]
            case .openAlbum(let album):
                action = ["source": "album", "album": albumSignature(album)]
            }
            return ["title": result.title, "subtitle": result.subtitle, "icon": result.icon,
                    "category": result.category.rawValue, "relevance": result.relevance, "action": action]
        }
    }

    static func digest(_ results: [SearchEngine.SearchResult], data: SearchEngine.SearchData) throws -> String {
        let bytes = try JSONSerialization.data(withJSONObject: signatures(results, data: data), options: [.sortedKeys])
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    // Generated from 539ce55, before comparing against the new engine.
    static let golden: [String: String] = [
        "": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
        " \n ": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
        " SONG 1 ": "5e555e70f0c6d73e2761acc2ffd56e62353c3d5a779f5397a478a0cf7cdafd15",
        "empty": "31919e0f152d273ff14800d643f0116e437f3654ab969cfac353925c60b7b731",
        "shared": "74ae198f72aa84b3a943f31490ab0c6bd3d6a0149bb04495747fc40c43816c39",
        "song 3": "9933249f47a18253018af5534d7df0fdc68fac3016c2d0506b680a987bdc2dad",
        "tagonly": "619dc58760388e5e51196023c35ef7450c711165951da7117a47d02c832b7639",
        "unique_needle_詞": "3b7a7f878a5e53539c52f5a66662c8b0c344c26eea8adee0454845a6e9950657",
        "zz_no_match": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
        "專輯": "a3b39d3d2da4290b790924e275ac3a46a9dcb432d5871cbc7b040cbf8a4b1da6",
        "歌手": "2e96a6addcb92897b5416841d96c5fc47b9c73ddf047b51471b4700e151ba522",
        "測試": "96ecda8ef13c956f5c286d73b4bf17ef277e99d7ca19ef948685f8abaf77ba79",
    ]
}
