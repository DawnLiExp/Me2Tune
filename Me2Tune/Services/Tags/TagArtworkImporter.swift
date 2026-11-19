import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum TagArtworkImporter {
    static let supportedTypes: [UTType] = [.jpeg, .png]

    @concurrent
    static func load(from url: URL) async throws -> Data {
        let data = try Data(contentsOf: url)
        guard canEmbed(data) else { throw TagEditError.invalidArtwork }
        return data
    }

    static func canEmbed(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source) as String?,
              type == UTType.jpeg.identifier || type == UTType.png.identifier else { return false }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 256
        ] as CFDictionary) != nil
    }
}
