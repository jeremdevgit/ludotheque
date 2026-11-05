// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation
import AppKit
import CryptoKit

/// An emulator profile + the ROM folder it imports (Playnite-style emulation).
struct Emulator: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String
    var appPath: String
    var system: String          // "" = detect from file extension (RetroArch, OpenEmu…)
    var romFolder = ""
    var extensions: [String]
    var arguments = "{rom}"     // "{rom}" alone = open the file with the app

    var appExists: Bool { Paths.exists(appPath) }
}

/// A recommended emulator: how to recognise it, where to get it, how to launch games with it.
struct EmulatorPreset {
    enum Family: String, CaseIterable { case nintendo = "Nintendo", playstation = "PlayStation", xbox = "Xbox", multi = "Multi-consoles", ios = "Jeux iPhone / iPad" }

    let name: String
    let bundleIds: [String]
    let system: String
    let extensions: [String]
    let arguments: String
    var family: Family = .multi
    var consoles = ""
    var summary = ""
    var website = ""
    var download = ""
    var needs: String?                 // BIOS / firmware the user must provide
    var needsLink: String?
    var appNames: [String] = []        // fallback detection by .app name
    var availableOnMac = true
    var addable = true                 // can be used to launch games from Ludothèque

    /// Installed copy of this emulator, if any.
    var installedURL: URL? {
        if let u = bundleIds.lazy.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first { return u }
        let dirs = ["/Applications", Paths.home.appendingPathComponent("Applications").path]
        for d in dirs { for n in appNames + [name] { let p = "\(d)/\(n).app"; if Paths.exists(p) { return URL(fileURLWithPath: p) } } }
        return nil
    }
}

enum Emulation {
    struct System { let name: String; let platform: Platform; let libretro: String? }

    static let systems: [String: System] = [
        "Switch": System(name: "Nintendo Switch", platform: .nintendo, libretro: nil),
        "Wii U": System(name: "Nintendo Wii U", platform: .nintendo, libretro: nil),
        "Wii": System(name: "Nintendo Wii", platform: .nintendo, libretro: "Nintendo - Wii"),
        "GameCube": System(name: "Nintendo GameCube", platform: .nintendo, libretro: "Nintendo - GameCube"),
        "3DS": System(name: "Nintendo 3DS", platform: .nintendo, libretro: "Nintendo - Nintendo 3DS"),
        "DS": System(name: "Nintendo DS", platform: .nintendo, libretro: "Nintendo - Nintendo DS"),
        "N64": System(name: "Nintendo 64", platform: .nintendo, libretro: "Nintendo - Nintendo 64"),
        "SNES": System(name: "Super Nintendo", platform: .nintendo, libretro: "Nintendo - Super Nintendo Entertainment System"),
        "NES": System(name: "NES", platform: .nintendo, libretro: "Nintendo - Nintendo Entertainment System"),
        "GBA": System(name: "Game Boy Advance", platform: .nintendo, libretro: "Nintendo - Game Boy Advance"),
        "GBC": System(name: "Game Boy Color", platform: .nintendo, libretro: "Nintendo - Game Boy Color"),
        "GB": System(name: "Game Boy", platform: .nintendo, libretro: "Nintendo - Game Boy"),
        "PS1": System(name: "PlayStation", platform: .psn, libretro: "Sony - PlayStation"),
        "PS2": System(name: "PlayStation 2", platform: .psn, libretro: "Sony - PlayStation 2"),
        "PSP": System(name: "PlayStation Portable", platform: .psn, libretro: "Sony - PlayStation Portable"),
        "PS3": System(name: "PlayStation 3", platform: .psn, libretro: nil),
        "Xbox": System(name: "Xbox", platform: .xbox, libretro: nil),
        "Genesis": System(name: "Mega Drive / Genesis", platform: .emulation, libretro: "Sega - Mega Drive - Genesis"),
        "MasterSystem": System(name: "Master System", platform: .emulation, libretro: "Sega - Master System - Mark III"),
        "Arcade": System(name: "Arcade", platform: .emulation, libretro: nil),
    ]

    /// For multi-system emulators: file extension → system.
    static let byExtension: [String: String] = [
        "nsp": "Switch", "xci": "Switch", "wud": "Wii U", "wux": "Wii U", "rpx": "Wii U", "wua": "Wii U",
        "wbfs": "Wii", "rvz": "GameCube", "gcm": "GameCube", "3ds": "3DS", "cci": "3DS", "cia": "3DS", "nds": "DS",
        "n64": "N64", "z64": "N64", "v64": "N64", "sfc": "SNES", "smc": "SNES", "nes": "NES", "fds": "NES",
        "gba": "GBA", "gbc": "GBC", "gb": "GB", "cso": "PSP", "md": "Genesis", "gen": "Genesis", "smd": "Genesis",
        "sms": "MasterSystem",
    ]

    static let presets: [EmulatorPreset] = [
        // Nintendo
        EmulatorPreset(name: "Dolphin", bundleIds: ["org.dolphin-emu.dolphin"], system: "GameCube",
                       extensions: ["iso", "gcm", "rvz", "gcz", "ciso", "wbfs", "wad"], arguments: "-b -e {rom}",
                       family: .nintendo, consoles: "GameCube · Wii", summary: "La référence GameCube / Wii : excellente compatibilité, natif Apple Silicon.",
                       website: "https://dolphin-emu.org", download: "https://dolphin-emu.org/download/"),
        EmulatorPreset(name: "Cemu", bundleIds: ["info.cemu.Cemu"], system: "Wii U", extensions: ["wud", "wux", "rpx", "wua"], arguments: "-g {rom}",
                       family: .nintendo, consoles: "Wii U", summary: "Émulateur Wii U open source, version macOS officielle.",
                       website: "https://cemu.info", download: "https://github.com/cemu-project/Cemu/releases",
                       needs: "Jeux et clés (keys.txt) extraits de ta propre Wii U — inutile pour le format .wua déjà déchiffré."),
        EmulatorPreset(name: "Azahar", bundleIds: ["org.azahar-emu.azahar", "io.github.lime3ds.Lime3DS", "org.citra-emu.citra"], system: "3DS",
                       extensions: ["3ds", "cci", "cia", "3dsx"], arguments: "{rom}",
                       family: .nintendo, consoles: "Nintendo 3DS", summary: "Successeur de Citra / Lime3DS, maintenu et natif Apple Silicon.",
                       website: "https://azahar-emu.org", download: "https://github.com/azahar-emu/azahar/releases",
                       needs: "Jeux déchiffrés depuis ta propre console 3DS.", appNames: ["Azahar", "Lime3DS"]),
        EmulatorPreset(name: "melonDS", bundleIds: ["net.kuribo64.melonDS"], system: "DS", extensions: ["nds"], arguments: "{rom}",
                       family: .nintendo, consoles: "Nintendo DS · DSi", summary: "Émulateur DS précis, jeu en ligne local (Wi-Fi) inclus.",
                       website: "https://melonds.kuribo64.net", download: "https://melonds.kuribo64.net/downloads.php",
                       needs: "BIOS / firmware DS facultatifs (de ta console) pour une précision maximale."),
        EmulatorPreset(name: "mGBA", bundleIds: ["com.endrift.mgba"], system: "", extensions: ["gba", "gbc", "gb"], arguments: "{rom}",
                       family: .nintendo, consoles: "Game Boy · Color · Advance", summary: "Rapide et précis pour toute la famille Game Boy.",
                       website: "https://mgba.io", download: "https://mgba.io/downloads.html"),
        // PlayStation
        EmulatorPreset(name: "DuckStation", bundleIds: ["com.github.stenzek.duckstation"], system: "PS1",
                       extensions: ["cue", "chd", "m3u", "pbp", "ecm", "iso"], arguments: "-batch -- {rom}",
                       family: .playstation, consoles: "PlayStation", summary: "Le meilleur émulateur PS1 : upscaling, filtres, très léger.",
                       website: "https://www.duckstation.org", download: "https://github.com/stenzek/duckstation/releases",
                       needs: "BIOS PS1 (SCPH-xxxx) extrait de ta propre console."),
        EmulatorPreset(name: "PCSX2", bundleIds: ["net.pcsx2.pcsx2"], system: "PS2", extensions: ["iso", "chd", "cso", "gz"], arguments: "-batch -- {rom}",
                       family: .playstation, consoles: "PlayStation 2", summary: "Émulateur PS2 de référence, version macOS officielle.",
                       website: "https://pcsx2.net", download: "https://pcsx2.net/downloads/",
                       needs: "BIOS PS2 extrait de ta propre console."),
        EmulatorPreset(name: "RPCS3", bundleIds: ["net.rpcs3.rpcs3", "net.rpcs3.RPCS3"], system: "PS3", extensions: ["iso"], arguments: "--no-gui {rom}",
                       family: .playstation, consoles: "PlayStation 3", summary: "Seul émulateur PS3 viable, natif Apple Silicon. Très gourmand.",
                       website: "https://rpcs3.net", download: "https://rpcs3.net/download",
                       needs: "Firmware officiel PS3 (PS3UPDAT.PUP), téléchargeable gratuitement chez Sony.",
                       needsLink: "https://www.playstation.com/fr-fr/support/hardware/ps3/system-software/"),
        EmulatorPreset(name: "PPSSPP", bundleIds: ["org.ppsspp.ppsspp"], system: "PSP", extensions: ["iso", "cso", "pbp", "chd"], arguments: "{rom}",
                       family: .playstation, consoles: "PSP", summary: "Excellent émulateur PSP, fonctionne même sur les petites configs.",
                       website: "https://www.ppsspp.org", download: "https://www.ppsspp.org/download/"),
        // Xbox
        EmulatorPreset(name: "xemu", bundleIds: ["app.xemu.xemu", "xemu.app.xemu"], system: "Xbox", extensions: ["iso", "xiso"], arguments: "-dvd_path {rom}",
                       family: .xbox, consoles: "Xbox (2001)", summary: "Émulateur Xbox d'origine open source, version macOS officielle.",
                       website: "https://xemu.app", download: "https://github.com/xemu-project/xemu/releases",
                       needs: "BIOS, boot ROM MCPX et image du disque dur extraits de ta propre Xbox."),
        EmulatorPreset(name: "Xenia", bundleIds: [], system: "Xbox 360", extensions: [], arguments: "{rom}",
                       family: .xbox, consoles: "Xbox 360", summary: "Seul émulateur Xbox 360 avancé — disponible uniquement sur Windows et Linux, pas sur Mac.",
                       website: "https://xenia.jp", download: "https://xenia.jp/download/", availableOnMac: false, addable: false),
        // Multi
        EmulatorPreset(name: "OpenEmu", bundleIds: ["org.openemu.OpenEmu"], system: "",
                       extensions: ["nes", "sfc", "smc", "n64", "z64", "gb", "gbc", "gba", "nds", "md", "gen", "sms"], arguments: "{rom}",
                       family: .multi, consoles: "NES · SNES · N64 · Game Boy · DS · Sega…", summary: "Interface Mac soignée pour toutes les consoles rétro.",
                       website: "https://openemu.org", download: "https://openemu.org"),
        EmulatorPreset(name: "RetroArch", bundleIds: ["com.libretro.dist.RetroArch", "com.libretro.RetroArch"], system: "",
                       extensions: ["nes", "sfc", "smc", "n64", "z64", "gb", "gbc", "gba", "md", "gen", "sms"], arguments: "-L <chemin du core>.dylib {rom}",
                       family: .multi, consoles: "Presque toutes les consoles rétro", summary: "Tout-en-un basé sur les « cores » libretro. Puissant mais plus technique.",
                       website: "https://www.retroarch.com", download: "https://www.retroarch.com/?page=platforms"),
        // iOS
        EmulatorPreset(name: "PlayCover", bundleIds: ["io.playcover.PlayCover"], system: "", extensions: [], arguments: "{rom}",
                       family: .ios, consoles: "Jeux iPhone / iPad", summary: "Fait tourner des apps iOS sur Mac Apple Silicon avec mappage clavier / manette. Ses jeux apparaissent dans la plateforme « PlayCover ».",
                       website: "https://playcover.io", download: "https://github.com/PlayCover/PlayCover/releases",
                       needs: "N'utilise que des apps que tu as le droit d'installer : l'app ne fournit et ne déchiffre aucune IPA.", addable: false),
    ]

    /// Emulators installed on this Mac that aren't configured yet.
    static func detect(existing: [Emulator]) -> [Emulator] {
        presets.compactMap { p in
            guard p.addable, let url = p.installedURL, !existing.contains(where: { $0.appPath == url.path }) else { return nil }
            return Emulator(name: p.name, appPath: url.path, system: p.system, extensions: p.extensions, arguments: p.arguments)
        }
    }

    static func load() -> [Emulator] { Store<[Emulator]>.load("emulators.json", []) }
    static func save(_ e: [Emulator]) { Store<[Emulator]>.save("emulators.json", e) }

    // MARK: ROM import

    static func scan() -> [Game] {
        var games = [Game]()
        for emu in load() where !emu.romFolder.isEmpty {
            let exts = Set(emu.extensions.map { $0.lowercased() })
            guard let en = FileManager.default.enumerator(at: URL(fileURLWithPath: emu.romFolder),
                                                          includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            var count = 0
            for case let url as URL in en {
                if en.level > 6 { en.skipDescendants(); continue }
                let ext = url.pathExtension.lowercased()
                if emu.system == "PS3", url.lastPathComponent.uppercased() == "EBOOT.BIN",
                   url.deletingLastPathComponent().lastPathComponent == "USRDIR" {
                    var g = game(for: url, emulator: emu)
                    g.title = cleanTitle(url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().lastPathComponent)
                    games.append(g)
                    continue
                }
                guard exts.contains(ext) else { continue }
                // Multi-file images: keep the .cue/.m3u, not each .bin track.
                if ext == "bin", Paths.exists(url.deletingPathExtension().appendingPathExtension("cue").path) { continue }
                count += 1
                if count > 20000 { break }
                games.append(game(for: url, emulator: emu))
            }
        }
        return games
    }

    static func game(for rom: URL, emulator emu: Emulator) -> Game {
        let sysKey = emu.system.isEmpty ? (byExtension[rom.pathExtension.lowercased()] ?? "Arcade") : emu.system
        let sys = systems[sysKey] ?? System(name: sysKey, platform: .emulation, libretro: nil)
        let hash = SHA256.hash(data: Data(rom.path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let base = rom.deletingPathExtension().lastPathComponent
        var g = Game(id: "\(sys.platform.rawValue)_rom_\(hash)", platform: sys.platform, externalId: rom.path, title: cleanTitle(base))
        g.installed = true
        g.macNative = true
        g.launchURL = "emu:\(emu.id)|\(rom.path)"
        g.system = "\(sys.name) · \(emu.name)"
        if let lr = sys.libretro {
            // libretro thumbnails are named after No-Intro / Redump file names.
            let safe = base.map { "&*/:`<>?\\|\"".contains($0) ? "_" : String($0) }.joined()
            g.coverURL = "https://thumbnails.libretro.com/\(lr)/Named_Boxarts/\(safe).png"
                .addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
        }
        return g
    }

    /// "Zelda - Link's Awakening (USA) [!] [0100…][v0]" → "Zelda - Link's Awakening"
    static func cleanTitle(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "_", with: " ")
        t = t.replacingOccurrences(of: "\\s*[\\(\\[][^\\)\\]]*[\\)\\]]", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? s : t
    }

    // MARK: Launch

    /// Starts a ROM; `onExit` gets the session length in seconds.
    static func launch(_ target: String, onStart: @escaping (pid_t) -> Void) -> Bool {
        let parts = target.dropFirst(4).split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let emu = load().first(where: { $0.id == parts[0] }), emu.appExists else { return false }
        let rom = parts[1]
        let app = URL(fileURLWithPath: emu.appPath)
        let args = emu.arguments.trimmingCharacters(in: .whitespaces)
        if args == "{rom}" {
            NSWorkspace.shared.open([URL(fileURLWithPath: rom)], withApplicationAt: app, configuration: .init()) { running, _ in
                if let pid = running?.processIdentifier { DispatchQueue.main.async { onStart(pid) } }
            }
            return true
        }
        guard let exe = Bundle(url: app)?.executableURL else { return false }
        let p = Process()
        p.executableURL = exe
        p.arguments = tokenize(args).map { $0 == "{rom}" ? rom : $0.replacingOccurrences(of: "{rom}", with: rom) }
        do { try p.run() } catch { return false }
        onStart(p.processIdentifier)
        return true
    }

    /// Splits an argument string, honouring "double quotes".
    static func tokenize(_ s: String) -> [String] {
        var out = [String](), cur = "", quoted = false
        for c in s {
            if c == "\"" { quoted.toggle() }
            else if c == " " && !quoted { if !cur.isEmpty { out.append(cur); cur = "" } }
            else { cur.append(c) }
        }
        if !cur.isEmpty { out.append(cur) }
        return out.map { ($0 as NSString).expandingTildeInPath }
    }
}
