import Foundation
import AppKit

final class FaviconService {
    static let shared = FaviconService()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 256
    }

    func fetchFavicon(primary: String?, secondary: String?) async -> NSImage? {
        if let host = primary, let img = await fetchHost(host) { return img }
        if let host = secondary, let img = await fetchHost(host) { return img }
        return nil
    }

    private func fetchHost(_ host: String) async -> NSImage? {
        let key = host as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        // Try site favicon first
        if let img1 = await requestURL(buildSiteFaviconURL(for: host)) {
            cache.setObject(img1, forKey: key)
            return img1
        }
        // Fallback to Google S2 aggregator
        if let img2 = await requestURL(buildS2URL(for: host)) {
            cache.setObject(img2, forKey: key)
            return img2
        }
        return nil
    }

    private func buildS2URL(for host: String) -> URL? {
        var comps = URLComponents(string: "https://www.google.com/s2/favicons")
        comps?.queryItems = [
            URLQueryItem(name: "domain", value: host),
            URLQueryItem(name: "sz", value: "64")
        ]
        return comps?.url
    }

    private func buildSiteFaviconURL(for host: String) -> URL? {
        return URL(string: "https://\(host)/favicon.ico")
    }

    private func requestURL(_ url: URL?) async -> NSImage? {
        guard let url = url else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 6
        let session = URLSession(configuration: config)
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else { return nil }
            if let img = NSImage(data: data), img.size.width > 0, img.size.height > 0 {
                return img
            }
        } catch {
            return nil
        }
        return nil
    }
}
