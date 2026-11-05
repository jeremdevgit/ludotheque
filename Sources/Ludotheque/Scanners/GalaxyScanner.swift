// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation
import AppKit

/// GOG Galaxy 2.0 aggregates the libraries of every connected platform
/// (Xbox, PlayStation, Ubisoft, EA, Epic, Steam, Battle.net…). Reading its
/// database gives us ownership for stores that have no Mac client.
enum GalaxyScanner {
    static let dbPath = "/Users/Shared/GOG.com/Galaxy/Storage/galaxy-2.0.db"

    static func scan(steamInfo: [UInt32: SteamAppInfo]) -> [Game] {
        guard let db = SQLiteDB(path: dbPath) else { return [] }

        var hidden = Set<String>()
        for r in db.rows("select releaseKey from UserReleaseProperties where isHidden = 1") { if let k = r[0] { hidden.insert(k) } }

        var titles = [String: String]()
        var covers = [String: String]()
        var dlc = Set<String>()
        let pieces = db.rows("""
            select g.releaseKey, t.type, g.value from GamePieces g join GamePieceTypes t on t.id = g.gamePieceTypeId
            where t.type in ('title', 'originalTitle', 'originalImages', 'meta', 'originalMeta')
            """)
        for r in pieces {
            guard let key = r[0], let type = r[1], let raw = r[2]?.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { continue }
            switch type {
            case "title", "originalTitle":
                if let t = obj["title"] as? String, !t.isEmpty, titles[key] == nil || type == "title" { titles[key] = t }
            case "originalImages":
                if let c = obj["verticalCover"] as? String { covers[key] = c }
            default:
                if let t = obj["type"] as? String, t != "game" { dlc.insert(key) }
            }
        }

        var lastPlayed = [String: Date]()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        fmt.timeZone = TimeZone(identifier: "UTC")
        for r in db.rows("select gameReleaseKey, lastPlayedDate from LastPlayedDates") {
            if let k = r[0], let s = r[1], let d = fmt.date(from: s) { lastPlayed[k] = d }
        }
        var playtime = [String: Int]()
        for r in db.rows("select releaseKey, minutesInGame from GameTimes") {
            if let k = r[0], let m = Int(r[1] ?? "") , m > 0 { playtime[k] = m }
        }

        var installedGOG = Set<String>()
        for r in db.rows("select productId from InstalledBaseProducts") { if let id = r[0] { installedGOG.insert(id) } }
        let galaxyHere = Launchers.installed(.gog)

        var games = [Game]()
        for r in db.rows("select distinct releaseKey from LibraryReleases") {
            guard let key = r[0], !hidden.contains(key), !dlc.contains(key),
                  let sep = key.firstIndex(of: "_") else { continue }
            let prefix = String(key[..<sep]), ext = String(key[key.index(after: sep)...])
            let platform = Platform.fromGalaxy(prefix)
            if platform == .other, prefix == "test" { continue }

            var g: Game
            if platform == .steam {
                g = SteamScanner.make(id: ext, info: steamInfo)
                if g.isDLC { continue }
            } else {
                g = Game(id: "\(platform.rawValue)_\(ext)", platform: platform, externalId: ext, title: titles[key] ?? "")
                g.coverURL = covers[key]
                g.dbPlatform = prefix
                Links.fill(&g)
                if prefix == "minecraft" { // Microsoft-owned, native Mac (Java) edition
                    g.macNative = true
                    g.launchURL = "https://www.minecraft.net/fr-fr/download"
                }
            }
            if let t = titles[key], !g.hasTitle { g.title = t }
            if platform == .gog {
                g.installed = installedGOG.contains(ext)
                if galaxyHere { g.launchURL = "goggalaxy://openGameView/\(key)" }
            }
            g.lastPlayed = lastPlayed[key]
            g.playtimeMinutes = playtime[key]
            games.append(g)
        }
        return games
    }
}

/// Store pages and launcher URL schemes for platforms we only know by id.
enum Links {
    static let battlenetCodes: [String: String] = [
        "wow": "WoW", "wow_classic": "WoWC", "diablo3": "D3", "fenris": "Fen", "fen": "Fen", "d2r": "OSI", "osi": "OSI",
        "s1": "S1", "s2": "S2", "hs_beta": "WTCG", "heroes": "Hero", "prometheus": "Pro", "w3": "W3",
        "odin": "ODIN", "viper": "VIPR", "lazarus": "LAZR", "zeus": "ZEUS", "fore": "FORE", "auks": "AUKS",
    ]

    /// Blizzard games with a native macOS client.
    static let battlenetMac: Set<String> = ["wow", "wow_classic", "diablo3", "s1", "s2", "hs_beta", "heroes", "fenris", "fen"]

    static func fill(_ g: inout Game) {
        let q = g.title.urlQueryEscaped
        switch g.platform {
        case .epic:
            g.launchURL = "com.epicgames.launcher://apps/\(g.externalId)?action=launch&silent=true"
            g.storeURL = "https://store.epicgames.com/fr/browse?q=\(q)"
        case .gog:
            g.storeURL = "https://www.gog.com/fr/games?query=\(q)"
        case .xbox:
            g.storeURL = "https://www.xbox.com/fr-FR/search/results/games?q=\(q)"
            g.launchURL = "https://www.xbox.com/fr-FR/play/search?q=\(q)"
            g.macNative = false
            if g.title.localizedCaseInsensitiveContains("Java Edition") {
                // Minecraft Java Edition runs natively on Mac through its launcher.
                let launcher = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mojang.minecraftlauncher")?.path
                g.macNative = true
                g.installed = launcher != nil
                g.launchURL = launcher ?? "https://www.minecraft.net/fr-fr/download"
            }
        case .battlenet:
            if let code = battlenetCodes[g.externalId] { g.launchURL = "battlenet://\(code)" }
            g.macNative = battlenetMac.contains(g.externalId)
            g.storeURL = "https://shop.battle.net/fr-fr"
        case .ea:
            g.storeURL = "https://www.ea.com/fr-fr/games/library?q=\(q)"
        case .ubisoft:
            g.storeURL = "https://store.ubisoft.com/fr/search?q=\(q)"
            g.macNative = false
        case .psn:
            g.storeURL = "https://store.playstation.com/fr-fr/search/\(q)"
            g.macNative = false
        case .riot:
            g.storeURL = "https://www.riotgames.com/fr"
            let lol = g.externalId.contains("league")
            g.macNative = lol
            if lol, Paths.exists("/Applications/League of Legends.app") { g.launchURL = "/Applications/League of Legends.app"; g.installed = true }
            else if lol { g.launchURL = "https://signup.leagueoflegends.com/fr-fr/signup/redownload" }
        case .itch:
            g.storeURL = "https://itch.io/search?q=\(q)"
        case .amazon:
            g.storeURL = "https://gaming.amazon.com/home"
        default:
            break
        }
    }

    /// Refresh query-based URLs once a real title is known.
    static func refresh(_ g: inout Game) {
        let launch = g.launchURL, installed = g.installed
        Links.fill(&g)
        if installed || g.platform == .gog || g.platform == .steam { g.launchURL = launch ?? g.launchURL }
    }
}
