//
//  FieldLinkReader.swift
//  WE
//
//  Reads a pasted link for the + card: its title, its site, a picture.
//
//  The read happens on this phone, through LinkPresentation — the same thing
//  Messages does when a link is pasted. Nothing about the link goes to WE's
//  servers until it is sent, and then only as the item it becomes. A read
//  that fails or takes too long is not an error: the link is still kept,
//  titled by its address, because a slow website is not a reason to lose
//  what somebody meant to save.
//

import LinkPresentation
import SwiftUI
import UIKit

@MainActor
@Observable
final class FieldLinkReader {
    enum Phase: Equatable {
        case reading
        case read(title: String?, image: UIImage?)
    }

    let url: URL
    private(set) var phase: Phase = .reading
    private var provider: LPMetadataProvider?

    init(url: URL) {
        self.url = url
    }

    /// "muji.us", without the "www."
    var site: String {
        let host = url.host() ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var title: String? {
        if case .read(let title, _) = phase { return title }
        return nil
    }

    var image: UIImage? {
        if case .read(_, let image) = phase { return image }
        return nil
    }

    /// The words to file when nothing was typed: the page's own title, or
    /// the address when there is none.
    var fallbackWords: String {
        title ?? FieldConversationLinks.title(url)
    }

    func read() async {
        let provider = LPMetadataProvider()
        provider.timeout = 8
        self.provider = provider
        do {
            let metadata = try await provider.startFetchingMetadata(for: url)
            let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let image = await Self.image(from: metadata.imageProvider ?? metadata.iconProvider)
            phase = .read(title: title?.isEmpty == false ? title : nil, image: image)
        } catch {
            phase = .read(title: nil, image: nil)
        }
    }

    func cancel() {
        provider?.cancel()
    }

    private static func image(from provider: NSItemProvider?) async -> UIImage? {
        guard let provider, provider.canLoadObject(ofClass: UIImage.self) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }

    /// Where a link goes when its site says so plainly.
    ///
    /// Additive: the words are still classified first, and this only speaks
    /// for a site whose kind is not in doubt. A page title reads to the
    /// classifier like a film ("AirPods Pro 3" is title-cased and short), so
    /// without this a product page lands in Watchlist. An unknown site
    /// returns nil and the words decide, as they always have.
    static func category(for url: URL) -> LifeCategory? {
        let host = (url.host() ?? "").lowercased()
        let path = url.path.lowercased()
        func on(_ domains: [String]) -> Bool {
            domains.contains { host == $0 || host.hasSuffix("." + $0) }
        }
        if on(["imdb.com", "letterboxd.com", "netflix.com", "hulu.com", "max.com",
               "disneyplus.com", "primevideo.com", "tv.apple.com", "rottentomatoes.com",
               "justwatch.com", "goodreads.com"]) { return .watchlist }
        if on(["airbnb.com", "booking.com", "hotels.com", "expedia.com", "vrbo.com", "kayak.com"]) {
            return .trips
        }
        if on(["cooking.nytimes.com", "allrecipes.com", "bonappetit.com", "seriouseats.com",
               "epicurious.com", "food52.com", "resy.com", "opentable.com", "yelp.com"])
            || path.contains("/recipe") { return .food }
        if on(["amazon.com", "amzn.to", "etsy.com", "target.com", "walmart.com", "ikea.com",
               "apple.com", "bestbuy.com", "wayfair.com", "muji.us", "muji.com", "costco.com",
               "crateandbarrel.com", "potterybarn.com", "westelm.com", "uniqlo.com"])
            || ["/dp/", "/product", "/products/", "/shop/", "/buy/", "/p/"].contains(where: path.contains) {
            return .buys
        }
        return nil
    }

    /// The first web link in some text, if there is one.
    static func firstLink(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range)
            .compactMap(\.url)
            .first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
    }
}
