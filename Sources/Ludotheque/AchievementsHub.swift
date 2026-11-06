// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation

/// Per-game achievement progress across Steam, Xbox and PlayStation.
struct AchSummary: Codable, Identifiable, Hashable {
    var id: String { "\(platform.rawValue)_\(gameId)" }
    let platform: Platform
    let gameId: String          // Steam app id / Xbox title id / PSN communication id
    var title: String
    var unlocked: Int
    var total: Int
    var lastUnlock: Date?
    var icon: String?
    var gamerscore: Int?        // Xbox
    var gamerscoreTotal: Int?
    var platinum: Bool?         // PlayStation
    var recent: [RecentAch] = []
    var rarest: RecentAch?

    var percent: Double { total == 0 ? 0 : Double(unlocked) / Double(total) }
    var inProgress: Bool { unlocked > 0 && unlocked < total }
    var perfect: Bool { total > 0 && unlocked == total }
}

struct RecentAch: Codable, Hashable {
    let name: String
    let detail: String
    let icon: String?
    let date: Date?
    var rarity: Double?         // % of players who have it (Steam)
}

@MainActor
final class AchievementHub: ObservableObject {
    static let shared = AchievementHub()
    @Published private(set) var items: [AchSummary] = Store<[AchSummary]>.load("achievements.json", [])
    @Published private(set) var progress: (Int, Int)?
    @Published private(set) var lastError: String?
    @Published private(set) var updatedAt: Date? = UserDefaults.standard.object(forKey: "achievementsUpdatedAt") as? Date

    var connected: [Platform] {
        var p = [Platform]()
        if Creds(.steam)["apiKey"] != nil { p.append(.steam) }
        if Creds(.xbox)["apiKey"] != nil { p.append(.xbox) }
        if Creds(.psn)["npsso"] != nil { p.append(.psn) }
        return p
    }

    func refresh(_ lib: Library, replace: Bool = true) async {
        guard !connected.isEmpty else { return }
        await TaskCenter.shared.runAndWait("achievements", String(localized: "Récupération des succès")) { [self] in await doRefresh(lib, replace: replace) }
    }

    /// Part of "Tout actualiser": at most once a day (Steam needs one request per game).
    func refreshIfStale(_ lib: Library) async {
        if Date().timeIntervalSince(updatedAt ?? .distantPast) > 20 * 3600 { await refresh(lib, replace: false) }
    }

    private func doRefresh(_ lib: Library, replace: Bool) async {
        lastError = nil
        var out = [AchSummary]()
        var errors = [String]()
        progress = (0, 1)
        TaskCenter.shared.detail("achievements", String(localized: "Xbox et PlayStation…"))
        if connected.contains(.xbox) {
            do { out += try await xbox() } catch { errors.append("Xbox : \(error.localizedDescription)") }
        }
        if connected.contains(.psn) {
            do { out += try await psn() } catch { errors.append("PlayStation : \(error.localizedDescription)") }
        }
        if connected.contains(.steam) {
            out += await steam(lib)
        }
        progress = nil
        lastError = errors.isEmpty ? nil : errors.joined(separator: " · ")
        guard !out.isEmpty else { return }
        if !replace {
            // Automatic refresh: update what came back, keep the rest (e.g. a platform that failed).
            let fresh = Set(out.map(\.id))
            out += items.filter { !fresh.contains($0.id) }
        }
        items = out
        updatedAt = Date()
        UserDefaults.standard.set(updatedAt, forKey: "achievementsUpdatedAt")
        Store<[AchSummary]>.save("achievements.json", out)
    }

    // MARK: Steam — played games (most played first), with rarity of unlocked achievements

    private func steam(_ lib: Library) async -> [AchSummary] {
        let c = Creds(.steam)
        guard let key = c["apiKey"], let sid = c["steamId"] else { return [] }
        let games = lib.games.filter { $0.platform == .steam && ($0.playtimeMinutes ?? 0) > 0 }
            .sorted { ($0.playtimeMinutes ?? 0) > ($1.playtimeMinutes ?? 0) }.prefix(200)
        var out = [AchSummary]()
        progress = (0, games.count)
        await withTaskGroup(of: AchSummary?.self) { group in
            var it = games.makeIterator()
            func next() {
                guard let g = it.next() else { return }
                group.addTask { await Self.steamGame(g, key: key, sid: sid) }
            }
            for _ in 0..<4 { next() }
            var done = 0
            for await s in group {
                if let s { out.append(s) }
                done += 1
                progress = (done, games.count)
                TaskCenter.shared.progress("achievements", done, games.count, "Steam : \(s?.title ?? "…")")
                if Task.isCancelled { group.cancelAll(); break }
                next()
            }
        }
        return out
    }

    nonisolated private static func steamGame(_ g: Game, key: String, sid: String) async -> AchSummary? {
        let app = g.externalId
        guard let p = try? await HTTP.json("https://api.steampowered.com/ISteamUserStats/GetPlayerAchievements/v1/?appid=\(app)&key=\(key)&steamid=\(sid)&l=french"),
              let list = (p["playerstats"] as? [String: Any])?["achievements"] as? [[String: Any]], !list.isEmpty else { return nil }
        let unlocked = list.filter { ($0["achieved"] as? Int) == 1 }
        var s = AchSummary(platform: .steam, gameId: app, title: g.title, unlocked: unlocked.count, total: list.count,
                           icon: "https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/\(app)/library_600x900.jpg")
        let dated = unlocked.compactMap { a -> (String, Date)? in
            guard let api = a["apiname"] as? String, let t = a["unlocktime"] as? Double, t > 0 else { return nil }
            return (api, Date(timeIntervalSince1970: t))
        }.sorted { $0.1 > $1.1 }
        s.lastUnlock = dated.first?.1
        guard !unlocked.isEmpty else { return s }
        // Names, icons and global rarity only for games with unlocks.
        var schema = [String: (String, String, String?)]()
        if let r = try? await HTTP.json("https://api.steampowered.com/ISteamUserStats/GetSchemaForGame/v2/?appid=\(app)&key=\(key)&l=french"),
           let defs = (((r["game"] as? [String: Any])?["availableGameStats"] as? [String: Any])?["achievements"] as? [[String: Any]]) {
            for d in defs { if let n = d["name"] as? String { schema[n] = (d["displayName"] as? String ?? n, d["description"] as? String ?? "", d["icon"] as? String) } }
        }
        var rarity = [String: Double]()
        if let r = try? await HTTP.json("https://api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v2/?gameid=\(app)"),
           let arr = (r["achievementpercentages"] as? [String: Any])?["achievements"] as? [[String: Any]] {
            for a in arr { if let n = a["name"] as? String { rarity[n] = (a["percent"] as? NSNumber)?.doubleValue ?? Double(a["percent"] as? String ?? "") } }
        }
        func make(_ api: String, _ date: Date?) -> RecentAch {
            let d = schema[api]
            return RecentAch(name: d?.0 ?? api, detail: d?.1 ?? "", icon: d?.2, date: date, rarity: rarity[api])
        }
        s.recent = dated.prefix(5).map { make($0.0, $0.1) }
        let unlockedNames = unlocked.compactMap { $0["apiname"] as? String }
        if let rare = unlockedNames.min(by: { (rarity[$0] ?? 100) < (rarity[$1] ?? 100) }) {
            s.rarest = make(rare, dated.first { $0.0 == rare }?.1)
        }
        return s
    }

    // MARK: Xbox — one call for every title (OpenXBL)

    private func xbox() async throws -> [AchSummary] {
        guard let key = Creds(.xbox)["apiKey"] else { return [] }
        let r = try await HTTP.json("https://xbl.io/api/v2/achievements", headers: ["X-Authorization": key, "Accept-Language": Langue.bcp47])
        let titles = (r["titles"] ?? (r["content"] as? [String: Any])?["titles"]) as? [[String: Any]] ?? []
        return titles.compactMap { t in
            guard let id = Integrations.string(t["titleId"]), let name = t["name"] as? String,
                  let a = t["achievement"] as? [String: Any], let total = a["totalAchievements"] as? Int, total > 0 else { return nil }
            var s = AchSummary(platform: .xbox, gameId: id, title: name, unlocked: a["currentAchievements"] as? Int ?? 0, total: total,
                               icon: t["displayImage"] as? String)
            s.gamerscore = a["currentGamerscore"] as? Int
            s.gamerscoreTotal = a["totalGamerscore"] as? Int
            s.lastUnlock = Integrations.date((t["titleHistory"] as? [String: Any])?["lastTimePlayed"])
            return s
        }
    }

    // MARK: PlayStation — trophy titles

    private func psn() async throws -> [AchSummary] {
        guard let raw = Creds(.psn)["npsso"] else { return [] }
        let token = try await Integrations.psnAccessToken(raw)
        var out = [AchSummary](), offset = 0
        while true {
            let r = try await HTTP.json("https://m.np.playstation.com/api/trophy/v1/users/me/trophyTitles?limit=200&offset=\(offset)",
                                        headers: ["Authorization": "Bearer \(token)"])
            let list = r["trophyTitles"] as? [[String: Any]] ?? []
            for t in list {
                guard let id = t["npCommunicationId"] as? String, let name = t["trophyTitleName"] as? String,
                      let def = t["definedTrophies"] as? [String: Int], let got = t["earnedTrophies"] as? [String: Int] else { continue }
                var s = AchSummary(platform: .psn, gameId: id, title: name, unlocked: got.values.reduce(0, +), total: def.values.reduce(0, +),
                                   icon: t["trophyTitleIconUrl"] as? String)
                s.lastUnlock = Integrations.date(t["lastUpdatedDateTime"])
                s.platinum = (got["platinum"] ?? 0) > 0
                out.append(s)
            }
            guard let next = r["nextOffset"] as? Int, next > offset, !list.isEmpty else { break }
            offset = next
        }
        return out
    }
}
