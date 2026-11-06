import SwiftUI

nonisolated struct SearchEngine: Sendable {
    struct SearchData: Sendable {
        let playlist: [AudioTrack]
        let albums: [Album]
        let version: Version

        init(playlist: [AudioTrack], albums: [Album]) {
            self.playlist = playlist
            self.albums = albums
            version = Version(
                playlist: playlist.map(TrackVersion.init),
                albums: albums.map {
                    AlbumVersion(id: $0.id, name: $0.name, tracks: $0.tracks.map(TrackVersion.init))
                }
            )
        }
    }

    struct TrackVersion: Equatable, Sendable {
        let id: UUID
        let metadataRevision: UUID

        init(_ track: AudioTrack) {
            id = track.id
            metadataRevision = track.metadataRevision
        }
    }

    struct AlbumVersion: Equatable, Sendable {
        let id: UUID
        let name: String
        let tracks: [TrackVersion]
    }

    struct Version: Equatable, Sendable {
        let playlist: [TrackVersion]
        let albums: [AlbumVersion]
    }

    struct Request: Equatable, Sendable {
        let query: String
        let version: Version
    }

    struct Batch: Sendable {
        let request: Request
        let results: [SearchResult]

        func results(for currentRequest: Request?) -> [SearchResult]? {
            request == currentRequest ? results : nil
        }
    }

    // The view owns cancellation via .task(id:); this also rejects computations
    // that return successfully after cancellation, before touching UI state.
    @MainActor
    static func run(
        request: Request,
        data: SearchData,
        canPublish: () -> Bool,
        compute: (SearchData, String) async throws -> [SearchResult] = {
            try await SearchEngine(searchData: $0).search(query: $1)
        },
        publish: (Batch) -> Void
    ) async {
        do {
            try Task.checkCancellation()
            let results = try await compute(data, request.query)
            try Task.checkCancellation()
            guard canPublish() else { return }
            publish(Batch(request: request, results: results))
        } catch is CancellationError {
            // Cancellation is a normal search lifecycle event.
        } catch {
            assertionFailure("Unexpected search failure: \(error)")
        }
    }

    struct SearchResult: Identifiable, Sendable {
        let id: UUID
        let title: String
        let subtitle: String
        let icon: String
        let action: Action
        let category: Category
        let relevance: Int

        enum Action: Sendable {
            case playPlaylistTrack(Int)
            case playAlbumTrack(Album, Int)
            case openAlbum(Album)
        }

        enum Category: String, Comparable, Sendable {
            case album
            case song

            var displayName: LocalizedStringKey {
                switch self {
                case .album: return "category_albums"
                case .song: return "category_songs"
                }
            }

            static func < (lhs: Category, rhs: Category) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }
    }

    let searchData: SearchData
    private let maxTotalSongResults = 20
    private let maxAlbumResults = 10
    private let maxPerSourceSongs = 20

    @concurrent
    func search(query text: String) async throws -> [SearchResult] {
        try Task.checkCancellation()
        let query = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        var allResults: [SearchResult] = []

        let playlistResults = try searchPlaylistTracks(query: query)
        let albumResults = try searchAlbums(query: query)
        let albumTrackResults = try searchAlbumTracks(query: query)

        var songResults = playlistResults + albumTrackResults
        songResults.sort { $0.relevance > $1.relevance }

        if songResults.count > maxTotalSongResults {
            songResults = Array(songResults.prefix(maxTotalSongResults))
        }

        allResults.append(contentsOf: albumResults)
        allResults.append(contentsOf: songResults)

        return allResults
    }

    private func searchPlaylistTracks(query: String) throws -> [SearchResult] {
        var results: [SearchResult] = []

        for (index, track) in searchData.playlist.enumerated() {
            try Task.checkCancellation()
            guard results.count < maxPerSourceSongs else { break }

            let titleMatch = track.title.lowercased().contains(query)
            let artistMatch = track.artist?.lowercased().contains(query) ?? false
            let albumMatch = track.albumTitle?.lowercased().contains(query) ?? false

            guard titleMatch || artistMatch || albumMatch else { continue }

            let relevance = titleMatch ? 3 : (artistMatch ? 2 : 1)

            let subtitle = [
                track.artist ?? String(localized: "unknown_artist"),
                String(localized: "from_playlist")
            ]
            .joined(separator: " • ")

            results.append(SearchResult(
                id: UUID(),
                title: track.title,
                subtitle: subtitle,
                icon: "music.note",
                action: .playPlaylistTrack(index),
                category: .song,
                relevance: relevance
            ))
        }

        return results
    }

    private func searchAlbums(query: String) throws -> [SearchResult] {
        var results: [SearchResult] = []

        for album in searchData.albums {
            try Task.checkCancellation()
            guard results.count < maxAlbumResults else { break }

            let nameMatch = album.name.lowercased().contains(query)
            let artistMatch = try album.tracks.contains { track in
                try Task.checkCancellation()
                return track.artist?.lowercased().contains(query) ?? false
            }

            guard nameMatch || artistMatch else { continue }

            let artist = album.tracks.first?.artist
            let trackCountText = trackCountText(for: album.tracks.count)
            let subtitle: String
            if let artist, !artist.isEmpty {
                let format = String(localized: "search_album_subtitle_with_artist_format")
                subtitle = String(format: format, locale: Locale.current, artist, trackCountText)
            } else {
                subtitle = trackCountText
            }

            let relevance = nameMatch ? 3 : 2

            results.append(SearchResult(
                id: album.id,
                title: album.name,
                subtitle: subtitle,
                icon: "opticaldisc",
                action: .openAlbum(album),
                category: .album,
                relevance: relevance
            ))
        }

        return results
    }

    private func searchAlbumTracks(query: String) throws -> [SearchResult] {
        var results: [SearchResult] = []

        albumLoop: for album in searchData.albums {
            try Task.checkCancellation()
            for (index, track) in album.tracks.enumerated() {
                try Task.checkCancellation()
                guard results.count < maxPerSourceSongs else { break albumLoop }

                let titleMatch = track.title.lowercased().contains(query)
                let artistMatch = track.artist?.lowercased().contains(query) ?? false

                guard titleMatch || artistMatch else { continue }

                let relevance = titleMatch ? 3 : 2

                let subtitle = [
                    track.artist ?? String(localized: "unknown_artist"),
                    inAlbumText(for: album.name)
                ]
                .joined(separator: " • ")

                results.append(SearchResult(
                    id: UUID(),
                    title: track.title,
                    subtitle: subtitle,
                    icon: "music.note",
                    action: .playAlbumTrack(album, index),
                    category: .song,
                    relevance: relevance
                ))
            }
        }

        return results
    }

    private func trackCountText(for count: Int) -> String {
        let format = String(localized: "track_count_format")
        return String(format: format, locale: Locale.current, Int64(count))
    }

    private func inAlbumText(for albumName: String) -> String {
        let format = String(localized: "search_in_album_format")
        return String(format: format, locale: Locale.current, albumName)
    }
}
