import Foundation
import ImageIO

nonisolated enum PocketThumbnail {
    /// ImageIO's synchronous disk/decode work must not compete with pocket transitions.
    @concurrent static func decode(_ url: URL) async -> CGImage? {
        guard !Task.isCancelled, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 320,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
}
