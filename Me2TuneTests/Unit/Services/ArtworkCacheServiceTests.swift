import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Me2Tune

@Suite("Artwork extraction and isolated cache")
@MainActor
struct ArtworkCacheServiceTests {
    @Test("Embedded JPEG takes priority and invalidation replaces memory and disk artwork")
    func embeddedAndCacheLifecycle() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("track.mp3")
        try FileManager.default.copyItem(at: TrackTagServiceTests.fixtures.appendingPathComponent("id3v3.mp3"), to: url)
        let tags = TrackTagService(recoveryURL: root.appendingPathComponent("recovery/pending.json"))
        try await replaceArtwork(try picture(type: .jpeg), at: url, using: tags)
        try picture(type: .png, blue: true).write(to: root.appendingPathComponent("00-folder.png"))
        let cache = ArtworkCacheService(cacheDirectory: root.appendingPathComponent("cache"))
        let first = try #require(await cache.artwork(for: url))
        try checkQuadrants(first)
        let memory = try #require(await cache.artwork(for: url))
        #expect(memory === first)

        // Removing the source makes a subsequent successful load evidence of a disk hit.
        let held = root.appendingPathComponent("held.mp3")
        try FileManager.default.moveItem(at: url, to: held)
        await cache.clearMemoryCache()
        let disk = try #require(await cache.artwork(for: url))
        #expect(disk !== first)
        try checkQuadrants(disk)
        try FileManager.default.moveItem(at: held, to: url)
        try FileManager.default.removeItem(at: root.appendingPathComponent("00-folder.png"))

        try await replaceArtwork(try picture(type: .jpeg, blue: true), at: url, using: tags)
        // Match PlaybackCoordinator.refreshTrackMetadata's existing invalidation order.
        await FileMetadataReader.shared.invalidate(url: url)
        await cache.invalidate(url: url)
        #expect(await cache.getCacheStats().count == 0)
        let updated = try #require(await cache.artwork(for: url))
        let rep = try bitmap(updated)
        let color = try pixel(rep, x: 75, y: 75)
        #expect(color.blueComponent > 0.8 && color.redComponent < 0.2)
        #expect(await cache.getCacheStats().count == 1)
        await FileMetadataReader.shared.invalidate(url: url)
    }

    @Test("Folder fallback preserves sorting, hidden filtering, alpha and first-image failure")
    func folderSelection() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("missing.mp3")
        let cache = ArtworkCacheService(cacheDirectory: root.appendingPathComponent("cache"))
        try picture(type: .png, blue: true).write(to: root.appendingPathComponent(".00-hidden.png"))
        try picture(type: .jpeg, blue: true).write(to: root.appendingPathComponent("z.jpg"))
        let selected = root.appendingPathComponent("a.PNG")
        try picture(type: .png, transparent: true).write(to: selected)
        let image = try #require(await cache.artwork(for: url))
        try checkQuadrants(image)
        let rep = try bitmap(image)
        #expect(try pixel(rep, x: 5, y: 75).alphaComponent < 0.05)
        #expect(try pixel(rep, x: 75, y: 75).alphaComponent > 0.95)

        try Data([1, 2, 3, 4]).write(to: selected)
        await cache.invalidate(url: url)
        #expect(await cache.artwork(for: url) == nil) // Do not skip a broken first image.
        try FileManager.default.removeItem(at: selected)
        try FileManager.default.removeItem(at: root.appendingPathComponent("z.jpg"))
        await cache.invalidate(url: url)
        #expect(await cache.artwork(for: url) == nil) // Hidden artwork remains ignored.
        await FileMetadataReader.shared.invalidate(url: url)
    }

    @Test("Orientation JPEG and TIFF retain square stretch and visible quadrants", arguments: ["oriented.jpg", "legacy.tiff"])
    func representativeFormats(_ name: String) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("missing.mp3")
        try picture(type: name.hasSuffix("jpg") ? .jpeg : .tiff,
                    orientation: name.hasSuffix("jpg") ? 6 : 1).write(to: root.appendingPathComponent(name))
        let cache = ArtworkCacheService(cacheDirectory: root.appendingPathComponent("cache"))
        let image = try #require(await cache.artwork(for: url))
        // Preserve AppKit’s existing clockwise rotation for EXIF orientation 6.
        try checkQuadrants(image, rotated: name.hasSuffix("jpg"))
        #expect(try pixel(bitmap(image), x: 75, y: 75).alphaComponent > 0.95)
        await FileMetadataReader.shared.invalidate(url: url)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ArtworkTest-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func replaceArtwork(_ data: Data, at url: URL, using tags: TrackTagService) async throws {
        let before = try await tags.read(url: url)
        let receipt = try await tags.save(trackID: UUID(), baseline: before,
                                         patch: TagPatch(artworkChanged: true, artwork: data))
        try await tags.finishSave(receipt: receipt)
    }

    private func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
        #expect(image.size == NSSize(width: 300, height: 300))
        let rep = try #require(image.representations.compactMap { $0 as? NSBitmapImageRep }.first)
        #expect(rep.pixelsWide == 300 && rep.pixelsHigh == 300)
        return rep
    }

    private func pixel(_ rep: NSBitmapImageRep, x: Int, y: Int) throws -> NSColor {
        try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
    }

    private func checkQuadrants(_ image: NSImage, rotated: Bool = false) throws {
        let rep = try bitmap(image)
        let upperLeft = try pixel(rep, x: rotated ? 225 : 75, y: 75)
        let upperRight = try pixel(rep, x: 225, y: rotated ? 225 : 75)
        let lowerLeft = try pixel(rep, x: 75, y: rotated ? 75 : 225)
        let lowerRight = try pixel(rep, x: rotated ? 75 : 225, y: 225)
        #expect(upperLeft.redComponent > 0.8 && upperLeft.greenComponent < 0.2)
        #expect(upperRight.greenComponent > 0.8 && upperRight.redComponent < 0.2)
        #expect(lowerLeft.blueComponent > 0.8 && lowerLeft.redComponent < 0.2)
        #expect(lowerRight.redComponent > 0.8 && lowerRight.greenComponent > 0.8)
        // The non-square 600×400 source fills the whole square, with no letterboxing.
        #expect(try pixel(rep, x: 150, y: 5).alphaComponent > 0.95)
        #expect(try pixel(rep, x: 295, y: 295).alphaComponent > 0.95)
    }

    private func picture(type: UTType, transparent: Bool = false, blue: Bool = false, orientation: Int = 1) throws -> Data {
        let width = 600, height = 400
        let context = try #require(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let bytes = try #require(context.data).bindMemory(to: UInt8.self, capacity: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let alpha: UInt8 = transparent && x < 60 ? 0 : 255
                bytes[offset] = !blue && ((x < 300 && y < 200) || (x >= 300 && y >= 200)) ? alpha : 0
                bytes[offset + 1] = !blue && x >= 300 ? alpha : 0
                bytes[offset + 2] = blue || (x < 300 && y >= 200) ? alpha : 0
                bytes[offset + 3] = alpha
            }
        }
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()),
            [kCGImagePropertyOrientation: orientation, kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
