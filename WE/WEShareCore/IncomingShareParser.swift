import Foundation

enum IncomingShareError: Error, LocalizedError {
    case noSupportedItems
    case tooManyImages
    case invalidURL
    case textTooLong
    case imageTooLarge
    case unsupportedImage
    case corruptImage

    var errorDescription: String? {
        switch self {
        case .noSupportedItems: "Nothing here can be kept in WE."
        case .tooManyImages: "WE can keep up to five photos at a time."
        case .invalidURL: "Only secure HTTPS links without embedded credentials are supported."
        case .textTooLong: "This text is too long to keep safely."
        case .imageTooLarge: "This photo is too large to process in the Share Sheet."
        case .unsupportedImage: "This image format is not supported."
        case .corruptImage: "This image could not be read."
        }
    }
}

/// Nothing survived parsing. The per-item reasons travel with the failure so
/// the Share Sheet can say *why* each thing was left out. A bare "nothing can
/// be kept" would be the one screen in this feature that declines to show its
/// work.
struct IncomingShareRejection: Error, LocalizedError {
    let omissions: [IncomingShareOmission]

    var errorDescription: String? {
        IncomingShareError.noSupportedItems.localizedDescription
    }
}

enum IncomingShareParser {
    static func parse(
        _ candidates: [IncomingShareCandidate],
        vaultID: UUID,
        now: Date = Date()
    ) throws -> IncomingShareDraft {
        var representations: [IncomingShareRepresentation] = []
        var resources: [IncomingShareResource] = []
        var resourceData: [UUID: Data] = [:]
        var omissions: [IncomingShareOmission] = []
        var fingerprints: Set<String> = []
        var imageCount = 0

        for candidate in candidates {
            switch candidate {
            case .omitted(let omission):
                omissions.append(omission)

            case .text(let raw, let label):
                let text = normalisedText(raw)
                guard !text.isEmpty else {
                    omissions.append(.init(label: label, reason: "The text was empty."))
                    continue
                }
                guard text.count <= WEShareConstants.maximumTextCharacters else {
                    omissions.append(.init(label: label, reason: IncomingShareError.textTooLong.localizedDescription))
                    continue
                }
                let fingerprint = "text:\(ShareCrypto.sha256(Data(text.utf8)))"
                guard fingerprints.insert(fingerprint).inserted else {
                    omissions.append(.init(label: label, reason: "A duplicate was left out."))
                    continue
                }
                representations.append(
                    .init(kind: .text, text: text)
                )

            case .webURL(let rawURL, let label):
                guard let url = canonicalHTTPSURL(rawURL) else {
                    omissions.append(.init(label: label, reason: IncomingShareError.invalidURL.localizedDescription))
                    continue
                }
                let fingerprint = "url:\(url.absoluteString)"
                guard fingerprints.insert(fingerprint).inserted else {
                    omissions.append(.init(label: label, reason: "A duplicate link was left out."))
                    continue
                }
                representations.append(
                    .init(kind: .url, url: url)
                )

            case .image(let image, let label):
                guard imageCount < WEShareConstants.maximumImages else {
                    omissions.append(.init(label: label, reason: IncomingShareError.tooManyImages.localizedDescription))
                    continue
                }
                let fingerprint = "image:\(image.sha256)"
                guard fingerprints.insert(fingerprint).inserted else {
                    omissions.append(.init(label: label, reason: "A duplicate photo was left out."))
                    continue
                }
                guard image.data.count <= WEShareConstants.maximumOutputBytes else {
                    omissions.append(.init(label: label, reason: "The normalized photo was still over 8 MB."))
                    continue
                }

                imageCount += 1
                let resourceID = UUID()
                let filename = "\(resourceID.uuidString.lowercased()).sealed"
                resources.append(
                    IncomingShareResource(
                        id: resourceID,
                        kind: .image,
                        sealedFilename: filename,
                        contentType: image.contentType,
                        sha256: image.sha256,
                        byteCount: image.data.count,
                        pixelWidth: image.pixelWidth,
                        pixelHeight: image.pixelHeight
                    )
                )
                resourceData[resourceID] = image.data
                representations.append(
                    .init(kind: .image, resourceID: resourceID)
                )
            }
        }

        guard !representations.isEmpty else {
            throw IncomingShareRejection(omissions: omissions)
        }

        let manifest = IncomingShareManifest(
            vaultID: vaultID,
            createdAt: now,
            titleSuggestion: titleSuggestion(for: representations),
            representations: representations,
            resources: resources,
            omissions: omissions
        )
        return IncomingShareDraft(
            manifest: manifest,
            resourceData: resourceData
        )
    }

    static func canonicalHTTPSURL(_ url: URL) -> URL? {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ),
        components.scheme?.lowercased() == "https",
        let host = components.host?.lowercased(),
        !host.isEmpty,
        components.user == nil,
        components.password == nil
        else { return nil }

        components.scheme = "https"
        components.host = host
        components.fragment = nil
        if components.path.isEmpty { components.path = "/" }
        return components.url
    }

    static func normalisedText(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func titleSuggestion(
        for representations: [IncomingShareRepresentation]
    ) -> String {
        if let text = representations.compactMap(\.text).first,
           let line = text.split(separator: "\n").first {
            return String(line.prefix(80))
        }
        if let host = representations.compactMap(\.url).first?.host {
            return host
        }
        let images = representations.count { $0.kind == .image }
        return images == 1 ? "A photo from elsewhere" : "\(images) photos from elsewhere"
    }
}
