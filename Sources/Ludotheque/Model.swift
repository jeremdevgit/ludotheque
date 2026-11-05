// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation
import AppKit

enum Platform: String, Codable, CaseIterable, Identifiable, Sendable {
    case steam, epic, gog, xbox, psn, nintendo, battlenet, ea, ubisoft, itch, amazon, humble
    case rockstar, bethesda, riot, indiegala, fanatical, gmg, paradox, wargaming, legacy, meta
    case appstore, googleplay, mac, crossover, playcover, emulation, custom, other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .steam: "Steam"
        case .epic: "Epic Games"
        case .gog: "GOG"
        case .xbox: "Xbox / Microsoft"
        case .psn: "PlayStation"
        case .nintendo: "Nintendo"
        case .battlenet: "Battle.net"
        case .ea: "EA"
        case .ubisoft: "Ubisoft Connect"
        case .itch: "itch.io"
        case .amazon: "Amazon Games"
        case .humble: "Humble Bundle"
        case .rockstar: "Rockstar"
        case .bethesda: "Bethesda"
        case .riot: "Riot Games"
        case .indiegala: "IndieGala"
        case .fanatical: "Fanatical"
        case .gmg: "Green Man Gaming"
        case .paradox: "Paradox"
        case .wargaming: "Wargaming"
        case .legacy: "Legacy Games"
        case .meta: "Meta Quest"
        case .appstore: "App Store / Arcade"
        case .googleplay: "Google Play Games"
        case .mac: "Apps Mac"
        case .crossover: "CrossOver / Wine"
        case .playcover: "PlayCover (iOS)"
        case .emulation: "Rétro / Émulation"
        case .custom: "Autres (manuel)"
        case .other: "Autres"
        }
    }

    /// Used to fetch the real brand logo (favicon) of the platform.
    var domain: String? {
        switch self {
        case .steam: "store.steampowered.com"
        case .epic: "epicgames.com"
        case .gog: "gog.com"
        case .xbox: "xbox.com"
        case .psn: "playstation.com"
        case .nintendo: "nintendo.com"
        case .battlenet: "battle.net"
        case .ea: "ea.com"
        case .ubisoft: "ubisoft.com"
        case .itch: "itch.io"
        case .amazon: "gaming.amazon.com"
        case .humble: "humblebundle.com"
        case .rockstar: "rockstargames.com"
        case .bethesda: "bethesda.net"
        case .riot: "riotgames.com"
        case .indiegala: "indiegala.com"
        case .fanatical: "fanatical.com"
        case .gmg: "greenmangaming.com"
        case .paradox: "paradoxinteractive.com"
        case .wargaming: "wargaming.net"
        case .legacy: "legacygames.com"
        case .meta: "meta.com"
        case .appstore: "apps.apple.com"
        case .googleplay: "play.google.com"
        case .crossover: "codeweavers.com"
        case .playcover: "playcover.io"
        case .emulation: "retroarch.com"
        case .mac, .custom, .other: nil
        }
    }

    var symbol: String {
        switch self {
        case .xbox: "xbox.logo"
        case .psn: "playstation.logo"
        case .appstore, .mac: "apple.logo"
        case .crossover: "wineglass.fill"
        case .playcover: "iphone"
        case .emulation: "arcade.stick"
        case .custom: "square.and.pencil"
        default: "gamecontroller.fill"
        }
    }

    var color: NSColor {
        switch self {
        case .steam: NSColor(red: 0.11, green: 0.35, blue: 0.62, alpha: 1)
        case .epic: NSColor(white: 0.25, alpha: 1)
        case .gog: NSColor(red: 0.55, green: 0.18, blue: 0.75, alpha: 1)
        case .xbox: NSColor(red: 0.06, green: 0.49, blue: 0.06, alpha: 1)
        case .psn: NSColor(red: 0.0, green: 0.27, blue: 0.62, alpha: 1)
        case .nintendo: NSColor(red: 0.9, green: 0.0, blue: 0.07, alpha: 1)
        case .battlenet: NSColor(red: 0.0, green: 0.6, blue: 0.95, alpha: 1)
        case .ea: NSColor(red: 0.95, green: 0.25, blue: 0.3, alpha: 1)
        case .ubisoft: NSColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1)
        case .riot: NSColor(red: 0.92, green: 0.2, blue: 0.2, alpha: 1)
        case .googleplay: NSColor(red: 0.2, green: 0.66, blue: 0.33, alpha: 1)
        case .itch: NSColor(red: 0.98, green: 0.36, blue: 0.36, alpha: 1)
        case .amazon: NSColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1)
        case .humble: NSColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1)
        case .appstore, .mac: NSColor.systemBlue
        default: NSColor.systemGray
        }
    }

    /// Maps a GOG Galaxy release-key prefix ("xboxone_123") to a platform.
    static func fromGalaxy(_ prefix: String) -> Platform {
        switch prefix {
        case "steam": .steam
        case "epic": .epic
        case "gog": .gog
        case "xboxone", "xbox": .xbox
        case "psn": .psn
        case "nswitch", "nwiiu", "nwii", "ncube", "ngameboy", "nes", "snes": .nintendo
        case "battlenet": .battlenet
        case "origin", "ea": .ea
        case "uplay": .ubisoft
        case "itch": .itch
        case "amazon", "nile": .amazon
        case "humble": .humble
        case "rockstar": .rockstar
        case "bethesda": .bethesda
        case "riot": .riot
        case "indiegala": .indiegala
        case "fanatical": .fanatical
        case "gmg": .gmg
        case "paradox": .paradox
        case "wargaming": .wargaming
        case "oculus": .meta
        case "minecraft": .xbox // Minecraft belongs to Microsoft
        case "atari", "amiga", "zx", "c64", "sms", "segag", "sega32", "segacd", "neo", "pce", "vision", "dotemu": .emulation
        case "generic": .custom
        default: .other
        }
    }
}

/// How a game can be started right now from this Mac.
enum LaunchKind: String, Codable, CaseIterable, Sendable {
    case installed   // runs locally now
    case installable // launcher on this Mac can install it (Mac compatible)
    case cloud       // streaming (Xbox Cloud, GeForce NOW…)
    case none        // library only

    var label: String {
        switch self {
        case .installed: "Installé"
        case .installable: "Installable localement"
        case .cloud: "Cloud"
        case .none: "Bibliothèque seule"
        }
    }
    var symbol: String {
        switch self {
        case .installed: "internaldrive.fill"
        case .installable: "arrow.down.circle.fill"
        case .cloud: "cloud.fill"
        case .none: "books.vertical.fill"
        }
    }
    var rank: Int { Self.allCases.firstIndex(of: self)! }
}

struct Game: Codable, Identifiable, Hashable, Sendable {
    var id: String                // "<platform>_<externalId>"
    var platform: Platform
    var externalId: String
    var title: String
    var installed = false
    var macNative: Bool?          // nil = unknown
    var launchURL: String?        // URL scheme or file path to open to play
    var appPath: String?          // local .app, used for the icon fallback
    var storeURL: String?
    var coverURL: String?         // remote or file:// URL
    var lastPlayed: Date?
    var playtimeMinutes: Int?
    var isDLC = false
    var altCoverURL: String?      // used when coverURL fails
    var dbPlatform: String?       // GamesDB platform id when not derivable from `platform`
    var manualId: String?         // set for games entered by hand
    var cloud: Bool?              // streaming link
    var system: String?           // emulated console, e.g. "Nintendo Switch · Ryujinx"

    var hasTitle: Bool { !title.isEmpty && title != externalId }

    var launchKind: LaunchKind {
        if installed && launchURL != nil { return .installed }
        if cloud == true || (platform == .xbox && macNative != true) { return launchURL != nil ? .cloud : .none }
        if macNative == true, launchURL != nil { return .installable }
        return .none
    }

    var sortTitle: String {
        let t = title.lowercased()
        for p in ["the ", "a "] where t.hasPrefix(p) { return String(t.dropFirst(p.count)) }
        return t
    }

    var normalizedTitle: String {
        title.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Key used to group the same game owned on several platforms.
    var groupKey: String {
        var t = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        for s in ["™", "®", "©"] { t = t.replacingOccurrences(of: s, with: "") }
        t = t.replacingOccurrences(of: "&", with: " and ")
        t = t.replacingOccurrences(of: "’", with: "'")
        // Publisher / franchise prefixes some stores drop ("Tom Clancy's Rainbow Six Siege" = "Rainbow Six Siege").
        for p in ["tom clancy's ", "tom clancys ", "sid meier's ", "sid meiers ", "disney's ", "disney "] where t.hasPrefix(p) {
            t = String(t.dropFirst(p.count))
        }
        // Store-specific suffixes that don't make it a different game.
        let suffixes = ["game of the year edition", "goty edition", "game of the year", "goty", "definitive edition",
                        "complete edition", "deluxe edition", "standard edition", "enhanced edition", "ultimate edition",
                        "gold edition", "windows 10 edition", "for windows 10", "windows edition", "pc edition",
                        "xbox one edition", "xbox series x|s", "ps4 & ps5", "ps4", "ps5", "(pc)", "pc", "mac"]
        var changed = true
        while changed {
            changed = false
            t = t.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            for s in suffixes where t.hasSuffix(s) && t.count > s.count + 2 {
                t = String(t.dropLast(s.count)); changed = true
            }
        }
        let key = t.filter { $0.isLetter || $0.isNumber }
        return key.isEmpty ? id : key
    }

    /// Merge info about the same game coming from another source.
    mutating func merge(_ o: Game) {
        if !hasTitle && o.hasTitle { title = o.title }
        if o.installed && !installed { installed = true; launchURL = o.launchURL ?? launchURL }
        if launchURL == nil { launchURL = o.launchURL }
        if macNative == nil || o.macNative == true { macNative = o.macNative ?? macNative }
        appPath = appPath ?? o.appPath
        storeURL = storeURL ?? o.storeURL
        if coverURL == nil || (o.coverURL?.hasPrefix("file://") ?? false) { coverURL = o.coverURL ?? coverURL }
        altCoverURL = altCoverURL ?? o.altCoverURL
        if let d = o.lastPlayed, d > (lastPlayed ?? .distantPast) { lastPlayed = d }
        if let m = o.playtimeMinutes, m > (playtimeMinutes ?? 0) { playtimeMinutes = m }
        isDLC = isDLC || o.isDLC
    }
}

/// A set of games that are the same title on different platforms.
struct GameGroup: Identifiable {
    let id: String
    let games: [Game]        // best way to play first
    let key: String          // group key (user data are stored under it)

    var primary: Game { games[0] }
    var title: String { primary.title }
    var coverGame: Game {
        games.first { $0.coverURL?.hasPrefix("file://") == true } ?? games.first { $0.coverURL != nil } ?? primary
    }
    let platforms: [Platform]
    /// Best version on each platform (games are already sorted best first).
    let bestPerPlatform: [Game]
    let lastPlayed: Date?
    /// Playtime per platform. Several releases on the same platform share one account → max, not sum.
    let playtimeByPlatform: [(Platform, Int)]

    /// Total playtime. Launchers that mirror another one (Ubisoft Connect / EA app started from Steam
    /// report the same hours) are counted once: values within 10 % of a larger one are dropped.
    let playtime: Int

    /// Derived values are computed once here (tiles read them on every redraw).
    init(id: String, games: [Game], key: String? = nil) {
        self.id = id
        let sorted = games.sorted { ($0.launchKind.rank, $0.platform.name) < ($1.launchKind.rank, $1.platform.name) }
        self.games = sorted
        self.key = key ?? sorted[0].groupKey
        var seen = Set<Platform>()
        bestPerPlatform = sorted.filter { seen.insert($0.platform).inserted }
        platforms = bestPerPlatform.map(\.platform)
        lastPlayed = sorted.compactMap(\.lastPlayed).max()
        var best = [Platform: Int]()
        for g in sorted { if let m = g.playtimeMinutes, m > 0 { best[g.platform] = max(best[g.platform] ?? 0, m) } }
        playtimeByPlatform = best.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
        // Launchers mirroring another one (Ubisoft Connect / EA app started from Steam) are counted once.
        var kept = [Int]()
        for (_, m) in playtimeByPlatform where !kept.contains(where: { Double(m) >= Double($0) * 0.9 }) { kept.append(m) }
        playtime = kept.reduce(0, +)
    }
}

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let appSupport = home.appendingPathComponent("Library/Application Support")
    static let support: URL = dir(appSupport.appendingPathComponent("Ludotheque"))
    static let caches: URL = dir(home.appendingPathComponent("Library/Caches/Ludotheque/covers"))
    static let logos: URL = dir(home.appendingPathComponent("Library/Caches/Ludotheque/logos"))
    static let api: URL = dir(support.appendingPathComponent("api"))
    static let userCovers: URL = dir(support.appendingPathComponent("covers"))

    static func dir(_ u: URL) -> URL {
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }
}

/// Short-lived cache for "is this app installed?" (LaunchServices + disk lookups). Views ask it for
/// every row and every context menu at each redraw; the answer doesn't change within seconds.
enum AppLookup {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: (at: Date, url: URL?)] = [:]
    nonisolated(unsafe) private static var numbers: [String: (at: Date, value: Int)] = [:]

    static func url(_ key: String, ttl: TimeInterval = 10, _ resolve: () -> URL?) -> URL? {
        lock.lock()
        if let c = cache[key], Date().timeIntervalSince(c.at) < ttl { lock.unlock(); return c.url }
        lock.unlock()
        let u = resolve()
        lock.lock(); cache[key] = (Date(), u); lock.unlock()
        return u
    }

    static func number(_ key: String, ttl: TimeInterval, _ resolve: () -> Int) -> Int {
        lock.lock()
        if let c = numbers[key], Date().timeIntervalSince(c.at) < ttl { lock.unlock(); return c.value }
        lock.unlock()
        let v = resolve()
        lock.lock(); numbers[key] = (Date(), v); lock.unlock()
        return v
    }
}

enum Launchers {
    static let bundleIds: [Platform: String] = [
        .steam: "com.valvesoftware.steam",
        .epic: "com.epicgames.EpicGamesLauncher",
        .gog: "com.gog.galaxy",
        .battlenet: "net.battle.app",
        .ea: "com.ea.mac.eaapp",
        .itch: "io.itch.mac",
        .crossover: "com.codeweavers.CrossOver",
        .playcover: "io.playcover.PlayCover",
    ]
    static let heroic = "com.heroicgameslauncher.hgl"
    static let geforceNow = "com.nvidia.gfnpc.mall"

    static func installed(_ bundleId: String) -> Bool {
        AppLookup.url("bundle:" + bundleId) { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) } != nil
    }
    static func installed(_ p: Platform) -> Bool {
        bundleIds[p].map(installed) ?? false
    }
}

extension String {
    var urlQueryEscaped: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?/:"))) ?? self
    }
}
