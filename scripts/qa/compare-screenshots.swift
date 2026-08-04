#!/usr/bin/swift

import AppKit
import CoreImage
import Foundation

private struct GoldenAttachment {
    let name: String
    let fileURL: URL
}

private struct PixelImage {
    let width: Int
    let height: Int
    let bytes: [UInt8]
}

private enum ComparisonError: LocalizedError {
    case usage
    case missingManifest(URL)
    case malformedManifest(URL)
    case noGoldenAttachments
    case missingExport(String)
    case missingReference(URL)
    case unreadableImage(URL)
    case incompatibleImages(String, PixelImage, PixelImage)

    var errorDescription: String? {
        switch self {
        case .usage:
            return """
            usage: compare-screenshots.swift \
              <exported-attachments> <reference-root> <diff-output>
            """
        case let .missingManifest(url):
            return "Attachment manifest is missing: \(url.path)"
        case let .malformedManifest(url):
            return "Attachment manifest is malformed: \(url.path)"
        case .noGoldenAttachments:
            return "No attachments whose names begin with 'golden.' were exported."
        case let .missingExport(name):
            return "The manifest references a missing exported attachment: \(name)"
        case let .missingReference(url):
            return "Golden reference is missing: \(url.path)"
        case let .unreadableImage(url):
            return "Unable to decode PNG pixels: \(url.path)"
        case let .incompatibleImages(name, actual, reference):
            return """
            \(name) changed dimensions: \
            actual \(actual.width)x\(actual.height), \
            reference \(reference.width)x\(reference.height)
            """
        }
    }
}

private func attachmentName(in dictionary: [String: Any]) -> String? {
    for key in [
        "name",
        "suggestedName",
        "attachmentName",
        "suggestedHumanReadableName",
    ] {
        if let value = dictionary[key] as? String, value.hasPrefix("golden.") {
            let extensionless = (value as NSString).deletingPathExtension
            let components = extensionless.split(
                separator: "_",
                omittingEmptySubsequences: false
            )
            if components.count >= 3,
               Int(components[components.count - 2]) != nil,
               UUID(uuidString: String(components.last!)) != nil {
                return components.dropLast(2).joined(separator: "_")
            }
            return extensionless
        }
    }
    return nil
}

private func exportedFileName(in dictionary: [String: Any]) -> String? {
    for key in ["exportedFileName", "fileName", "filename"] {
        if let value = dictionary[key] as? String, !value.isEmpty {
            return value
        }
    }
    return nil
}

private func collectAttachments(
    from value: Any,
    exportedRoot: URL,
    into result: inout [GoldenAttachment]
) {
    if let dictionary = value as? [String: Any] {
        if let name = attachmentName(in: dictionary),
           let fileName = exportedFileName(in: dictionary) {
            result.append(
                GoldenAttachment(
                    name: name,
                    fileURL: exportedRoot.appendingPathComponent(fileName)
                )
            )
        }
        for nestedValue in dictionary.values {
            collectAttachments(
                from: nestedValue,
                exportedRoot: exportedRoot,
                into: &result
            )
        }
    } else if let array = value as? [Any] {
        for nestedValue in array {
            collectAttachments(
                from: nestedValue,
                exportedRoot: exportedRoot,
                into: &result
            )
        }
    }
}

private func loadPixelImage(from url: URL) throws -> PixelImage {
    guard let image = CIImage(contentsOf: url, options: [
        .applyOrientationProperty: true,
    ]) else {
        throw ComparisonError.unreadableImage(url)
    }

    let extent = image.extent.integral
    let width = Int(extent.width)
    let height = Int(extent.height)
    guard width > 0, height > 0 else {
        throw ComparisonError.unreadableImage(url)
    }

    let rowBytes = width * 4
    var pixels = [UInt8](repeating: 0, count: rowBytes * height)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    CIContext(options: [.cacheIntermediates: false]).render(
        image,
        toBitmap: &pixels,
        rowBytes: rowBytes,
        bounds: extent,
        format: .RGBA8,
        colorSpace: colorSpace
    )
    return PixelImage(width: width, height: height, bytes: pixels)
}

private func writeDiff(
    _ bytes: [UInt8],
    width: Int,
    height: Int,
    to url: URL
) throws {
    let data = Data(bytes)
    guard let provider = CGDataProvider(data: data as CFData),
          let image = CGImage(
              width: width,
              height: height,
              bitsPerComponent: 8,
              bitsPerPixel: 32,
              bytesPerRow: width * 4,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGBitmapInfo(
                  rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              provider: provider,
              decode: nil,
              shouldInterpolate: false,
              intent: .defaultIntent
          ),
          let png = NSBitmapImageRep(cgImage: image)
              .representation(using: .png, properties: [:]) else {
        throw ComparisonError.unreadableImage(url)
    }
    try png.write(to: url, options: .atomic)
}

private func normalizedPNGName(_ attachmentName: String) -> String {
    attachmentName.lowercased().hasSuffix(".png")
        ? attachmentName
        : "\(attachmentName).png"
}

do {
    guard CommandLine.arguments.count == 4 else {
        throw ComparisonError.usage
    }

    let fileManager = FileManager.default
    let exportedRoot = URL(
        fileURLWithPath: CommandLine.arguments[1],
        isDirectory: true
    )
    let referenceRoot = URL(
        fileURLWithPath: CommandLine.arguments[2],
        isDirectory: true
    )
    let diffRoot = URL(
        fileURLWithPath: CommandLine.arguments[3],
        isDirectory: true
    )
    let manifestURL = exportedRoot.appendingPathComponent("manifest.json")

    guard fileManager.fileExists(atPath: manifestURL.path) else {
        throw ComparisonError.missingManifest(manifestURL)
    }

    let manifestData = try Data(contentsOf: manifestURL)
    let manifest = try JSONSerialization.jsonObject(with: manifestData)
    guard manifest is [Any] || manifest is [String: Any] else {
        throw ComparisonError.malformedManifest(manifestURL)
    }

    var attachments: [GoldenAttachment] = []
    collectAttachments(
        from: manifest,
        exportedRoot: exportedRoot,
        into: &attachments
    )
    guard !attachments.isEmpty else {
        throw ComparisonError.noGoldenAttachments
    }

    try fileManager.createDirectory(
        at: diffRoot,
        withIntermediateDirectories: true
    )

    let channelTolerance = UInt8(
        ProcessInfo.processInfo.environment["WE_QA_MAX_CHANNEL_DELTA"]
            .flatMap(Int.init)
            .map { min(max($0, 0), 255) } ?? 8
    )
    let mismatchTolerance = min(
        max(
            ProcessInfo.processInfo.environment["WE_QA_MAX_MISMATCH_RATIO"]
                .flatMap(Double.init) ?? 0.001,
            0
        ),
        1
    )

    var failures: [String] = []
    var seenNames = Set<String>()

    for attachment in attachments.sorted(by: { $0.name < $1.name }) {
        guard seenNames.insert(attachment.name).inserted else {
            failures.append("\(attachment.name): duplicate attachment name")
            continue
        }
        guard fileManager.fileExists(atPath: attachment.fileURL.path) else {
            throw ComparisonError.missingExport(
                attachment.fileURL.lastPathComponent
            )
        }

        let pngName = normalizedPNGName(attachment.name)
        let referenceURL = referenceRoot.appendingPathComponent(pngName)
        guard fileManager.fileExists(atPath: referenceURL.path) else {
            throw ComparisonError.missingReference(referenceURL)
        }

        let actual = try loadPixelImage(from: attachment.fileURL)
        let reference = try loadPixelImage(from: referenceURL)
        guard actual.width == reference.width,
              actual.height == reference.height else {
            throw ComparisonError.incompatibleImages(
                attachment.name,
                actual,
                reference
            )
        }

        var mismatchedPixels = 0
        var largestChannelDelta = 0
        var diffBytes = [UInt8](
            repeating: 0,
            count: actual.bytes.count
        )

        for pixelOffset in stride(
            from: 0,
            to: actual.bytes.count,
            by: 4
        ) {
            var pixelMismatch = false
            for channelOffset in 0..<4 {
                let actualValue = Int(actual.bytes[pixelOffset + channelOffset])
                let referenceValue =
                    Int(reference.bytes[pixelOffset + channelOffset])
                let delta = abs(actualValue - referenceValue)
                largestChannelDelta = max(largestChannelDelta, delta)
                if delta > Int(channelTolerance) {
                    pixelMismatch = true
                }
            }

            if pixelMismatch {
                mismatchedPixels += 1
                diffBytes[pixelOffset] = 255
                diffBytes[pixelOffset + 1] = 0
                diffBytes[pixelOffset + 2] = 255
                diffBytes[pixelOffset + 3] = 255
            } else {
                let luminance = UInt8(
                    (
                        Int(reference.bytes[pixelOffset])
                            + Int(reference.bytes[pixelOffset + 1])
                            + Int(reference.bytes[pixelOffset + 2])
                    ) / 3
                )
                diffBytes[pixelOffset] = luminance
                diffBytes[pixelOffset + 1] = luminance
                diffBytes[pixelOffset + 2] = luminance
                diffBytes[pixelOffset + 3] = 255
            }
        }

        let totalPixels = actual.width * actual.height
        let mismatchRatio = Double(mismatchedPixels) / Double(totalPixels)
        let percentage = mismatchRatio * 100
        let diffURL = diffRoot.appendingPathComponent(pngName)

        try writeDiff(
            diffBytes,
            width: actual.width,
            height: actual.height,
            to: diffURL
        )

        let result = String(
            format: "%.4f%% changed, max channel delta %d",
            percentage,
            largestChannelDelta
        )
        if mismatchRatio > mismatchTolerance {
            failures.append("\(attachment.name): \(result)")
            print("FAIL \(attachment.name): \(result)")
        } else {
            print("PASS \(attachment.name): \(result)")
        }
    }

    let referenceNames = try Set(
        fileManager.contentsOfDirectory(
            at: referenceRoot,
            includingPropertiesForKeys: nil
        )
        .map(\.lastPathComponent)
        .filter {
            $0.hasPrefix("golden.") && $0.lowercased().hasSuffix(".png")
        }
    )
    let actualNames = Set(seenNames.map(normalizedPNGName))
    for missingName in referenceNames.subtracting(actualNames).sorted() {
        failures.append("\(missingName): no matching XCTest attachment")
    }

    if !failures.isEmpty {
        fputs(
            """
            \nGolden screenshot contract failed:
            \(failures.map { "- \($0)" }.joined(separator: "\n"))

            """,
            stderr
        )
        exit(1)
    }

    print(
        "Compared \(attachments.count) golden screenshots against "
            + referenceRoot.path
    )
} catch {
    fputs("Golden screenshot comparison failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
