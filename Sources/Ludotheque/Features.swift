// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation
import AppKit
import UserNotifications

// MARK: - Notifications

enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(_ title: String, _ body: String, id: String) {
        guard UserDefaults.standard.object(forKey: "notifications") as? Bool ?? true else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }
}

// MARK: - Play session journal (Nintendo-style activity log)

struct Session: Codable, Identifiable {
    var id = UUID().uuidString
    let key: String
    let title: String
    let start: Date
    let minutes: Int
}

@MainActor
final class SessionLog: ObservableObject {
    static let shared = SessionLog()
    @Published private(set) var sessions: [Session] = Store<[Session]>.load("sessions.json", [])

    func reload() { sessions = Store<[Session]>.load("sessions.json", []) }

    func add(key: String, title: String, minutes: Int) {
        sessions.insert(Session(key: key, title: title, start: Date().addingTimeInterval(TimeInterval(-minutes * 60)), minutes: minutes), at: 0)
        if sessions.count > 3000 { sessions.removeLast(sessions.count - 3000) }
        Store<[Session]>.save("sessions.json", sessions)
    }

    /// Minutes played per day for the last `days` days (oldest first).
    func perDay(_ days: Int = 7) -> [(Date, Int)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<days).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            let mins = sessions.filter { cal.isDate($0.start, inSameDayAs: day) }.map(\.minutes).reduce(0, +)
            return (day, mins)
        }
    }

    var thisWeekMinutes: Int { perDay(7).map(\.1).reduce(0, +) }
}

// MARK: - Free games (Epic, Steam, GOG, Prime Gaming, itch… via GamerPower)

struct Giveaway: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let worth: String?
    let image: String?
    let platforms: String
    let endDate: Date?
    let url: String
    let description: String?
    var kind: String? = nil          // "Game", "DLC" (in-game items / loot), "Early Access" (betas)

    /// "Sker Ritual (Epic Games) Giveaway" → "Sker Ritual"
    var cleanTitle: String {
        title.replacingOccurrences(of: "\\s*\\([^)]*\\)\\s*Giveaway$|\\s*(Key )?Giveaway$", with: "", options: .regularExpression)
    }
    /// Every platform the offer applies to (PC, consoles, mobile).
    var allPlatforms: [Platform] {
        let p = platforms.lowercased()
        var out = [Platform]()
        for (k, v) in [("steam", Platform.steam), ("epic", .epic), ("gog", .gog), ("itch", .itch), ("ubisoft", .ubisoft), ("playstation", .psn),
                       ("xbox", .xbox), ("switch", .nintendo), ("android", .googleplay), ("ios", .appstore), ("battle", .battlenet)] where p.contains(k) {
            out.append(v)
        }
        return out.isEmpty ? [.custom] : out
    }
    var store: Platform {
        let p = platforms.lowercased()
        if p.contains("epic") { return .epic }
        if p.contains("steam") { return .steam }
        if p.contains("gog") { return .gog }
        if p.contains("itch") { return .itch }
        if p.contains("prime") || p.contains("amazon") { return .amazon }
        if p.contains("ubisoft") { return .ubisoft }
        if p.contains("ea ") || p.contains("origin") { return .ea }
        if p.contains("battle") { return .battlenet }
        if p.contains("playstation") { return .psn }
        if p.contains("xbox") { return .xbox }
        if p.contains("switch") { return .nintendo }
        if p.contains("android") { return .googleplay }
        if p.contains("ios") { return .appstore }
        return .other
    }
}

@MainActor
final class FreeGamesStore: ObservableObject {
    static let shared = FreeGamesStore()
    @Published private(set) var items: [Giveaway] = Store<[Giveaway]>.load("giveaways.json", [])
    @Published private(set) var loot: [Giveaway] = Store<[Giveaway]>.load("giveaways-loot.json", [])
    @Published var claimed: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "claimedGiveaways") ?? []) {
        didSet { UserDefaults.standard.set(Array(claimed), forKey: "claimedGiveaways") }
    }
    @Published private(set) var loading = false

    var active: [Giveaway] { items.filter { ($0.endDate ?? .distantFuture) > Date() } }
    var activeLoot: [Giveaway] { loot.filter { ($0.endDate ?? .distantFuture) > Date() } }

    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        // In-game items, DLC and betas on every platform.
        var extras = [Giveaway]()
        for type in ["loot", "beta"] { extras += await fetch("https://www.gamerpower.com/api/giveaways?type=\(type)&sort-by=date") }
        if !extras.isEmpty {
            let known = Set(loot.map(\.id))
            let new = extras.filter { !known.contains($0.id) }
            if !known.isEmpty, !new.isEmpty {
                Notifier.post(String(localized: "Nouveaux objets gratuits"), new.prefix(3).map(\.cleanTitle).joined(separator: ", "), id: "loot-\(new[0].id)")
            }
            loot = extras
            Store<[Giveaway]>.save("giveaways-loot.json", extras)
        }
        let fresh = await fetch("https://www.gamerpower.com/api/giveaways?platform=pc&type=game&sort-by=date")
        guard !fresh.isEmpty else { return }
        let known = Set(items.map(\.id))
        let new = fresh.filter { !known.contains($0.id) }
        if !known.isEmpty, !new.isEmpty {
            Notifier.post(String(localized: "Nouveau jeu gratuit"), new.prefix(3).map(\.cleanTitle).joined(separator: ", "), id: "free-\(new[0].id)")
        }
        items = fresh
        Store<[Giveaway]>.save("giveaways.json", fresh)
    }

    private func fetch(_ url: String) async -> [Giveaway] {
        guard let (d, r) = try? await HTTP.raw(url), r.statusCode == 200,
              let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return [] }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return arr.compactMap { o -> Giveaway? in
            guard let id = Integrations.string(o["id"]), let title = o["title"] as? String,
                  let url = (o["open_giveaway_url"] as? String) ?? (o["gamerpower_url"] as? String) else { return nil }
            return Giveaway(id: id, title: title, worth: (o["worth"] as? String).flatMap { $0 == "N/A" ? nil : $0 },
                            image: o["image"] as? String, platforms: o["platforms"] as? String ?? "",
                            endDate: (o["end_date"] as? String).flatMap(fmt.date), url: url, description: o["description"] as? String,
                            kind: o["type"] as? String)
        }
    }
}

// MARK: - Wishlist with price tracking (Steam wishlist / IsThereAnyDeal-style)

struct WishItem: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var title: String
    var steamAppId: String?
    var cheapSharkId: String?
    var cover: String?
    var targetPrice: Double?          // in € when a Steam price is known
    var added = Date()
    // Last known prices
    var steamPrice: Double?           // €
    var steamDiscount: Int?
    var bestDeal: Double?             // $ (CheapShark)
    var bestDealStore: String?
    var bestDealURL: String?
    var lowestEver: Double?           // $
    var checkedAt: Date?
    var notifiedAt: Double?

    var onSale: Bool {
        (steamDiscount ?? 0) > 0 || (targetPrice.map { t in (steamPrice ?? bestDeal ?? .infinity) <= t } ?? false)
    }
}

@MainActor
final class WishlistStore: ObservableObject {
    static let shared = WishlistStore()
    @Published private(set) var items: [WishItem] = Store<[WishItem]>.load("wishlist.json", [])
    @Published private(set) var refreshing = false
    private var stores: [String: String] = [:]   // CheapShark storeID → name

    private func save() { Store<[WishItem]>.save("wishlist.json", items) }

    func reload() { items = Store<[WishItem]>.load("wishlist.json", []) }

    func contains(title: String) -> Bool { items.contains { Integrations.norm($0.title) == Integrations.norm(title) } }

    func add(_ item: WishItem) {
        guard !contains(title: item.title) else { return }
        items.insert(item, at: 0)
        save()
        Notifier.requestAuthorization()
        Task {
            while refreshing { try? await Task.sleep(for: .milliseconds(300)) }
            await refresh([item.id])
        }
    }

    func remove(_ id: String) { items.removeAll { $0.id == id }; save() }

    func setTarget(_ id: String, _ price: Double?) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].targetPrice = price
        save()
    }

    /// Search CheapShark (covers Steam, GOG, Epic, Humble, Fanatical, GMG…).
    func search(_ q: String) async -> [WishItem] {
        guard let (d, _) = try? await HTTP.raw("https://www.cheapshark.com/api/1.0/games?limit=12&title=\(q.urlQueryEscaped)"),
              let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return [] }
        return arr.compactMap { o in
            guard let t = o["external"] as? String else { return nil }
            let steam = (o["steamAppID"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return WishItem(title: t, steamAppId: steam, cheapSharkId: o["gameID"] as? String,
                            cover: steam.map { "https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/\($0)/library_600x900.jpg" } ?? o["thumb"] as? String,
                            bestDeal: Double(o["cheapest"] as? String ?? ""))
        }
    }

    /// Imports the public Steam wishlist of the connected (or local) Steam account.
    func importSteam() async -> String {
        guard let sid = Creds(.steam)["steamId"].flatMap({ UInt64($0) != nil ? $0 : nil }) ?? Integrations.steamLocalUser() else {
            return String(localized: "Connecte Steam dans Gestion des plateformes (SteamID requis)")
        }
        guard let r = try? await HTTP.json("https://api.steampowered.com/IWishlistService/GetWishlist/v1/?steamid=\(sid)"),
              let list = (r["response"] as? [String: Any])?["items"] as? [[String: Any]], !list.isEmpty else {
            return String(localized: "Liste de souhaits Steam vide ou privée (rends « Détails des jeux » public)")
        }
        var added = 0
        for e in list {
            guard let appid = Integrations.string(e["appid"]), !items.contains(where: { $0.steamAppId == appid }) else { continue }
            var title = ""
            var cs: String?
            if let (d, _) = try? await HTTP.raw("https://www.cheapshark.com/api/1.0/games?steamAppID=\(appid)"),
               let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]], let f = arr.first {
                title = f["external"] as? String ?? ""
                cs = f["gameID"] as? String
            }
            if title.isEmpty, let r = try? await HTTP.json("https://store.steampowered.com/api/appdetails?appids=\(appid)&filters=basic"),
               let n = ((r[appid] as? [String: Any])?["data"] as? [String: Any])?["name"] as? String { title = n }
            guard !title.isEmpty else { continue }
            items.append(WishItem(title: title, steamAppId: appid, cheapSharkId: cs,
                                  cover: "https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/\(appid)/library_600x900.jpg"))
            added += 1
        }
        save()
        await refresh()
        return String(localized: "\(added) jeux importés depuis ta liste de souhaits Steam")
    }

    func refresh(_ ids: [String]? = nil) async {
        guard !refreshing, !items.isEmpty else { return }
        refreshing = true
        TaskCenter.shared.begin("wishlist", String(localized: "Prix de la liste de souhaits"))
        defer { refreshing = false; save(); TaskCenter.shared.end("wishlist") }
        if stores.isEmpty, let (d, _) = try? await HTTP.raw("https://www.cheapshark.com/api/1.0/stores"),
           let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] {
            for s in arr { if let id = s["storeID"] as? String, let n = s["storeName"] as? String { stores[id] = n } }
        }
        for i in items.indices where ids == nil || ids!.contains(items[i].id) {
            var it = items[i]
            if let app = it.steamAppId,
               let r = try? await HTTP.json("https://store.steampowered.com/api/appdetails?appids=\(app)&cc=fr&filters=price_overview"),
               let po = ((r[app] as? [String: Any])?["data"] as? [String: Any])?["price_overview"] as? [String: Any] {
                it.steamPrice = (po["final"] as? Double).map { $0 / 100 }
                it.steamDiscount = po["discount_percent"] as? Int
            }
            if let cs = it.cheapSharkId, let r = try? await HTTP.json("https://www.cheapshark.com/api/1.0/games?id=\(cs)") {
                if let deal = (r["deals"] as? [[String: Any]])?.first {
                    it.bestDeal = Double(deal["price"] as? String ?? "")
                    it.bestDealStore = stores[deal["storeID"] as? String ?? ""]
                    it.bestDealURL = (deal["dealID"] as? String).map { "https://www.cheapshark.com/redirect?dealID=\($0)" }
                }
                it.lowestEver = Double(((r["cheapestPriceEver"] as? [String: Any])?["price"] as? String) ?? "")
            }
            it.checkedAt = Date()
            TaskCenter.shared.progress("wishlist", i + 1, items.count, it.title)
            // One alert per price point.
            let price = it.steamPrice ?? it.bestDeal ?? 0
            if it.onSale, it.notifiedAt != price {
                let detail = it.steamPrice.map { String(format: "%.2f €", $0) } ?? it.bestDeal.map { String(format: "%.2f $", $0) } ?? ""
                Notifier.post(String(localized: "Promo : \(it.title)"), "\(detail)\(it.steamDiscount.map { $0 > 0 ? " (−\($0) %)" : "" } ?? "")", id: "wish-\(it.id)-\(price)")
                it.notifiedAt = price
            }
            items[i] = it
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}

// MARK: - News (Steam announcements & patch notes)

struct NewsItem: Identifiable, Hashable {
    let id: String
    let game: String
    let title: String
    let url: String
    let date: Date
    let summary: String
}

enum News {
    static func fetch(appId: String, game: String, count: Int = 3) async -> [NewsItem] {
        guard let r = try? await HTTP.json("https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=\(appId)&count=\(count)&maxlength=300&feeds=steam_community_announcements"),
              let items = (r["appnews"] as? [String: Any])?["newsitems"] as? [[String: Any]] else { return [] }
        return items.compactMap { n in
            guard let gid = n["gid"] as? String, let t = n["title"] as? String, let u = n["url"] as? String else { return nil }
            let text = (n["contents"] as? String ?? "")
                .replacingOccurrences(of: "\\[[^\\]]*\\]|<[^>]+>|\\{STEAM_CLAN_IMAGE\\}[^ ]*", with: "", options: .regularExpression)
            return NewsItem(id: gid, game: game, title: t, url: u,
                            date: Date(timeIntervalSince1970: n["date"] as? Double ?? 0), summary: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func steamId(_ g: GameGroup) -> String? {
        g.games.first { $0.platform == .steam }?.externalId
    }
}

// MARK: - Achievements (Steam & Xbox)

struct Achievement: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let icon: String?
    let unlocked: Date?
}

enum Achievements {
    static func fetch(_ g: GameGroup) async -> (platform: Platform, list: [Achievement])? {
        if let app = News.steamId(g), let r = await steam(app) { return (.steam, r) }
        if let xbox = g.games.first(where: { $0.platform == .xbox }), let r = await xboxList(xbox.externalId) { return (.xbox, r) }
        return nil
    }

    private static func steam(_ app: String) async -> [Achievement]? {
        let c = Creds(.steam)
        guard let key = c["apiKey"], let sid = c["steamId"] else { return nil }
        guard let p = try? await HTTP.json("https://api.steampowered.com/ISteamUserStats/GetPlayerAchievements/v1/?appid=\(app)&key=\(key)&steamid=\(sid)&l=french"),
              let list = (p["playerstats"] as? [String: Any])?["achievements"] as? [[String: Any]] else { return nil }
        var icons = [String: (String, String)]()
        if let s = try? await HTTP.json("https://api.steampowered.com/ISteamUserStats/GetSchemaForGame/v2/?appid=\(app)&key=\(key)&l=french"),
           let defs = (((s["game"] as? [String: Any])?["availableGameStats"] as? [String: Any])?["achievements"] as? [[String: Any]]) {
            for d in defs { if let n = d["name"] as? String { icons[n] = (d["icon"] as? String ?? "", d["icongray"] as? String ?? "") } }
        }
        return list.compactMap { a in
            guard let api = a["apiname"] as? String else { return nil }
            let done = (a["achieved"] as? Int ?? 0) == 1
            let t = a["unlocktime"] as? Double ?? 0
            return Achievement(id: api, name: a["name"] as? String ?? api, detail: a["description"] as? String ?? "",
                               icon: done ? icons[api]?.0 : icons[api]?.1, unlocked: done ? Date(timeIntervalSince1970: t) : nil)
        }
    }

    private static func xboxList(_ titleId: String) async -> [Achievement]? {
        guard let key = Creds(.xbox)["apiKey"],
              let r = try? await HTTP.json("https://xbl.io/api/v2/achievements/title/\(titleId)", headers: ["X-Authorization": key, "Accept-Language": Langue.bcp47]),
              let list = r["achievements"] as? [[String: Any]] else { return nil }
        return list.compactMap { a in
            guard let id = Integrations.string(a["id"]), let n = a["name"] as? String else { return nil }
            let done = (a["progressState"] as? String) == "Achieved"
            let icon = (a["mediaAssets"] as? [[String: Any]])?.first?["url"] as? String
            let when = Integrations.date((a["progression"] as? [String: Any])?["timeUnlocked"])
            return Achievement(id: id, name: n, detail: (a["description"] as? String) ?? (a["lockedDescription"] as? String) ?? "",
                               icon: icon, unlocked: done ? (when ?? Date()) : nil)
        }
    }
}
