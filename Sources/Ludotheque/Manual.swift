// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation

/// A game entered by hand (any platform, physical copy, cloud service…).
struct ManualGame: Codable, Identifiable, Hashable {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case none, app, url, cloud
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: String(localized: "Aucun")
            case .app: String(localized: "Application Mac")
            case .url: String(localized: "Lien / launcher")
            case .cloud: String(localized: "Cloud (streaming)")
            }
        }
    }

    var id = UUID().uuidString
    var title = ""
    var platform: Platform = .custom
    var mode: Mode = .none
    var target = ""          // .app path or URL
    var storeURL = ""
    var coverURL = ""
    var installed = false
    var macNative = true
    var playtimeHours = 0

    func game() -> Game {
        var g = Game(id: "\(platform.rawValue)_manual_\(id)", platform: platform, externalId: id, title: title)
        g.manualId = id
        let t = target.trimmingCharacters(in: .whitespaces)
        if mode != .none, !t.isEmpty { g.launchURL = t }
        switch mode {
        case .app: g.installed = true; g.macNative = true; g.appPath = t
        case .url: g.installed = installed; g.macNative = macNative
        case .cloud: g.cloud = true; g.macNative = false
        case .none: g.macNative = macNative
        }
        g.storeURL = storeURL.isEmpty ? nil : storeURL
        g.coverURL = coverURL.isEmpty ? nil : coverURL
        if playtimeHours > 0 { g.playtimeMinutes = playtimeHours * 60 }
        return g
    }
}

enum ManualStore {
    static let url = Paths.support.appendingPathComponent("manual-games.json")
    static func load() -> [ManualGame] { (try? JSONDecoder().decode([ManualGame].self, from: Data(contentsOf: url))) ?? [] }
    static func save(_ list: [ManualGame]) { try? JSONEncoder().encode(list).write(to: url, options: .atomic) }

    static func upsert(_ m: ManualGame) {
        var list = load()
        if let i = list.firstIndex(where: { $0.id == m.id }) { list[i] = m } else { list.append(m) }
        save(list)
    }
    static func delete(_ id: String) { save(load().filter { $0.id != id }) }
    static func get(_ id: String) -> ManualGame? { load().first { $0.id == id } }
}

/// Cover search for the manual form: Steam store search needs no API key
/// and covers most PC games; results use the 600x900 library artwork.
enum CoverSearch {
    struct Hit: Identifiable, Hashable { let id: String; let name: String; let cover: String; let alt: String }

    static func search(_ term: String) async -> [Hit] {
        let q = term.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let r = try? await HTTP.json("https://store.steampowered.com/api/storesearch/?term=\(q.urlQueryEscaped)&l=french&cc=FR")
        else { return [] }
        return (r["items"] as? [[String: Any]] ?? []).compactMap { it in
            guard let id = Integrations.string(it["id"]), let name = it["name"] as? String else { return nil }
            let base = "https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/\(id)"
            return Hit(id: id, name: name, cover: "\(base)/library_600x900.jpg", alt: "\(base)/header.jpg")
        }
    }
}
