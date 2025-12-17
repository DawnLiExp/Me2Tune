//
//  CollectionManager.swift
//  Me2Tune
//
//  专辑收藏管理
//

import Foundation
internal import Combine

@MainActor
final class CollectionManager: ObservableObject {
    @Published private(set) var albums: [Album] = []
    private let persistenceService = PersistenceService()
    
    init() {
        Task {
            await loadCollections()
        }
    }
    
    func addAlbum(from folderURL: URL) async {
        let albumName = folderURL.lastPathComponent
        
        print("📁 开始扫描专辑: \(albumName)")
        
        // 扫描文件夹
        let audioURLs = scanFolder(folderURL)
        
        print("📁 找到 \(audioURLs.count) 首歌曲")
        
        guard !audioURLs.isEmpty else {
            print("⚠️ 文件夹中没有音频文件")
            return
        }
        
        // 创建曲目
        var tracks: [AudioTrack] = []
        for url in audioURLs {
            let track = await AudioTrack(url: url)
            tracks.append(track)
        }
        
        let album = Album(name: albumName, folderURL: folderURL, tracks: tracks)
        
        await MainActor.run {
            self.albums.append(album)
            self.objectWillChange.send()
            
            print("✅ 专辑创建成功: \(albumName), \(tracks.count) 首歌曲")
            print("📚 当前专辑总数: \(self.albums.count)")
            print("📚 专辑列表: \(self.albums.map(\.name))")
            
            Task { await saveCollections() }
        }
    }
    
    func removeAlbum(id: UUID) {
        albums.removeAll { $0.id == id }
        Task { await saveCollections() }
    }
    
    func clearAllAlbums() {
        albums.removeAll()
        Task { await saveCollections() }
    }
    
    private func loadCollections() async {
        do {
            let state = try await persistenceService.loadCollections()
            self.albums = state.albums
            print("📚 成功加载 \(self.albums.count) 个专辑")
        } catch {
            // 首次启动或文件不存在是正常的
            print("⚠️ 无法加载专辑列表: \(error.localizedDescription)")
        }
    }
    
    private func saveCollections() async {
        do {
            let state = CollectionState(albums: self.albums)
            try await persistenceService.save(state)
            print("💾 成功保存 \(self.albums.count) 个专辑")
        } catch {
            print("❌ 无法保存专辑列表: \(error.localizedDescription)")
        }
    }
    
    private func scanFolder(_ folderURL: URL) -> [URL] {
        let fileManager = FileManager.default
        let supportedExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ape", "wv", "tta", "mpc"]
        
        var audioURLs: [URL] = []
        
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
        ) else {
            print("❌ 无法访问文件夹: \(folderURL.path)")
            return []
        }
        
        while let fileURL = enumerator.nextObject() as? URL {
            if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                audioURLs.append(fileURL)
            }
        }
        
        // 按文件名排序
        audioURLs.sort { $0.lastPathComponent < $1.lastPathComponent }
        
        return audioURLs
    }
}
