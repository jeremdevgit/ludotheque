// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation
import AppKit

/// "Jouer aux jeux Windows": checks the Mac, recommends the simplest way to run each
/// Windows-only game (Heroic, CrossOver/Whisky, cloud) and automates the boring steps.
enum WinTool: String, CaseIterable, Identifiable {
    case heroic, crossover, whisky, sikarugir, portingKit, parallels, geforceNow, xboxCloud

    var id: String { rawValue }
    var name: String {
        switch self {
        case .heroic: "Heroic Games Launcher"
        case .crossover: "CrossOver"
        case .whisky: "Whisky"
        case .sikarugir: "Sikarugir"
        case .portingKit: "Porting Kit"
        case .parallels: "Parallels Desktop"
        case .geforceNow: "GeForce NOW"
        case .xboxCloud: "Xbox Cloud Gaming"
        }
    }
    var summary: String {
        switch self {
        case .heroic: String(localized: "Gratuit. Le plus simple pour Epic Games, GOG et Amazon : connexion à tes comptes, installation et lancement en un clic (Wine + Game Porting Toolkit intégrés).")
        case .crossover: String(localized: "Payant (essai 14 jours). Le plus compatible : Steam, Battle.net, EA, Ubisoft… dans des « bouteilles » Windows, avec D3DMetal d'Apple. Recommandé pour Steam.")
        case .whisky: String(localized: "Gratuit, interface simple basée sur le Game Porting Toolkit. N'est plus maintenu depuis 2025 mais fonctionne encore pour beaucoup de jeux.")
        case .sikarugir: String(localized: "Gratuit (successeur de Wineskin/Kegworks) : crée une app Mac autonome par jeu. Plus technique.")
        case .portingKit: String(localized: "Gratuit : catalogue de jeux pré-configurés (« ports ») à installer en quelques clics.")
        case .parallels: String(localized: "Payant : vrai Windows 11 ARM en machine virtuelle. Compatible avec plus de logiciels, mais pas avec les anti-triche.")
        case .geforceNow: String(localized: "Streaming : jeux Steam/Epic/Ubisoft que tu possèdes, en haute qualité, même ceux avec anti-triche. Gratuit avec file d'attente.")
        case .xboxCloud: String(localized: "Streaming via le navigateur avec le Game Pass Ultimate. Aucune installation.")
        }
    }
    var bundleIds: [String] {
        switch self {
        case .heroic: [Launchers.heroic]
        case .crossover: ["com.codeweavers.CrossOver"]
        case .whisky: ["com.isaacmarovitz.Whisky"]
        case .parallels: ["com.parallels.desktop.console"]
        case .geforceNow: [Launchers.geforceNow]
        default: []
        }
    }
    var appNames: [String] {
        switch self {
        case .sikarugir: ["Sikarugir Creator", "Sikarugir"]
        case .portingKit: ["Porting Kit"]
        default: []
        }
    }
    var website: String {
        switch self {
        case .heroic: "https://heroicgameslauncher.com"
        case .crossover: "https://www.codeweavers.com/crossover"
        case .whisky: "https://getwhisky.app"
        case .sikarugir: "https://github.com/Sikarugir-App/Sikarugir"
        case .portingKit: "https://www.portingkit.com"
        case .parallels: "https://www.parallels.com/products/desktop/"
        case .geforceNow: "https://www.nvidia.com/fr-fr/geforce-now/download/"
        case .xboxCloud: "https://www.xbox.com/fr-FR/play"
        }
    }
    var free: Bool { ![.crossover, .parallels].contains(self) }

    var installedURL: URL? {
        if self == .xboxCloud { return nil }
        return AppLookup.url("wintool:" + rawValue) { resolveInstalledURL() }
    }
    private func resolveInstalledURL() -> URL? {
        if let u = bundleIds.lazy.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first { return u }
        for d in ["/Applications", Paths.home.appendingPathComponent("Applications").path] {
            for n in appNames { let p = "\(d)/\(n).app"; if Paths.exists(p) { return URL(fileURLWithPath: p) } }
        }
        return nil
    }
    var installed: Bool { self == .xboxCloud || installedURL != nil }
}

/// Official Windows launcher installers (HTTPS, publishers' own servers only).
enum WinInstaller: String, CaseIterable, Identifiable {
    case steam, battlenet, ea, ubisoft, rockstar, epic
    var id: String { rawValue }
    var name: String {
        switch self {
        case .steam: "Steam"
        case .battlenet: "Battle.net"
        case .ea: "EA app"
        case .ubisoft: "Ubisoft Connect"
        case .rockstar: "Rockstar Games Launcher"
        case .epic: "Epic Games (Windows)"
        }
    }
    var platform: Platform {
        switch self {
        case .steam: .steam
        case .battlenet: .battlenet
        case .ea: .ea
        case .ubisoft: .ubisoft
        case .rockstar: .rockstar
        case .epic: .epic
        }
    }
    var url: String {
        switch self {
        case .steam: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"
        case .battlenet: "https://www.battle.net/download/getInstallerForGame?os=win&gameProgram=BATTLENET_APP&version=Live"
        case .ea: "https://origin-a.akamaihd.net/EA-Desktop-Client-Download/installer-releases/EAappInstaller.exe"
        case .ubisoft: "https://static3.cdn.ubi.com/orbit/launcher_installer/UbisoftConnectInstaller.exe"
        case .rockstar: "https://gamedownloads.rockstargames.com/public/installer/Rockstar-Games-Launcher.exe"
        case .epic: "https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi"
        }
    }
    var fileName: String {
        switch self {
        case .battlenet: "Battle.net-Setup.exe"
        case .epic: "EpicGamesLauncherInstaller.msi"
        default: URL(string: url)!.lastPathComponent
        }
    }
    static let allowedHosts: Set<String> = ["cdn.akamai.steamstatic.com", "www.battle.net", "origin-a.akamaihd.net", "static3.cdn.ubi.com",
                                            "gamedownloads.rockstargames.com", "launcher-public-service-prod06.ol.epicgames.com"]
}

struct AntiCheatInfo: Codable, Hashable {
    let status: String          // AreWeAntiCheatYet: Supported / Running / Broken / Denied / Planned
    let anticheats: [String]
    /// Anti-cheat support on Linux/Proton does not carry over to Wine on macOS: only "Running" games
    /// (anti-cheat not enforced on Wine) have a chance.
    var blocksMac: Bool { !anticheats.isEmpty && status != "Running" }
}

enum WinRoute: Equatable {
    case heroic, crossover, cloud(String), antiCheatCloud, xboxCloud
    var label: String {
        switch self {
        case .heroic: String(localized: "Heroic (gratuit)")
        case .crossover: "CrossOver / Whisky"
        case .cloud(let s): s
        case .antiCheatCloud: String(localized: "Cloud uniquement (anti-triche)")
        case .xboxCloud: "Xbox Cloud Gaming"
        }
    }
    var symbol: String {
        switch self {
        case .heroic: "shield.lefthalf.filled"
        case .crossover: "wineglass.fill"
        case .cloud, .xboxCloud: "cloud.fill"
        case .antiCheatCloud: "exclamationmark.shield.fill"
        }
    }
}

@MainActor
final class WindowsGaming: ObservableObject {
    static let shared = WindowsGaming()
    @Published private(set) var antiCheat: [String: AntiCheatInfo] = Store<[String: AntiCheatInfo]>.load("anticheat.json", [:])
    @Published private(set) var rosetta = Paths.exists("/Library/Apple/usr/share/rosetta/rosetta")
    @Published var busy: String?

    static var appleSilicon: Bool {
        var v: Int32 = 0, size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &v, &size, nil, 0) == 0 && v == 1
    }
    static var freeDiskGB: Int {
        AppLookup.number("freeDiskGB", ttl: 30) {
            let v = try? Paths.home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return Int((v?.volumeAvailableCapacityForImportantUsage ?? 0) / 1_000_000_000)
        }
    }

    // MARK: Anti-cheat database (AreWeAntiCheatYet, refreshed weekly)

    func loadAntiCheat(force: Bool = false) async {
        let fresh = (UserDefaults.standard.object(forKey: "anticheatAt") as? Date).map { Date().timeIntervalSince($0) < 7 * 86400 } ?? false
        if !force && fresh && !antiCheat.isEmpty { return }
        TaskCenter.shared.begin("anticheat", String(localized: "Base de compatibilité anti-triche"))
        defer { TaskCenter.shared.end("anticheat") }
        guard let (d, r) = try? await HTTP.raw("https://raw.githubusercontent.com/AreWeAntiCheatYet/AreWeAntiCheatYet/HEAD/games.json"),
              r.statusCode == 200, let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return }
        var out = [String: AntiCheatInfo]()
        for g in arr {
            guard let name = g["name"] as? String, let status = g["status"] as? String else { continue }
            let ac = (g["anticheats"] as? [String]) ?? []
            out[Integrations.norm(name)] = AntiCheatInfo(status: status, anticheats: ac)
        }
        antiCheat = out
        Store<[String: AntiCheatInfo]>.save("anticheat.json", out)
        UserDefaults.standard.set(Date(), forKey: "anticheatAt")
    }

    func antiCheat(for g: GameGroup) -> AntiCheatInfo? {
        let keys = [Integrations.norm(g.title)] + g.games.map { Integrations.norm($0.title) }
        return keys.lazy.compactMap { self.antiCheat[$0] }.first
    }

    // MARK: Windows-only games and their best route

    static let pcStores: Set<Platform> = [.steam, .epic, .gog, .ea, .ubisoft, .battlenet, .amazon, .itch, .humble, .rockstar,
                                          .bethesda, .indiegala, .fanatical, .gmg, .paradox, .wargaming, .riot, .legacy, .xbox]

    /// Owned on a PC store, with no native Mac version anywhere.
    func windowsOnly(_ lib: Library) -> [GameGroup] {
        lib.groups.filter { g in
            !g.games.contains { $0.macNative == true || $0.launchKind == .installed } &&
            g.games.contains { Self.pcStores.contains($0.platform) && $0.cloud != true }
        }
    }

    func route(_ g: GameGroup) -> WinRoute {
        if let ac = antiCheat(for: g), ac.blocksMac { return .antiCheatCloud }
        let p = Set(g.platforms)
        if !p.isDisjoint(with: [.epic, .gog, .amazon]) { return .heroic }
        if p == [.xbox] { return .xboxCloud }
        return .crossover
    }

    // MARK: Actions

    /// Installs Rosetta 2 (needed by Wine / x86 games), asking for the admin password.
    func installRosetta() async {
        busy = String(localized: "Installation de Rosetta 2…")
        defer { busy = nil }
        let ok = await Task.detached { () -> Bool in
            var err: NSDictionary?
            let s = NSAppleScript(source: "do shell script \"/usr/sbin/softwareupdate --install-rosetta --agree-to-license\" with administrator privileges")
            s?.executeAndReturnError(&err)
            return err == nil
        }.value
        rosetta = Paths.exists("/Library/Apple/usr/share/rosetta/rosetta")
        if !ok && !rosetta { busy = nil }
    }

    /// Downloads an official Windows launcher installer and opens it in CrossOver / Whisky,
    /// which start their install wizard in a Windows "bottle".
    func install(_ i: WinInstaller, with tool: WinTool) async -> String {
        guard let app = tool.installedURL else { return String(localized: "\(tool.name) n'est pas installé") }
        guard let url = URL(string: i.url), let host = url.host, WinInstaller.allowedHosts.contains(host) else { return String(localized: "Lien non autorisé") }
        let dir = Paths.dir(Paths.home.appendingPathComponent("Downloads/Ludothèque"))
        let dest = dir.appendingPathComponent(i.fileName)
        TaskCenter.shared.begin("wininstall", String(localized: "Téléchargement de \(i.name)"))
        defer { TaskCenter.shared.end("wininstall") }
        do {
            let (tmp, resp) = try await URLSession.shared.download(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return String(localized: "Téléchargement impossible (\(i.name))") }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
        } catch { return String(localized: "Téléchargement impossible : \(error.localizedDescription)") }
        NSWorkspace.shared.open([dest], withApplicationAt: app, configuration: .init()) { _, _ in }
        return String(localized: "\(i.name) s'ouvre dans \(tool.name) : suis l'assistant d'installation")
    }

    func open(_ tool: WinTool) {
        if let app = tool.installedURL { NSWorkspace.shared.openApplication(at: app, configuration: .init()) }
        else if let u = URL(string: tool.website) { NSWorkspace.shared.open(u) }
    }

    static func compatLinks(_ title: String) -> [(String, URL)] {
        let q = title.urlQueryEscaped
        return [("AppleGamingWiki", "https://www.applegamingwiki.com/w/index.php?search=\(q)"),
                (String(localized: "Base CodeWeavers"), "https://www.codeweavers.com/compatibility?name=\(q)")].compactMap { n, u in URL(string: u).map { (n, $0) } }
    }
}
