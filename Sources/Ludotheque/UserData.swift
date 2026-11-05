// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation
import SwiftUI

/// Completion status, as in Playnite.
enum Completion: String, Codable, CaseIterable, Identifiable {
    case none, planned, playing, onHold, beaten, completed, abandoned
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "Pas commencé"
        case .planned: "À jouer"
        case .playing: "En cours"
        case .onHold: "En pause"
        case .beaten: "Terminé"
        case .completed: "Complété à 100 %"
        case .abandoned: "Abandonné"
        }
    }
    var symbol: String {
        switch self {
        case .none: "circle"
        case .planned: "bookmark.fill"
        case .playing: "play.circle.fill"
        case .onHold: "pause.circle.fill"
        case .beaten: "flag.checkered"
        case .completed: "trophy.fill"
        case .abandoned: "xmark.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .none: .secondary
        case .planned: .purple
        case .playing: .blue
        case .onHold: .orange
        case .beaten: .green
        case .completed: .yellow
        case .abandoned: .red
        }
    }
}

/// Everything the user sets on a game; keyed by group key so it applies to
/// every platform version of the same game.
struct UserEntry: Codable, Equatable {
    var status: Completion?
    var rating: Int?            // 1…5
    var notes: String?
    var tags: [String]?
    var customTitle: String?
    var customCover: String?
    var trackedMinutes: Int?    // measured by Ludothèque's playtime counter
    var lastLaunched: Date?
    var launchCount: Int?
    var added: Date?
}

/// A saved combination of view, filters and sort (Playnite "filter presets").
struct Preset: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var scope: Scope
    var filters: Filters
    var sort: SortOrder
}

extension Scope: Codable {
    init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        switch s {
        case "all": self = .all
        case "playable": self = .playable
        case "installed": self = .installed
        case "installable": self = .installable
        case "cloud": self = .cloud
        case "favorites": self = .favorites
        case "recent": self = .recent
        case "performance": self = .performance
        case "emulators": self = .emulators
        case "home": self = .home
        case "freeGames": self = .freeGames
        case "wishlist": self = .wishlist
        case "profile": self = .profile
        case "options": self = .options
        case "statistics": self = .statistics
        case "search": self = .search
        case "freeLoot": self = .freeLoot
        case "achievements": self = .achievements
        case "windows": self = .windows
        case "refresh": self = .refresh
        default:
            if s.hasPrefix("platform:"), let p = Platform(rawValue: String(s.dropFirst(9))) { self = .platform(p) }
            else if s.hasPrefix("preset:") { self = .preset(String(s.dropFirst(7))) }
            else { self = .all }
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .platform(let p): try c.encode("platform:\(p.rawValue)")
        case .preset(let id): try c.encode("preset:\(id)")
        default: try c.encode(String(describing: self))
        }
    }
}

enum Store<T: Codable> {
    static func load(_ name: String, _ fallback: T) -> T {
        (try? JSONDecoder().decode(T.self, from: Data(contentsOf: Paths.support.appendingPathComponent(name)))) ?? fallback
    }
    static func save(_ name: String, _ value: T) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(value).write(to: Paths.support.appendingPathComponent(name), options: .atomic)
    }
}
