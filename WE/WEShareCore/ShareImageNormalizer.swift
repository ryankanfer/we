import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ShareImageNormalizer: Sendable {
    private let acceptedTypes: Set<String> = [
        UTType.heic.identifier,
        UTType.heif.identifier,
        UTType.jpeg.identifier,
        UTType.png.identifier,
        UTType.gif.identifier,
        UTType.webP.identifier,
    ]

    func normalize(fileAt url: URL) throws -> NormalizedShareImage {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let sourceBytes = values.fileSize,
              sourceBytes <= WEShareConstants.maximumSourceBytes
        else { throw IncomingShareError.imageTooLarge }

        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw IncomingShareError.corruptImage
        }

        guard let type = CGImageSourceGetType(source) as String?,
              acceptedTypes.contains(type)
        else {
            throw IncomingShareError.unsupportedImage
        }

        var dimension = WEShareConstants.maximumOutputDimension
        while dimension >= 720 {
            guard let image = thumbnail(from: source, maximumDimension: dimension)
            else { throw IncomingShareError.corruptImage }

            let hasAlpha = image.hasUsefulAlpha
            let contentType = hasAlpha
                ? UTType.png.identifier
                : UTType.jpeg.identifier
            if let encoded = encode(image, hasAlpha: hasAlpha),
               encoded.count <= WEShareConstants.maximumOutputBytes {
                return NormalizedShareImage(
                    data: encoded,
                    contentType: contentType,
                    pixelWidth: image.width,
                    pixelHeight: image.height,
                    sha256: ShareCrypto.sha256(encoded)
                )
            }
            dimension = Int(Double(dimension) * 0.8)
        }

        throw IncomingShareError.imageTooLarge
    }

    private func thumbnail(
        from source: CGImageSource,
        maximumDimension: Int
    ) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary
        )
    }

    private func encode(_ image: CGImage, hasAlpha: Bool) -> Data? {
        if hasAlpha {
            return destinationData(
                image,
                type: UTType.png.identifier,
                properties: [:]
            )
        }

        for quality in stride(from: 0.9, through: 0.55, by: -0.1) {
            guard let encoded = destinationData(
                image,
                type: UTType.jpeg.identifier,
                properties: [
                    kCGImageDestinationLossyCompressionQuality: quality
                ]
            ),
            let data = stripJPEGMetadata(encoded)
            else { continue }
            if data.count <= WEShareConstants.maximumOutputBytes {
                return data
            }
        }
        return nil
    }

    private func destinationData(
        _ image: CGImage,
        type: String,
        properties: [CFString: Any]
    ) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            type as CFString,
            1,
            nil
        ) else { return nil }
        // Supplying only encoding properties deliberately drops every source
        // metadata dictionary, including EXIF, GPS, IPTC and XMP.
        CGImageDestinationAddImage(
            destination,
            image,
            properties as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// ImageIO may add a small technical EXIF block even when no source
    /// properties are supplied. Remove JPEG metadata marker segments after
    /// the fresh encode so the output contains pixels and encoding structure,
    /// not EXIF, XMP, IPTC, comments, captions, or filenames.
    private func stripJPEGMetadata(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8
        else { return nil }

        var output = Data(bytes[0...1])
        var index = 2

        while index < bytes.count {
            guard bytes[index] == 0xFF else { return nil }
            let markerStart = index
            while index < bytes.count, bytes[index] == 0xFF {
                index += 1
            }
            guard index < bytes.count else { return nil }
            let marker = bytes[index]
            index += 1

            if marker == 0xDA {
                output.append(contentsOf: bytes[markerStart...])
                return output
            }
            if marker == 0xD9 {
                output.append(contentsOf: bytes[markerStart..<index])
                return output
            }
            if marker == 0x01 || (0xD0...0xD7).contains(marker) {
                output.append(contentsOf: bytes[markerStart..<index])
                continue
            }

            guard index + 1 < bytes.count else { return nil }
            let length = Int(bytes[index]) << 8 | Int(bytes[index + 1])
            guard length >= 2, index + length <= bytes.count else {
                return nil
            }
            let segmentEnd = index + length
            let isMetadata = (0xE1...0xEF).contains(marker)
                || marker == 0xFE
            if !isMetadata {
                output.append(
                    contentsOf: bytes[markerStart..<segmentEnd]
                )
            }
            index = segmentEnd
        }

        return nil
    }
}

private extension CGImage {
    var hasUsefulAlpha: Bool {
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            true
        case .none, .noneSkipFirst, .noneSkipLast, .alphaOnly:
            false
        @unknown default:
            false
        }
    }
}
