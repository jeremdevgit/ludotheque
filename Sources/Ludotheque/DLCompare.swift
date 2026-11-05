// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation

/// Native DLCompare integration (dlcompare.fr): CD-key prices only.
/// Respects robots.txt: games are found through the public sitemap (never /search),
/// prices come from the JSON the game pages load themselves.
struct DLCGame: Codable, Identifiable, Hashable {
    let id: String          // DLCompare game id
    let slug: String        // "hollow-knight"
    var title: String       // from slug, replaced by the real name once prices are loaded

    var pageURL: String { "https://www.dlcompare.fr/jeux/\(id)/acheter-\(slug)" }
}

struct DLCOffer: Identifiable, Hashable {
    let id: String
    let shop: String
    let trusted: Bool       // DLCompare "Gold" partner
    let platform: String    // activation platform (Steam, Xbox…)
    let region: String
    let price: Double       // without payment fees
    let paypal: Double?
    let card: Double?
    let crossed: Double?
    let discount: String?
    let code: String?

    var url: String { "https://www.dlcompare.fr/price/\(id)/serve" }
}

struct DLCTracked: Codable, Identifiable, Hashable {
    var game: DLCGame
    var best: Double?
    var bestShop: String?
    var checkedAt: Date?
    var id: String { game.id }
}

@MainActor
final class DLCompareStore: ObservableObject {
    static let shared = DLCompareStore()

    @Published private(set) var indexCount = 0
    @Published private(set) var loadingIndex = false
    @Published var tracked: [DLCTracked] = Store<[DLCTracked]>.load("dlcompare-tracked.json", []) { didSet { Store<[DLCTracked]>.save("dlcompare-tracked.json", tracked) } }
    @Published private(set) var offers: [String: [DLCOffer]] = [:]
    @Published private(set) var loading: Set<String> = []
    @Published private(set) var refreshing = false

    private var index: [DLCGame] = []
    private let indexURL = Paths.caches.deletingLastPathComponent().appendingPathComponent("dlcompare-index.json")
    private static let headers = ["User-Agent": "Mozilla/5.0 (Macintosh) Ludotheque/1.0", "X-Requested-With": "XMLHttpRequest", "Accept": "application/json"]

    // MARK: Index (sitemap)

    func ensureIndex(force: Bool = false, cachedOnly: Bool = false) async {
        if !index.isEmpty && !force { return }
        if !force, let d = try? Data(contentsOf: indexURL), let list = try? JSONDecoder().decode([DLCGame].self, from: d) {
            index = list; indexCount = list.count; return
        }
        if cachedOnly { return }
        loadingIndex = true
        TaskCenter.shared.begin("dlcindex", "Catalogue DLCompare")
        defer { loadingIndex = false; TaskCenter.shared.end("dlcindex") }
        guard let (d, r) = try? await HTTP.raw("https://www.dlcompare.fr/sitemap.xml", headers: ["User-Agent": Self.headers["User-Agent"]!]),
              r.statusCode == 200 else { return }
        let list = await Task.detached { Self.parseSitemap(d) }.value
        index = list
        indexCount = list.count
        try? JSONEncoder().encode(list).write(to: indexURL, options: .atomic)
    }

    nonisolated static func parseSitemap(_ d: Data) -> [DLCGame] {
        let text = String(decoding: d, as: UTF8.self)
        guard let re = try? NSRegularExpression(pattern: "<loc>https://www\\.dlcompare\\.fr/jeux/(\\d+)/acheter-([a-z0-9-]+)</loc>") else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
            guard let i = Range(m.range(at: 1), in: text), let s = Range(m.range(at: 2), in: text) else { return nil }
            let slug = String(text[s])
            return DLCGame(id: String(text[i]), slug: slug, title: prettify(slug))
        }
    }

    nonisolated static func prettify(_ slug: String) -> String {
        slug.split(separator: "-").map { w in
            let s = String(w)
            return ["ii", "iii", "iv", "vi", "vii", "viii", "ix", "xi", "xii"].contains(s) ? s.uppercased() : s.prefix(1).uppercased() + s.dropFirst()
        }.joined(separator: " ")
    }

    nonisolated static func slugify(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
            .replacingOccurrences(of: "&", with: " and ").replacingOccurrences(of: "'", with: "")
        return folded.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Exact slug first, then slugs starting with the query, then slugs containing every word.
    func search(_ query: String) -> [DLCGame] {
        let q = Self.slugify(query)
        guard !q.isEmpty else { return [] }
        let words = q.split(separator: "-").map(String.init)
        var exact = [DLCGame](), prefix = [DLCGame](), contains = [DLCGame]()
        for g in index {
            if g.slug == q { exact.append(g) }
            else if g.slug.hasPrefix(q + "-") || g.slug.hasPrefix(q) { prefix.append(g) }
            else if words.allSatisfy({ g.slug.contains($0) }) { contains.append(g) }
        }
        prefix.sort { $0.slug.count < $1.slug.count }
        contains.sort { $0.slug.count < $1.slug.count }
        return Array((exact + prefix + contains).prefix(25))
    }

    func bestMatch(_ title: String) async -> DLCGame? {
        await ensureIndex(force: false)
        return search(title).first
    }

    // MARK: Prices

    /// The 10 cheapest CD-key offers (no accounts, no boxed copies, base game only).
    @discardableResult
    func loadOffers(_ g: DLCGame) async -> [DLCOffer] {
        loading.insert(g.id)
        defer { loading.remove(g.id) }
        guard let r = try? await HTTP.json("https://www.dlcompare.fr/price/data/game/\(g.id)/eur", headers: Self.headers),
              let pl = r["priceListData"] as? [String: Any],
              let prices = pl["prices"] as? [[String: Any]] else { return offers[g.id] ?? [] }
        let shops = pl["shops"] as? [String: [String: Any]] ?? [:]
        let platforms = pl["platforms"] as? [String: [String: Any]] ?? [:]
        func num(_ v: Any?) -> Double? { (v as? String).flatMap(Double.init) ?? (v as? NSNumber)?.doubleValue }
        let list = prices.compactMap { p -> DLCOffer? in
            guard p["isAccountSelling"] as? Bool == false, p["box"] as? Bool != true,
                  p["extraId"] == nil || p["extraId"] is NSNull,
                  p["unavailableLabel"] == nil || p["unavailableLabel"] is NSNull,
                  p["isSuspicious"] as? Bool != true,
                  let id = Integrations.string(p["id"]), let price = num(p["finalPrice"]) else { return nil }
            let shop = shops[Integrations.string(p["shopId"]) ?? ""]
            let fees = p["feePrices"] as? [String: Any]
            return DLCOffer(id: id, shop: shop?["name"] as? String ?? "?", trusted: shop?["isGold"] as? Bool ?? false,
                            platform: platforms[Integrations.string(p["platformId"]) ?? ""]?["title"] as? String ?? "",
                            region: p["displayRegion"] as? String ?? "", price: price,
                            paypal: num(fees?["1"]), card: num(fees?["2"]), crossed: num(p["crossedPrice"]),
                            discount: p["discountPercent"] as? String, code: (p["discountCode"] as? String).flatMap { $0.isEmpty ? nil : $0 })
        }
        .sorted { $0.price < $1.price }
        let top = Array(list.prefix(10))
        offers[g.id] = top
        if let i = tracked.firstIndex(where: { $0.id == g.id }) {
            if let name = prices.first?["objectName"] as? String { tracked[i].game.title = name }
            tracked[i].best = top.first?.price
            tracked[i].bestShop = top.first?.shop
            tracked[i].checkedAt = Date()
        }
        return top
    }

    func realTitle(_ g: DLCGame) -> String { tracked.first { $0.id == g.id }?.game.title ?? g.title }

    // MARK: Tracking

    func reload() { tracked = Store<[DLCTracked]>.load("dlcompare-tracked.json", []) }

    func isTracked(_ g: DLCGame) -> Bool { tracked.contains { $0.id == g.id } }

    func toggleTrack(_ g: DLCGame) {
        if let i = tracked.firstIndex(where: { $0.id == g.id }) { tracked.remove(at: i) }
        else { tracked.append(DLCTracked(game: g)); Task { await loadOffers(g) } }
    }

    /// Follows every wishlist game found on DLCompare.
    func trackWishlist() async -> Int {
        await ensureIndex(force: false)
        var n = 0
        for w in WishlistStore.shared.items {
            guard let g = search(w.title).first(where: { $0.slug == Self.slugify(w.title) }), !isTracked(g) else { continue }
            tracked.append(DLCTracked(game: g))
            n += 1
        }
        await refreshTracked()
        return n
    }

    /// Part of "Tout actualiser": refresh followed games (gently, ~1 request per second).
    func refreshTracked() async {
        guard !refreshing, !tracked.isEmpty else { return }
        refreshing = true
        TaskCenter.shared.begin("dlc", "Prix des clés (DLCompare)")
        defer { refreshing = false; TaskCenter.shared.end("dlc") }
        for (i, t) in tracked.enumerated() {
            TaskCenter.shared.progress("dlc", i, tracked.count, t.game.title)
            let before = t.best
            let top = await loadOffers(t.game)
            if let b = before, let now = top.first?.price, now < b - 0.01 {
                Notifier.post("Baisse de prix : \(realTitle(t.game))", String(format: "%.2f € chez %@ (avant %.2f €)", now, top.first!.shop, b), id: "dlc-\(t.id)-\(now)")
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
