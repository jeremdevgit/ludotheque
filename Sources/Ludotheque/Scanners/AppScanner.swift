// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation

/// Local .app bundles: native Mac games, App Store / Apple Arcade, Battle.net
/// and EA installs, CrossOver bottles shortcuts and PlayCover (iOS) apps.
enum AppScanner {
    static let launcherBundles: Set<String> = Set(Launchers.bundleIds.values)
        .union([Launchers.heroic, Launchers.geforceNow, "com.isaacmarovitz.Whisky", "com.valvesoftware.steamlink",
                Bundle.main.bundleIdentifier ?? ""])

    static let knownGames: [String: Platform] = [
        "com.mojang.minecraftlauncher": .xbox,
        "org.prismlauncher.PrismLauncher": .xbox,
        "com.riotgames.LeagueofLegends.GameClient": .riot,
        "com.riotgames.leagueoflegends": .riot,
    ]

    static func scan() -> [Game] {
        let home = Paths.home
        var games = [Game]()
        var seen = Set<String>()

        func add(_ url: URL, platform forced: Platform? = nil, requireGame: Bool) {
            let path = url.resolvingSymlinksInPath().path
            guard !seen.contains(path), let info = Bundle2.info(url) else { return }
            let bundle = info["CFBundleIdentifier"] as? String ?? ""
            if launcherBundles.contains(bundle) { return }
            let category = (info["LSApplicationCategoryType"] as? String ?? "").lowercased()
            var platform = forced ?? knownGames[bundle]
            if platform == nil {
                if requireGame && !category.contains("game") { return }
                platform = Paths.exists(url.appendingPathComponent("Contents/_MASReceipt").path) ? .appstore : .mac
            }
            seen.insert(path)
            var g = Game(id: "\(platform!.rawValue)_app_\(bundle.isEmpty ? url.lastPathComponent : bundle)",
                         platform: platform!, externalId: bundle, title: Bundle2.displayName(url))
            g.installed = true
            g.macNative = platform != .crossover
            g.launchURL = url.path
            g.appPath = url.path
            games.append(g)
        }

        // Generic folders: only apps declaring a games category.
        for dir in ["/Applications", "/Applications/Games", "/Applications/Jeux", home.appendingPathComponent("Applications").path,
                    home.appendingPathComponent("Applications/Games").path] {
            for app in Bundle2.apps(in: URL(fileURLWithPath: dir), depth: 0) { add(app, requireGame: true) }
        }
        // App Store / Apple Arcade games anywhere on disk (incl. iPhone/iPad games on Apple Silicon).
        for path in spotlight("kMDItemAppStoreHasReceipt == 1 && kMDItemAppStoreCategoryType == \"*games*\"c") {
            add(URL(fileURLWithPath: path), platform: .appstore, requireGame: false)
        }

        // Battle.net installs: paths recorded in its product database.
        if let raw = try? Data(contentsOf: URL(fileURLWithPath: "/Users/Shared/Battle.net/Agent/product.db")) {
            let text = String(decoding: raw.map { $0 >= 0x20 && $0 < 0x7F ? $0 : 0x0A }, as: UTF8.self)
            let dirs = Set(text.split(separator: "\n").map(String.init).filter { $0.hasPrefix("/") && !$0.contains("Battle.net") })
            for d in dirs { for app in Bundle2.apps(in: URL(fileURLWithPath: d), depth: 1) where !app.lastPathComponent.contains("Launcher") { add(app, platform: .battlenet, requireGame: false) } }
        }
        for d in ["/Applications/World of Warcraft", "/Applications/Diablo III", "/Applications/StarCraft II", "/Applications/Hearthstone", "/Applications/Diablo IV"] {
            for app in Bundle2.apps(in: URL(fileURLWithPath: d), depth: 1) where !app.lastPathComponent.contains("Launcher") { add(app, platform: .battlenet, requireGame: false) }
        }

        // Riot: League of Legends ships a native Mac client, started by the Riot Client.
        for app in ["/Applications/League of Legends.app", home.appendingPathComponent("Applications/League of Legends.app").path]
        where Paths.exists(app) {
            add(URL(fileURLWithPath: app), platform: .riot, requireGame: false)
        }

        // EA app installs.
        for app in Bundle2.apps(in: URL(fileURLWithPath: "/Applications/EA Games"), depth: 1) { add(app, platform: .ea, requireGame: false) }

        // CrossOver / Whisky shortcuts (Windows games in Wine bottles).
        for d in [home.appendingPathComponent("Applications/CrossOver"), home.appendingPathComponent("Applications/Whisky")] {
            for app in Bundle2.apps(in: d, depth: 2) { add(app, platform: .crossover, requireGame: false) }
        }

        // PlayCover: iOS games running on Apple Silicon.
        let pc = home.appendingPathComponent("Library/Containers/io.playcover.PlayCover/Applications")
        for app in Bundle2.apps(in: pc, depth: 0) { add(app, platform: .playcover, requireGame: false) }

        // Manually added.
        for path in CustomApps.load() where Paths.exists(path) {
            add(URL(fileURLWithPath: path), platform: .custom, requireGame: false)
        }
        return games
    }
}

/// Synchronous Spotlight query (mdfind), used for App Store receipts.
func spotlight(_ query: String) -> [String] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
    p.arguments = [query]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return [] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).filter { $0.hasSuffix(".app") }
}

enum CustomApps {
    static let url = Paths.support.appendingPathComponent("custom-apps.json")
    static func load() -> [String] { (try? JSONDecoder().decode([String].self, from: Data(contentsOf: url))) ?? [] }
    static func save(_ list: [String]) { try? JSONEncoder().encode(list).write(to: url) }
}
