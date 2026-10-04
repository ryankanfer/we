//
//  FieldPreviewImage.swift
//  WE
//
//  The picture for a kept link, on Today.
//
//  The only permitted source is the page the item arrived as, read on this
//  phone through LinkPresentation exactly as the + card reads it. An item
//  with no link has no picture, and nothing is ever looked up by title: a
//  restaurant nobody chose must not get a photograph of one.
//
//  Cached twice. In memory for the life of the app, and on disk in Caches as
//  a small JPEG keyed by the address, so a redraw or a relaunch never reads
//  the network for a picture it already has. A failed read is remembered for
//  the session too, so a dead link costs one attempt, not one per frame.
//

import LinkPresentation
import SwiftUI
import UIKit

@MainActor
@Observable
final class FieldPreviewImages {
    static let shared = FieldPreviewImages()

    enum Phase: Equatable {
        case loading
        case loaded(UIImage)
        case unavailable
    }

    private(set) var phases: [URL: Phase] = [:]
    @ObservationIgnored private var inFlight: Set<URL> = []
    /// Pictures found on disk. Kept outside observation because it is
    /// filled while a view is being drawn, and writing observed state there
    /// would ask for another draw.
    @ObservationIgnored private var fromDisk: [URL: UIImage] = [:]
    @ObservationIgnored private var missingOnDisk: Set<URL> = []

    /// What is known right now, without starting anything.
    func phase(for url: URL) -> Phase? {
        if let phase = phases[url] { return phase }
        if let image = fromDisk[url] { return .loaded(image) }
        guard !missingOnDisk.contains(url) else { return nil }
        if let image = Self.readDisk(url) {
            fromDisk[url] = image
            return .loaded(image)
        }
        missingOnDisk.insert(url)
        return nil
    }

    func load(_ url: URL) async {
        if let phase = phase(for: url), phase != .loading { return }
        guard !inFlight.contains(url) else { return }
        inFlight.insert(url)
        phases[url] = .loading
        defer { inFlight.remove(url) }

        let provider = LPMetadataProvider()
        provider.timeout = 8
        guard let metadata = try? await provider.startFetchingMetadata(for: url),
              let itemProvider = metadata.imageProvider,
              let image = await Self.image(from: itemProvider)
        else {
            phases[url] = .unavailable
            return
        }
        let small = Self.downscaled(image, maxSide: 1200)
        phases[url] = .loaded(small)
        Self.writeDisk(small, for: url)
    }

    // MARK: Disk

    private static var directory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TodayPreviews", isDirectory: true)
    }

    private static func file(for url: URL) -> URL? {
        // A stable, filesystem safe name. Not a security boundary, only a key.
        let key = url.absoluteString.utf8.reduce(into: UInt64(14_695_981_039_346_656_037)) { hash, byte in
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return directory?.appendingPathComponent(String(key, radix: 36) + ".jpg")
    }

    private static func readDisk(_ url: URL) -> UIImage? {
        guard let file = file(for: url), let data = try? Data(contentsOf: file) else { return nil }
        return UIImage(data: data)
    }

    private static func writeDisk(_ image: UIImage, for url: URL) {
        guard let directory, let file = file(for: url),
              let data = image.jpegData(compressionQuality: 0.8)
        else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    private static func image(from provider: NSItemProvider) async -> UIImage? {
        guard provider.canLoadObject(ofClass: UIImage.self) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }

    private static func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide, longest > 0 else { return image }
        let scale = maxSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// A picture in a frame whose size is decided before the picture arrives,
/// so nothing below it moves. While loading, and if it never comes, the
/// frame holds the site's name in small capitals: an intentional plate, not
/// a broken image.
struct FieldPreviewPlate: View {
    let url: URL
    var aspect: CGFloat = 4 / 3
    var cornerRadius: CGFloat = 4
    /// Small plates say nothing; there is no room for a site name.
    var showsSite = true

    @Environment(\.weCanvas) private var canvas
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var images: FieldPreviewImages { .shared }

    var body: some View {
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                switch images.phase(for: url) {
                case .loaded(let image):
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                default:
                    plate
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: images.phase(for: url))
            .task(id: url) { await images.load(url) }
            .accessibilityHidden(true)
    }

    private var plate: some View {
        ZStack {
            canvas.ink.opacity(0.05)
            if showsSite {
                Text(site.uppercased())
                    .font(FieldType.dateCount)
                    .tracking(FieldTracking.dateCount)
                    .foregroundStyle(.fieldInk(.legend))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
            }
        }
    }

    private var site: String {
        let host = url.host() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
