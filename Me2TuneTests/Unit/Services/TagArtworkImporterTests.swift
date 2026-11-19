import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Me2Tune

@Suite("Cover image import")
struct TagArtworkImporterTests {
    static let fixtures = TrackTagServiceTests.fixtures.deletingLastPathComponent().appendingPathComponent("Artwork")

    @Test("Still JPEG and PNG keep their original bytes", arguments: ["cover.jpg", "cover.png"])
    func originalData(_ name: String) async throws {
        let url = TrackTagServiceTests.fixtures.appendingPathComponent(name)
        let original = try Data(contentsOf: url)
        #expect(try await TagArtworkImporter.load(from: url) == original)
    }

    @Test("Opaque source images become full-size JPEG covers", arguments: ["still.bmp", "still.heic", "still.avif"])
    func opaqueImages(_ name: String) async throws {
        let data = try await TagArtworkImporter.load(from: Self.fixtures.appendingPathComponent(name))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 48 && image.height == 32)
    }

    @Test("Transparent WebP keeps both transparent and opaque pixels")
    func transparentCover() async throws {
        let data = try await TagArtworkImporter.load(from: Self.fixtures.appendingPathComponent("transparent.webp"))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
        let rep = try #require(NSBitmapImageRep(data: data))
        #expect(try #require(rep.colorAt(x: 4, y: 16)).alphaComponent == 0)
        #expect(try #require(rep.colorAt(x: 24, y: 16)).alphaComponent == 1)
    }

    @Test("Animation frame or TIFF page becomes a single oriented image",
          arguments: ["animated.gif", "animated.webp", "animated.apng", "pages.tiff"])
    func firstPicture(_ name: String) async throws {
        let data = try await TagArtworkImporter.load(from: Self.fixtures.appendingPathComponent(name))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetCount(source) == 1)
        let rep = try #require(NSBitmapImageRep(data: data))
        let rotated = name == "pages.tiff"
        #expect(rep.pixelsWide == (rotated ? 32 : 48))
        #expect(rep.pixelsHigh == (rotated ? 48 : 32))
        let center = try #require(rep.colorAt(x: 24, y: 16)?.usingColorSpace(.sRGB))
        #expect(center.redComponent > 0.7 && center.blueComponent < 0.3)
        let stripe = try #require(rep.colorAt(x: rotated ? 16 : 4, y: rotated ? 4 : 16)?.usingColorSpace(.sRGB))
        #expect(stripe.greenComponent > 0.6 && stripe.redComponent < 0.3)
    }
}
