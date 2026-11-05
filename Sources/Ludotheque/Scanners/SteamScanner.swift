// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation

enum SteamScanner {
    static let root = Paths.appSupport.appendingPathComponent("Steam")

    /// Returns installed + recently played Steam games, plus the appinfo
    /// table so other sources (GOG Galaxy library) can resolve Steam names.
    static func scan() -> (games: [Game], info: [UInt32: SteamAppInfo]) {
        guard Paths.exists(root.path) else { return ([], [:]) }
        let info = AppInfoVDF.parse(root.appendingPathComponent("appcache/appinfo.vdf"))
        var games = [String: Game]()

        // Installed games in every library folder.
        var libraries = [root.path]
        if let lf = VDF.parse(file: root.appendingPathComponent("steamapps/libraryfolders.vdf"))?["libraryfolders"] {
            for (_, v) in lf.dict { if let p = v["path"]?.string, !libraries.contains(p) { libraries.append(p) } }
        }
        for lib in libraries {
            let apps = URL(fileURLWithPath: lib).appendingPathComponent("steamapps")
            let files = (try? FileManager.default.contentsOfDirectory(atPath: apps.path)) ?? []
            for f in files where f.hasPrefix("appmanifest_") && f.hasSuffix(".acf") {
                guard let st = VDF.parse(file: apps.appendingPathComponent(f))?["AppState"],
                      let id = st["appid"]?.string else { continue }
                var g = make(id: id, info: info)
                if g.title.isEmpty || g.title == id { g.title = st["name"]?.string ?? id }
                let flags = Int(st["StateFlags"]?.string ?? "") ?? 0
                g.installed = flags & 4 != 0 // FullyInstalled
                if let dir = st["installdir"]?.string {
                    let gameDir = apps.appendingPathComponent("common/\(dir)")
                    g.appPath = Bundle2.apps(in: gameDir, depth: 0).first?.path
                    if g.appPath != nil { g.macNative = true }
                }
                if let lp = Double(st["LastPlayed"]?.string ?? ""), lp > 0 { g.lastPlayed = Date(timeIntervalSince1970: lp) }
                games[g.id] = g
            }
        }

        // Rest of the owned library (artwork cache) — keep only real games.
        for id in knownAppIds() where games["steam_\(id)"] == nil {
            if let i = info[UInt32(id)!], i.type == "game" { games["steam_\(id)"] = make(id: id, info: info) }
        }

        // Playtime / last played from every local user's config.
        let users = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("userdata").path)) ?? []
        for u in users {
            let cfg = root.appendingPathComponent("userdata/\(u)/config/localconfig.vdf")
            guard let apps = VDF.parse(file: cfg)?["UserLocalConfigStore"]?["Software"]?["Valve"]?["Steam"]?["apps"] else { continue }
            for (id, v) in apps.dict {
                guard let appId = UInt32(id) else { continue }
                let lp = Double(v["LastPlayed"]?.string ?? "") ?? 0
                let pt = Int(v["Playtime"]?.string ?? "") ?? 0
                guard lp > 0 || pt > 0 else { continue }
                if games["steam_\(id)"] == nil {
                    // Played but not installed: only keep real games.
                    guard let i = info[appId], i.type == "game" else { continue }
                    games["steam_\(id)"] = make(id: id, info: info)
                }
                var g = games["steam_\(id)"]!
                if lp > 0 { g.lastPlayed = max(g.lastPlayed ?? .distantPast, Date(timeIntervalSince1970: lp)) }
                if pt > 0 { g.playtimeMinutes = pt }
                games[g.id] = g
            }
        }
        return (Array(games.values), info)
    }

    static func make(id: String, info: [UInt32: SteamAppInfo]) -> Game {
        let i = UInt32(id).flatMap { info[$0] }
        var g = Game(id: "steam_\(id)", platform: .steam, externalId: id, title: i?.name ?? id)
        if let i {
            g.macNative = i.oslist.contains("macos")
            g.isDLC = !i.type.isEmpty && i.type != "game"
        }
        g.launchURL = "steam://rungameid/\(id)"
        g.storeURL = "https://store.steampowered.com/app/\(id)"
        let local = root.appendingPathComponent("appcache/librarycache/\(id)/library_600x900.jpg")
        g.altCoverURL = "https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/\(id)/header.jpg"
        g.coverURL = Paths.exists(local.path)
            ? local.absoluteString
            : "https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/\(id)/library_600x900.jpg"
        return g
    }

    /// Steam ownership outside GOG: librarycache holds a folder per owned/seen app.
    static func knownAppIds() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("appcache/librarycache").path))?
            .filter { UInt32($0) != nil } ?? []
    }
}
