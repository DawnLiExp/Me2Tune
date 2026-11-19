import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum TagArtworkImporter {
    static let supportedTypes: [UTType] = [.jpeg, .png, .webP, .heic, .heif, .heics, .gif, .tiff, .bmp]
        + ["avif", "apng"].compactMap { UTType(filenameExtension: $0) }

    @concurrent
    static func load(from url: URL) async throws -> Data {
        let data = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String? else { throw TagEditError.invalidArtwork }
        guard supportedTypes.contains(where: { $0.identifier == type }) else { throw TagEditError.unsupportedArtwork }
        if isStillCover(source) {
            guard canDecodeCover(source) else { throw TagEditError.invalidArtwork }
            return data
        }

        // Image I/O picks the primary HEIF image and index zero for other formats.
        let index = CGImageSourceGetPrimaryImageIndex(source)
        // Omitting a pixel limit renders the full image with its display orientation.
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let image = CGImageSourceCreateThumbnailAtIndex(source, index, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary),
              CGImageSourceGetStatusAtIndex(source, index) == .statusComplete else { throw TagEditError.invalidArtwork }

        // An opaque HEIC or AVIF can still decode into a bitmap with an alpha channel.
        let hasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool == true
        let outputType: UTType = hasAlpha ? .png : .jpeg
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, outputType.identifier as CFString, 1, nil)
        else { throw TagEditError.invalidArtwork }
        let options = hasAlpha ? nil : [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { throw TagEditError.invalidArtwork }
        return output as Data
    }

    static func canEmbed(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return isStillCover(source) && canDecodeCover(source)
    }

    private static func isStillCover(_ source: CGImageSource) -> Bool {
        guard CGImageSourceGetCount(source) == 1, let type = CGImageSourceGetType(source) as String? else { return false }
        return type == UTType.jpeg.identifier || type == UTType.png.identifier
    }

    private static func canDecodeCover(_ source: CGImageSource) -> Bool {
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 256
        ] as CFDictionary) != nil && CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete
    }
}
