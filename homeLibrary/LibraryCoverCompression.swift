//
//  LibraryCoverCompression.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/16.
//

import Foundation
import ImageIO
import UIKit

nonisolated struct LibraryCoverImageSize: Equatable, Sendable {
    let width: Int
    let height: Int

    var longestEdge: Int {
        max(width, height)
    }
}

nonisolated struct LibraryCoverCompressionResult: Equatable, Sendable {
    let data: Data
    let originalSize: LibraryCoverImageSize?
    let outputSize: LibraryCoverImageSize?
    let didCompress: Bool
}

nonisolated struct RepositoryCoverCompressionProgress: Equatable, Sendable {
    enum Phase: String, Equatable, Sendable {
        case running
        case completed
    }

    let phase: Phase
    let totalCount: Int
    let processedCount: Int
    let compressedCount: Int

    var statusText: String {
        switch phase {
        case .running:
            return localized(
                "已处理 %d / %d，已压缩 %d 张图片",
                en: "Processed %d / %d, compressed %d images",
                arguments: [processedCount, totalCount, compressedCount]
            )
        case .completed:
            return localized(
                "整理完成，已压缩 %d / %d 张图片",
                en: "Optimization complete, compressed %d / %d images",
                arguments: [compressedCount, totalCount]
            )
        }
    }
}

nonisolated enum LibraryCoverCompressor {
    nonisolated static let thumbnailMaxPixelSize = 720
    nonisolated static let thumbnailMaxByteCount = 220 * 1024

    nonisolated private static let compressionQualities: [CGFloat] = [0.82, 0.72, 0.62, 0.52, 0.42]

    nonisolated static func compressIfNeeded(
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

        guard let image = makePreparedImage(from: source, maxPixelSize: maxPixelSize) ?? UIImage(data: data) else {
            return LibraryCoverCompressionResult(
                data: data,
                originalSize: originalSize,
                outputSize: originalSize,
                didCompress: false
            )
        }

        let outputSize = LibraryCoverImageSize(
            width: max(1, Int(image.size.width.rounded())),
            height: max(1, Int(image.size.height.rounded()))
        )

        var encodedData: Data?
        for quality in compressionQualities {
            guard let candidate = makeJPEGData(from: image, quality: quality) else {
                continue
            }

            encodedData = candidate
            if candidate.count <= maxByteCount {
                break
            }
        }

        guard let encodedData else {
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
            outputSize: outputSize,
            didCompress: true
        )
    }

    nonisolated private static func imageSize(for source: CGImageSource) -> LibraryCoverImageSize? {
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

    nonisolated private static func makePreparedImage(from source: CGImageSource, maxPixelSize: Int) -> UIImage? {
        let thumbnailOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    nonisolated private static func makeJPEGData(from image: UIImage, quality: CGFloat) -> Data? {
        let targetSize = CGSize(
            width: max(1, image.size.width),
            height: max(1, image.size.height)
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.jpegData(withCompressionQuality: quality) { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
