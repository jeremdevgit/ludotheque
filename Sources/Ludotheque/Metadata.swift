// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation

/// Titles, covers and Mac support for games known only by store id, from
/// GOG's public GamesDB (the same service Galaxy uses). Results are cached
/// on disk forever, including misses, so this only hits the network once.
actor GamesDB {
    struct Entry: Codable {
        var title: String?
        var cover: String?
        var mac: Bool?
        var dlc: Bool?
    }

    static let shared = GamesDB()
    private let url = Paths.support.appendingPathComponent("gamesdb-cache.json")
    private var cache: [String: Entry] = [:]
    private var loaded = false

    private static let platformIds: [Platform: String] = [
        .steam: "steam", .epic: "epic", .gog: "gog", .xbox: "xboxone", .battlenet: "battlenet", .ea: "origin",
        .ubisoft: "uplay", .psn: "psn", .riot: "riot", .rockstar: "rockstar", .bethesda: "bethesda",
        .indiegala: "indiegala", .humble: "humble", .itch: "itch", .amazon: "amazon",
        .fanatical: "fanatical", .gmg: "gmg", .paradox: "paradox", .wargaming: "wargaming", .meta: "oculus",
    ]

    private static func dbId(_ g: Game) -> String? { g.manualId == nil ? (g.dbPlatform ?? platformIds[g.platform]) : nil }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let d = try? Data(contentsOf: url) { cache = (try? JSONDecoder().decode([String: Entry].self, from: d)) ?? [:] }
    }

    func applyCached(_ games: [String: Game]) -> [String: Game] {
        load()
        var out = games
        for (id, e) in cache where out[id] != nil { Self.apply(e, to: &out[id]!) }
        return out
    }

    func needsLookup(_ g: Game) -> Bool {
        load()
        guard Self.dbId(g) != nil, cache[g.id] == nil else { return false }
        return !g.hasTitle || g.coverURL == nil
    }

    /// Fetches missing entries with bounded concurrency; returns the new ones.
    func fetch(_ games: [Game], progress: @Sendable (Int, Int) async -> Void) async -> [String: Entry] {
        load()
        let todo = games.filter(needsLookup)
        guard !todo.isEmpty else { return [:] }
        var found = [String: Entry]()
        var done = 0
        await withTaskGroup(of: (String, Entry?).self) { group in
            var it = todo.makeIterator()
            func next() {
                guard let g = it.next(), let p = Self.dbId(g) else { return }
                group.addTask { (g.id, await Self.lookup(platform: p, id: g.externalId)) }
            }
            for _ in 0..<8 { next() }
            for await (id, e) in group {
                // nil = network error: retry next launch. Empty entry = known miss.
                if let e { cache[id] = e; found[id] = e }
                done += 1
                if done % 20 == 0 { await progress(done, todo.count) }
                next()
            }
        }
        save()
        return found
    }

    private func save() {
        if let d = try? JSONEncoder().encode(cache) { try? d.write(to: url, options: .atomic) }
    }

    /// nil = network error, (404, nil) = unknown release.
    private static func release(platform: String, id: String) async -> (Int, [String: Any]?)? {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? id
        guard let u = URL(string: "https://gamesdb.gog.com/platforms/\(platform)/external_releases/\(safe)") else { return (404, nil) }
        var req = URLRequest(url: u, timeoutInterval: 15)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req), let http = resp as? HTTPURLResponse else { return nil }
        return (http.statusCode, try? JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func localized(_ v: Any?) -> String? {
        guard let d = v as? [String: String] else { return nil }
        return d[Langue.bcp47] ?? d["en-US"] ?? d["*"] ?? d.values.first
    }

    private static func lookup(platform: String, id: String) async -> Entry? {
        guard let (status, o) = await release(platform: platform, id: id) else { return nil }
        if status == 404 { return Entry() }
        guard status == 200, let obj = o else { return nil }
        let game = obj["game"] as? [String: Any]
        var e = Entry()
        e.title = localized(game?["title"]) ?? localized(obj["title"])
        if let fmt = (game?["vertical_cover"] as? [String: Any])?["url_format"] as? String {
            e.cover = fmt.replacingOccurrences(of: "{formatter}", with: "_glx_vertical_cover").replacingOccurrences(of: "{ext}", with: "webp")
        }
        if let os = obj["supported_operating_systems"] as? [[String: Any]], !os.isEmpty {
            e.mac = os.contains { ($0["slug"] as? String) == "osx" }
        }
        if let t = (game?["type"] as? String) ?? (obj["type"] as? String) { e.dlc = t != "game" }
        return e
    }

    // MARK: Game details (description, genres…), fetched on demand

    struct Details: Codable {
        var summary: String?
        var genres: [String] = []
        var developers: [String] = []
        var publishers: [String] = []
        var modes: [String] = []
        var release: Date?
        var score: Double?
        var background: String?
        var screenshots: [String] = []
    }

    private let detailsURL = Paths.support.appendingPathComponent("gamesdb-details.json")
    private var detailsCache: [String: Details]?

    /// Details already downloaded (no network), for statistics.
    func cachedDetails(_ groups: [[Game]]) -> [Details?] {
        if detailsCache == nil {
            detailsCache = (try? JSONDecoder().decode([String: Details].self, from: Data(contentsOf: detailsURL))) ?? [:]
        }
        return groups.map { g in g.lazy.compactMap { self.detailsCache?[$0.id] }.first }
    }

    func details(for group: [Game]) async -> Details? {
        if detailsCache == nil {
            detailsCache = (try? JSONDecoder().decode([String: Details].self, from: Data(contentsOf: detailsURL))) ?? [:]
        }
        for g in group { if let d = detailsCache?[g.id] { return d } }
        // Store ids first, then a Steam title search as universal fallback.
        var candidates = group.compactMap { g in Self.dbId(g).map { (g.id, $0, g.externalId) } }
        if let first = group.first, let hit = await Self.steamSearch(first.title) { candidates.append((first.id, "steam", hit)) }
        for (key, p, id) in candidates {
            guard let (status, o) = await Self.release(platform: p, id: id), status == 200,
                  let game = o?["game"] as? [String: Any] else { continue }
            let d = Self.parseDetails(game)
            detailsCache?[key] = d
            if let data = try? JSONEncoder().encode(detailsCache) { try? data.write(to: detailsURL, options: .atomic) }
            return d
        }
        return nil
    }

    private static func steamSearch(_ title: String) async -> String? {
        let hits = await CoverSearch.search(title)
        let key = title.lowercased().filter { $0.isLetter || $0.isNumber }
        return hits.first { $0.name.lowercased().filter { $0.isLetter || $0.isNumber } == key }?.id
    }

    private static func parseDetails(_ g: [String: Any]) -> Details {
        func names(_ k: String) -> [String] {
            (g[k] as? [[String: Any]] ?? []).compactMap { ($0["name"] as? String) ?? localized($0["name"]) }
        }
        func image(_ v: Any?, _ fmt: String) -> String? {
            ((v as? [String: Any])?["url_format"] as? String)?.replacingOccurrences(of: "{formatter}", with: fmt).replacingOccurrences(of: "{ext}", with: "jpg")
        }
        var d = Details()
        d.summary = localized(g["summary"])
        d.genres = names("genres")
        d.developers = names("developers")
        d.publishers = names("publishers")
        d.modes = names("game_modes")
        d.release = Integrations.date(g["first_release_date"]) ?? (g["first_release_date"] as? String).flatMap {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"; return f.date(from: $0)
        }
        d.score = (g["aggregated_rating"] as? NSNumber)?.doubleValue
        d.background = image(g["background"], "_bg_crop_1366x655")
        d.screenshots = (g["screenshots"] as? [Any] ?? []).prefix(8).compactMap { image($0, "_product_card_v2_mobile_slider_639") }
        return d
    }

    static func apply(_ e: Entry, to g: inout Game) {
        if !g.hasTitle, let t = e.title { g.title = t; Links.refresh(&g) }
        if g.coverURL == nil { g.coverURL = e.cover }
        if g.macNative == nil { g.macNative = e.mac }
        if e.dlc == true && !g.installed { g.isDLC = true }
    }
}
