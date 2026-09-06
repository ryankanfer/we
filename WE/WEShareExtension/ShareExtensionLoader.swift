import Foundation
import UniformTypeIdentifiers

enum ShareExtensionLoader {
    static func candidates(
        from context: NSExtensionContext
    ) async -> [IncomingShareCandidate] {
        let providers = (context.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        var results: [IncomingShareCandidate] = []

        for (index, provider) in providers.enumerated() {
            let label = "Item \(index + 1)"
            results.append(await candidate(from: provider, label: label))
        }
        return results
    }

    private static func candidate(
        from provider: NSItemProvider,
        label: String
    ) async -> IncomingShareCandidate {
        var fallbackReason: String?

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = await loadURL(provider) {
            if url.isFileURL {
                // A photo frequently advertises its temporary file URL as a
                // URL. That is transport, not the representation.
                switch normalizeImage(fileAt: url) {
                case .success(let image):
                    return .image(image, label: label)
                case .failure(let error):
                    fallbackReason = error.localizedDescription
                }
            } else if IncomingShareParser.canonicalHTTPSURL(url) != nil {
                return .webURL(url, label: label)
            } else {
                // An invalid URL representation does not hide a valid image or
                // text representation supplied by the same provider.
                fallbackReason =
                    IncomingShareError.invalidURL.localizedDescription
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            let result = await loadImage(provider)
            switch result {
            case .success(let image):
                return .image(image, label: label)
            case .failure(let error):
                fallbackReason = error.localizedDescription
            }
        }

        if provider.hasItemConformingToTypeIdentifier(
            UTType.plainText.identifier
        ),
        let text = await loadText(provider) {
            return .text(text, label: label)
        }

        return .omitted(
            .init(
                label: label,
                reason: fallbackReason
                    ?? "This kind of item is not supported."
            )
        )
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(
                forTypeIdentifier: UTType.url.identifier,
                options: nil
            ) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let url = item as? NSURL {
                    continuation.resume(returning: url as URL)
                } else if let string = item as? String {
                    continuation.resume(returning: URL(string: string))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(
                forTypeIdentifier: UTType.plainText.identifier,
                options: nil
            ) { item, _ in
                if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let text = item as? NSString {
                    continuation.resume(returning: text as String)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadImage(
        _ provider: NSItemProvider
    ) async -> Result<NormalizedShareImage, Error> {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(
                forTypeIdentifier: UTType.image.identifier
            ) { url, error in
                guard let url else {
                    continuation.resume(
                        returning: .failure(
                            error ?? IncomingShareError.corruptImage
                        )
                    )
                    return
                }
                continuation.resume(returning: normalizeImage(fileAt: url))
            }
        }
    }

    private static func normalizeImage(
        fileAt url: URL
    ) -> Result<NormalizedShareImage, Error> {
        autoreleasepool {
            Result {
                try ShareImageNormalizer().normalize(fileAt: url)
            }
        }
    }
}
