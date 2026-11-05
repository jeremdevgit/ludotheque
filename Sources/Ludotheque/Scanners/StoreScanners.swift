// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation

// MARK: - Epic Games Launcher

enum EpicScanner {
    struct CatalogEntry { var title: String; var cover: String?; var mac: Bool; var isGame: Bool; var launchId: String }

    static let base = Paths.appSupport.appendingPathComponent("Epic")

    /// Catalog cache of the Epic launcher, keyed by appName and catalog id.
    static func catalog() -> [String: CatalogEntry] {
        let url = base.appendingPathComponent("EpicGamesLauncher/Data/Catalog/catcache.bin")
        guard let b64 = try? Data(contentsOf: url), let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
        var out = [String: CatalogEntry]()
        for it in items {
            guard let title = it["title"] as? String, let id = it["id"] as? String else { continue }
            let ns = it["namespace"] as? String ?? ""
            let cats = (it["categories"] as? [[String: Any]])?.compactMap { $0["path"] as? String } ?? []
            let images = it["keyImages"] as? [[String: Any]] ?? []
            let cover = ["DieselGameBoxTall", "OfferImageTall", "Thumbnail"].lazy.compactMap { t in
                images.first { $0["type"] as? String == t }?["url"] as? String
            }.first
            for rel in it["releaseInfo"] as? [[String: Any]] ?? [] {
                guard let appId = rel["appId"] as? String else { continue }
                let mac = (rel["platform"] as? [String])?.contains("Mac") ?? false
                let e = CatalogEntry(title: title, cover: cover, mac: mac, isGame: cats.contains("games"),
                                     launchId: "\(ns)%3A\(id)%3A\(appId)")
                out[appId] = e
                out[id] = out[id] ?? e
            }
        }
        return out
    }

    static func installed() -> [Game] {
        let candidates = [
            URL(fileURLWithPath: "/Users/Shared/Epic/UnrealEngineLauncher/LauncherInstalled.dat"),
            base.appendingPathComponent("UnrealEngineLauncher/LauncherInstalled.dat"),
        ]
        var games = [Game]()
        for url in candidates {
            guard let root = JSON.load(url) as? [String: Any], let list = root["InstallationList"] as? [[String: Any]] else { continue }
            for e in list {
                guard let app = e["AppName"] as? String, (e["NamespaceId"] as? String) != "ue" else { continue }
                var g = Game(id: "epic_\(app)", platform: .epic, externalId: app, title: "")
                Links.fill(&g)
                g.installed = true
                g.macNative = true
                if let loc = e["InstallLocation"] as? String {
                    g.appPath = Bundle2.apps(in: URL(fileURLWithPath: loc), depth: 1).first?.path
                }
                games.append(g)
            }
        }
        return games
    }

    static func enrich(_ g: inout Game, _ cat: [String: CatalogEntry]) {
        guard let e = cat[g.externalId] else { return }
        if !g.hasTitle { g.title = e.title }
        if g.coverURL == nil { g.coverURL = e.cover }
        if g.macNative == nil { g.macNative = e.mac }
        g.launchURL = "com.epicgames.launcher://apps/\(e.launchId)?action=launch&silent=true"
        if !e.isGame && !g.installed { g.isDLC = true }
    }
}

// MARK: - Heroic Games Launcher (Epic via Legendary, GOG, Amazon via Nile, sideloaded)

enum HeroicScanner {
    static let base = Paths.appSupport.appendingPathComponent("heroic")

    static func scan() -> [Game] {
        guard Paths.exists(base.path) else { return [] }
        let files: [(String, String, Platform)] = [
            ("store_cache/legendary_library.json", "legendary", .epic),
            ("store_cache/gog_library.json", "gog", .gog),
            ("store_cache/nile_library.json", "nile", .amazon),
            ("sideload_apps.json", "sideload", .custom),
        ]
        var games = [Game]()
        for (file, runner, platform) in files {
            guard let root = JSON.load(base.appendingPathComponent(file)) as? [String: Any] else { continue }
            let list = (root["library"] ?? root["games"]) as? [[String: Any]] ?? []
            for e in list {
                guard let app = e["app_name"] as? String, let title = e["title"] as? String else { continue }
                if e["is_dlc"] as? Bool == true { continue }
                var g = Game(id: "\(platform.rawValue)_\(app)", platform: platform, externalId: app, title: title)
                Links.fill(&g)
                g.installed = e["is_installed"] as? Bool ?? false
                g.macNative = (e["is_mac_native"] as? Bool) ?? ((e["install"] as? [String: Any])?["platform"] as? String == "Mac")
                g.coverURL = (e["art_cover"] as? String) ?? (e["art_square"] as? String)
                if g.installed || g.macNative == true || runner == "sideload" {
                    g.launchURL = "heroic://launch?appName=\(app.urlQueryEscaped)&runner=\(runner)"
                    // Windows games run through Heroic's Wine/CrossOver layer.
                    if g.installed { g.macNative = true }
                }
                games.append(g)
            }
        }
        return games
    }
}

// MARK: - itch.io app (butler database)

enum ItchScanner {
    static func scan() -> [Game] {
        let path = Paths.appSupport.appendingPathComponent("itch/db/butler.db").path
        guard let db = SQLiteDB(path: path) else { return [] }
        var games = [String: Game]()
        func make(_ r: [String?]) -> Game? {
            guard let id = r[0], let title = r[1] else { return nil }
            var g = Game(id: "itch_\(id)", platform: .itch, externalId: id, title: title)
            g.coverURL = r[2].flatMap { $0.isEmpty ? nil : $0 }
            g.storeURL = r[3]
            if let p = r[4] { g.macNative = p.contains("osx") || p.contains("\"web\"") }
            return g
        }
        // Owned (download keys) and installed (caves).
        for r in db.rows("select g.id, g.title, g.cover_url, g.url, g.platforms from games g join download_keys k on k.game_id = g.id") {
            if let g = make(r) { games[g.id] = g }
        }
        for r in db.rows("select g.id, g.title, g.cover_url, g.url, g.platforms, c.id, c.last_touched_at, c.seconds_run from caves c join games g on g.id = c.game_id") {
            guard var g = make(r), let cave = r[5] else { continue }
            g.installed = true
            g.macNative = true
            g.launchURL = "itch://caves/\(cave)/launch"
            if let s = Int(r[7] ?? ""), s > 0 { g.playtimeMinutes = s / 60 }
            if let t = r[6], let d = ISO8601DateFormatter().date(from: t) { g.lastPlayed = d }
            games[g.id] = g
        }
        // Owned but not installed: open in the itch app to install.
        if Launchers.installed(.itch) {
            for (k, g) in games where g.launchURL == nil {
                games[k]?.launchURL = "itch://games/\(g.externalId)"
            }
        }
        return Array(games.values)
    }
}
