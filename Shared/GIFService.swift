import Foundation

final class GIFService {
    static let shared = GIFService()

    enum Provider: String, CaseIterable {
        case tenor, giphy
        var title: String { self == .tenor ? "Tenor" : "GIPHY" }
    }

    private let defaults = UserDefaults.standard

    var provider: Provider {
        get { Provider(rawValue: defaults.string(forKey: "milazy.gif.provider") ?? "") ?? .tenor }
        set { defaults.set(newValue.rawValue, forKey: "milazy.gif.provider") }
    }

    func key(for provider: Provider) -> String? {
        defaults.string(forKey: "milazy.gif.key.\(provider.rawValue)")
    }

    func saveKey(_ value: String, for provider: Provider) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: "milazy.gif.key.\(provider.rawValue)")
        } else {
            defaults.set(trimmed, forKey: "milazy.gif.key.\(provider.rawValue)")
        }
    }

    var hasKey: Bool { key(for: provider) != nil }

    func firstGIFData(query: String) async -> Data? {
        guard let apiKey = key(for: provider),
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        do {
            let gifURL: URL?
            switch provider {
            case .tenor:
                var parts = URLComponents(string: "https://tenor.googleapis.com/v2/search")!
                parts.queryItems = [
                    .init(name: "q", value: query),
                    .init(name: "key", value: apiKey),
                    .init(name: "client_key", value: "milazy_keyboard"),
                    .init(name: "limit", value: "1"),
                    .init(name: "media_filter", value: "gif")
                ]
                guard let url = parts.url else { return nil }
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]],
                      let first = results.first,
                      let media = first["media_formats"] as? [String: Any],
                      let gif = media["gif"] as? [String: Any],
                      let raw = gif["url"] as? String else { return nil }
                gifURL = URL(string: raw)

            case .giphy:
                var parts = URLComponents(string: "https://api.giphy.com/v1/gifs/search")!
                parts.queryItems = [
                    .init(name: "api_key", value: apiKey),
                    .init(name: "q", value: query),
                    .init(name: "limit", value: "1"),
                    .init(name: "rating", value: "pg-13")
                ]
                guard let url = parts.url else { return nil }
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["data"] as? [[String: Any]],
                      let first = results.first,
                      let images = first["images"] as? [String: Any],
                      let original = images["original"] as? [String: Any],
                      let raw = original["url"] as? String else { return nil }
                gifURL = URL(string: raw)
            }

            guard let gifURL else { return nil }
            let (gifData, response) = try await URLSession.shared.data(from: gifURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return gifData
        } catch {
            return nil
        }
    }

    private init() {}
}
