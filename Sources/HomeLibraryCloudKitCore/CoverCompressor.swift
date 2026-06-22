import AppKit
import Foundation
import ImageIO

public struct LibraryCoverImageSize: Equatable, Codable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var longestEdge: Int {
        max(width, height)
    }
}

public struct LibraryCoverCompressionResult: Equatable, Sendable {
    public let data: Data
    public let originalSize: LibraryCoverImageSize?
    public let outputSize: LibraryCoverImageSize?
    public let didCompress: Bool

    public init(data: Data, originalSize: LibraryCoverImageSize?, outputSize: LibraryCoverImageSize?, didCompress: Bool) {
        self.data = data
        self.originalSize = originalSize
        self.outputSize = outputSize
        self.didCompress = didCompress
    }
}

public enum LibraryCoverCompressor {
    public static let thumbnailMaxPixelSize = 720
    public static let thumbnailMaxByteCount = 220 * 1024

    private static let compressionQualities: [CGFloat] = [0.82, 0.72, 0.62, 0.52, 0.42]

    public static func inspect(_ data: Data) -> LibraryCoverImageSize? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return imageSize(for: source)
    }

    public static func canDecode(_ data: Data) -> Bool {
        inspect(data) != nil
    }

    public static func compressIfNeeded(
        _ data: Data,
        maxPixelSize: Int = thumbnailMaxPixelSize,
        maxByteCount: Int = thumbnailMaxByteCount
    ) -> LibraryCoverCompressionResult {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return LibraryCoverCompressionResult(
                data: data,
                originalSize: nil,
                outputSize: nil,
                didCompress: false
            )
        }

        let originalSize = imageSize(for: source)
        let needsResize = (originalSize?.longestEdge ?? 0) > maxPixelSize
        let needsReencode = data.count > maxByteCount

        guard needsResize || needsReencode else {
            return LibraryCoverCompressionResult(
                data: data,
                originalSize: originalSize,
                outputSize: originalSize,
                didCompress: false
            )
        }

        guard let cgImage = makePreparedImage(from: source, maxPixelSize: maxPixelSize),
              let encodedData = makeCompressedJPEGData(from: cgImage, maxByteCount: maxByteCount) else {
            return LibraryCoverCompressionResult(
                data: data,
                originalSize: originalSize,
                outputSize: originalSize,
                didCompress: false
            )
        }

        if encodedData == data || (!needsResize && encodedData.count >= data.count) {
            return LibraryCoverCompressionResult(
                data: data,
                originalSize: originalSize,
                outputSize: originalSize,
                didCompress: false
            )
        }

        return LibraryCoverCompressionResult(
            data: encodedData,
            originalSize: originalSize,
            outputSize: LibraryCoverImageSize(width: cgImage.width, height: cgImage.height),
            didCompress: true
        )
    }

    private static func imageSize(for source: CGImageSource) -> LibraryCoverImageSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }

        let widthValue = properties[kCGImagePropertyPixelWidth] as? NSNumber
        let heightValue = properties[kCGImagePropertyPixelHeight] as? NSNumber

        guard let width = widthValue?.intValue,
              let height = heightValue?.intValue,
              width > 0,
              height > 0 else {
            return nil
        }

        return LibraryCoverImageSize(width: width, height: height)
    }

    private static func makePreparedImage(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let thumbnailOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
    }

    private static func makeCompressedJPEGData(from cgImage: CGImage, maxByteCount: Int) -> Data? {
        let width = max(1, cgImage.width)
        let height = max(1, cgImage.height)
        let image = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()

        var encodedData: Data?
        for quality in compressionQualities {
            guard let candidate = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
                continue
            }

            encodedData = candidate
            if candidate.count <= maxByteCount {
                break
            }
        }

        return encodedData
    }
}
