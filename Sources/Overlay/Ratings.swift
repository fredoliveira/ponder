import AppKit
import Foundation

struct CardRating: Decodable {
    let name: String
    let mtga_id: Int?
    let color: String
    let rarity: String
    let url: String
    let types: [String]?
    let avg_seen: Double?
    let ever_drawn_game_count: Int?
    /// GIH WR; null when 17Lands' sample is too small.
    let ever_drawn_win_rate: Double?
}

struct RatingSet {
    let byId: [Int: CardRating]
    /// Format the data is actually for (may differ from the draft's when that had no data).
    let format: String
    let mean: Double
    let sd: Double

    init(cards: [CardRating], format: String) {
        self.format = format
        byId = Dictionary(cards.compactMap { c in c.mtga_id.map { ($0, c) } }, uniquingKeysWith: { a, _ in a })
        let rates = cards.compactMap(\.ever_drawn_win_rate)
        let mean = rates.isEmpty ? 0.55 : rates.reduce(0, +) / Double(rates.count)
        let variance = rates.isEmpty ? 0 : rates.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(rates.count)
        self.mean = mean
        self.sd = max(variance.squareRoot(), 0.005)
    }

    var hasData: Bool { byId.values.contains { $0.ever_drawn_win_rate != nil } }
}

enum Cache {
    static let dir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("mtg-overlay")
        try? FileManager.default.createDirectory(
            at: dir.appendingPathComponent("img"), withIntermediateDirectories: true)
        return dir
    }()

    static func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("mtg-overlay (personal tool)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }
}

/// 17Lands card ratings: one request per set and format, cached (in memory and on disk) for
/// 3 hours. 17Lands' numbers move fast in a set's first weeks, and the app runs for days.
actor RatingsStore {
    static let shared = RatingsStore()
    private var memory: [String: (set: RatingSet, loaded: Date)] = [:]
    private let maxAge: TimeInterval = 3 * 3600

    func load(set: String, format: String) async -> RatingSet? {
        let primary = await one(set: set, format: format)
        if let primary, primary.hasData { return primary }
        // Formats with little play (early Quick Draft, special events) have no win rates yet.
        if format != "PremierDraft", let fallback = await one(set: set, format: "PremierDraft") {
            return fallback
        }
        return primary
    }

    private func one(set: String, format: String) async -> RatingSet? {
        let key = "\(set)-\(format)"
        if let hit = memory[key], Date().timeIntervalSince(hit.loaded) < maxAge { return hit.set }
        let file = Cache.dir.appendingPathComponent("ratings-\(key).json")
        let age = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate.map { Date().timeIntervalSince($0) }

        var data: Data?
        var loaded = Date()
        if let age, age < maxAge {
            data = try? Data(contentsOf: file)
            loaded = Date().addingTimeInterval(-age)  // expire with the file, not from now
        }
        if data == nil {
            var url = URLComponents(string: "https://www.17lands.com/api/card_data")!
            url.queryItems = [
                URLQueryItem(name: "expansion", value: set),
                URLQueryItem(name: "event_type", value: format),
                URLQueryItem(name: "time_period", value: "ALL_TIME"),
            ]
            if let fresh = await Cache.fetch(url.url!), decode(fresh) != nil {
                try? fresh.write(to: file, options: .atomic)
                data = fresh
            } else {
                data = try? Data(contentsOf: file)  // stale beats nothing
            }
        }
        guard let data, let cards = decode(data) else { return nil }
        let result = RatingSet(cards: cards, format: format)
        memory[key] = (result, loaded)
        return result
    }

    // MARK: Cards without ratings

    private var extras: [Int: CardRating]?
    private var extrasFile: URL { Cache.dir.appendingPathComponent("cards-unrated.json") }

    /// Name, type and art for cards the ratings table leaves out (basic lands, mostly), from
    /// 17Lands' card lookup. Cached on disk for good: a card id never changes meaning.
    func lookup(ids: [Int]) async -> [Int: CardRating] {
        struct Card: Codable {
            let id: Int
            let name: String
            let rarity: String?
            let image_url: String?
            let types: [String]?
        }
        struct Response: Decodable { let cards: [Card] }
        func rating(_ c: Card) -> CardRating {
            CardRating(
                name: c.name, mtga_id: c.id, color: "", rarity: c.rarity ?? "", url: c.image_url ?? "",
                types: c.types, avg_seen: nil, ever_drawn_game_count: nil, ever_drawn_win_rate: nil)
        }
        if extras == nil {
            let saved = (try? Data(contentsOf: extrasFile)).flatMap { try? JSONDecoder().decode([Card].self, from: $0) }
            extras = Dictionary((saved ?? []).map { ($0.id, rating($0)) }, uniquingKeysWith: { a, _ in a })
        }
        let missing = ids.filter { extras?[$0] == nil }
        if !missing.isEmpty {
            var url = URLComponents(string: "https://www.17lands.com/data/cards")!
            url.queryItems = [URLQueryItem(name: "ids", value: missing.map(String.init).joined(separator: ","))]
            if let data = await Cache.fetch(url.url!),
                let cards = (try? JSONDecoder().decode(Response.self, from: data))?.cards
            {
                for card in cards { extras?[card.id] = rating(card) }
                let all = (extras ?? [:]).values.map {
                    Card(id: $0.mtga_id ?? 0, name: $0.name, rarity: $0.rarity, image_url: $0.url, types: $0.types)
                }
                try? JSONEncoder().encode(all).write(to: extrasFile, options: .atomic)
            }
        }
        return (extras ?? [:]).filter { ids.contains($0.key) }
    }

    private func decode(_ data: Data) -> [CardRating]? {
        struct Response: Decodable { let data: [CardRating] }
        return (try? JSONDecoder().decode(Response.self, from: data))?.data
    }
}

/// A card image and the art box cropped out of it for the row thumbnail.
final class CardArt {
    /// The encoded card image; decoded only when the hover preview needs it.
    let data: Data
    let art: CGImage
    init(data: Data, art: CGImage) {
        self.data = data
        self.art = art
    }
    var full: NSImage? { NSImage(data: data) }
}

actor CardImages {
    static let shared = CardImages()
    private let memory: NSCache<NSString, CardArt> = {
        let cache = NSCache<NSString, CardArt>()
        cache.countLimit = 64
        return cache
    }()

    private static func downsample(_ image: CGImage, width: Int) -> CGImage? {
        let height = width * image.height / max(image.width, 1)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    func load(_ urlString: String) async -> CardArt? {
        if let hit = memory.object(forKey: urlString as NSString) { return hit }
        guard let url = URL(string: urlString) else { return nil }
        let file = Cache.dir.appendingPathComponent("img").appendingPathComponent(url.lastPathComponent)
        var data = try? Data(contentsOf: file)
        if data == nil, let fresh = await Cache.fetch(url) {
            try? fresh.write(to: file, options: .atomic)
            data = fresh
        }
        guard let data, let image = NSImage(data: data),
            let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        // The art box of a standard card frame, as fractions of the card image.
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let box = CGRect(x: w * 0.08, y: h * 0.115, width: w * 0.84, height: h * 0.435)
        guard let crop = cg.cropping(to: box), let art = Self.downsample(crop, width: 160) else { return nil }
        let result = CardArt(data: data, art: art)
        memory.setObject(result, forKey: urlString as NSString)
        return result
    }
}
