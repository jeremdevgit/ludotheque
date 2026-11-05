// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation
import AppKit
import UniformTypeIdentifiers

/// Import / export of the games list (CSV, JSON, HTML) — compatible with
/// spreadsheets and exports from other trackers (Backloggd, HowLongToBeat, Playnite…).
@MainActor
enum DataTransfer {
    enum Format: String, CaseIterable, Identifiable {
        case csv = "CSV", json = "JSON", html = "HTML"
        var id: String { rawValue }
        var type: UTType { self == .csv ? .commaSeparatedText : self == .json ? .json : .html }
    }

    enum Selection: String, CaseIterable, Identifiable {
        case all = "Toute la bibliothèque", visible = "Vue actuelle", installed = "Jeux installés", played = "Jeux joués", favorites = "Favoris"
        var id: String { rawValue }
    }

    struct Row {
        var title: String
        var platform: Platform?
        var status: Completion?
        var rating: Int?
        var minutes: Int?
        var tags: [String] = []
        var notes: String?
    }

    struct Preview {
        let rows: [Row]
        let matched: Int
        var new: Int { rows.count - matched }
    }

    // MARK: Export

    static func groups(_ lib: Library, _ s: Selection) -> [GameGroup] {
        let all = lib.groups.sorted { lib.title($0).lowercased() < lib.title($1).lowercased() }
        switch s {
        case .all: return all
        case .visible: return lib.visibleGroups
        case .installed: return all.filter { $0.primary.launchKind == .installed }
        case .played: return all.filter { lib.playtime($0) > 0 || lib.lastPlayed($0) != nil }
        case .favorites: return all.filter(lib.isFavorite)
        }
    }

    static func export(_ lib: Library, _ selection: Selection, _ format: Format) -> Data? {
        let list = groups(lib, selection)
        let iso = ISO8601DateFormatter()
        func record(_ g: GameGroup) -> [String: Any] {
            let u = lib.entry(g.key)
            var r: [String: Any] = ["titre": lib.title(g), "plateformes": g.platforms.map(\.name), "disponibilite": g.primary.launchKind.label,
                                    "statut": lib.statusOf(g).label, "temps_de_jeu_min": lib.playtime(g), "favori": lib.isFavorite(g)]
            if let n = u.rating { r["note"] = n }
            if let d = lib.lastPlayed(g) { r["derniere_partie"] = iso.string(from: d) }
            if let t = u.tags, !t.isEmpty { r["tags"] = t }
            if let n = u.notes, !n.isEmpty { r["notes"] = n }
            return r
        }
        switch format {
        case .json:
            return try? JSONSerialization.data(withJSONObject: list.map(record), options: [.prettyPrinted, .sortedKeys])
        case .csv:
            func esc(_ s: String) -> String { CSV.escape(s) }
            var lines = ["Titre,Plateformes,Disponibilité,Statut,Note,Temps de jeu (min),Dernière partie,Favori,Tags,Notes"]
            for g in list {
                let u = lib.entry(g.key)
                lines.append([esc(lib.title(g)), esc(g.platforms.map(\.name).joined(separator: ", ")), esc(g.primary.launchKind.label),
                              esc(lib.statusOf(g).label), "\(u.rating ?? 0)", "\(lib.playtime(g))", lib.lastPlayed(g).map(iso.string) ?? "",
                              lib.isFavorite(g) ? "oui" : "", esc((u.tags ?? []).joined(separator: ", ")), esc(u.notes ?? "")].joined(separator: ","))
            }
            return lines.joined(separator: "\n").data(using: .utf8)
        case .html:
            func h(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;") }
            var rows = ""
            for g in list {
                let m = lib.playtime(g)
                rows += "<tr><td>\(h(lib.title(g)))</td><td>\(h(g.platforms.map(\.name).joined(separator: ", ")))</td><td>\(h(lib.statusOf(g).label))</td><td>\(String(repeating: "★", count: lib.entry(g.key).rating ?? 0))</td><td>\(m / 60) h \(m % 60) min</td></tr>\n"
            }
            let html = """
            <!doctype html><html lang="fr"><meta charset="utf-8"><title>Ma ludothèque</title>
            <style>body{font:14px -apple-system,sans-serif;margin:32px;color:#222}h1{margin:0 0 4px}table{border-collapse:collapse;width:100%;margin-top:16px}
            th,td{text-align:left;padding:6px 10px;border-bottom:1px solid #ddd}th{background:#f4f4f6}tr:hover td{background:#fafafa}
            @media(prefers-color-scheme:dark){body{background:#1c1c1e;color:#eee}th{background:#2c2c2e}td{border-color:#333}tr:hover td{background:#242426}}</style>
            <h1>Ma ludothèque</h1><p>\(list.count) jeux · exporté le \(Date().formatted(date: .long, time: .omitted))</p>
            <table><tr><th>Jeu</th><th>Plateformes</th><th>Statut</th><th>Note</th><th>Temps de jeu</th></tr>
            \(rows)</table></html>
            """
            return html.data(using: .utf8)
        }
    }

    // MARK: Import

    static func read(_ url: URL, _ lib: Library) -> Preview? {
        var rows = [Row]()
        if url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url), let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
            let list = (obj as? [[String: Any]]) ?? ((obj as? [String: Any])?.values.first { $0 is [[String: Any]] } as? [[String: Any]]) ?? []
            for o in list {
                let lower = Dictionary(uniqueKeysWithValues: o.map { ($0.key.lowercased(), $0.value) })
                func val(_ keys: [String]) -> Any? { keys.lazy.compactMap { lower[$0] }.first }
                guard let t = val(["titre", "title", "name", "nom", "game", "jeu"]) as? String, !t.isEmpty else { continue }
                var r = Row(title: t)
                r.platform = platform(val(["plateformes", "platform", "plateforme", "platforms", "source", "store"]))
                r.status = (val(["statut", "status", "completion", "completionstatus"]) as? String).flatMap(status)
                r.rating = (val(["note", "rating", "score", "userscore"]) as? NSNumber).map { normaliseRating($0.doubleValue) }
                if let m = val(["temps_de_jeu_min", "playtime_minutes", "minutes"]) as? NSNumber { r.minutes = m.intValue }
                else if let s = val(["playtime"]) as? NSNumber { r.minutes = s.intValue / 60 }   // Playnite: seconds
                else if let hrs = val(["hours", "heures"]) as? NSNumber { r.minutes = Int(hrs.doubleValue * 60) }
                r.tags = (val(["tags"]) as? [String]) ?? []
                r.notes = val(["notes", "note_perso", "review"]) as? String
                rows.append(r)
            }
        } else {
            guard let table = CSV.read(url), let header = table.first?.map({ $0.lowercased().trimmingCharacters(in: .whitespaces) }) else { return nil }
            func col(_ names: [String]) -> Int? { header.firstIndex { h in names.contains { h == $0 || h.hasPrefix($0) } } }
            guard let tc = col(["titre", "title", "name", "nom", "game", "jeu"]) else { return nil }
            let pc = col(["plateforme", "platform", "source", "store"]), sc = col(["statut", "status", "completion"])
            let rc = col(["note", "rating", "score"]), tg = col(["tags"]), nc = col(["notes", "review"])
            let mc = col(["temps de jeu (min)", "minutes", "playtime (min)"]), hc = col(["temps de jeu", "playtime", "hours", "heures"])
            for line in table.dropFirst() where line.count > tc {
                func cell(_ i: Int?) -> String? { i.flatMap { line.count > $0 ? line[$0].trimmingCharacters(in: .whitespaces) : nil }.flatMap { $0.isEmpty ? nil : $0 } }
                guard let t = cell(tc) else { continue }
                var r = Row(title: t)
                r.platform = platform(cell(pc))
                r.status = cell(sc).flatMap(status)
                r.rating = cell(rc).flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }.map(normaliseRating)
                if let m = cell(mc).flatMap({ Int($0) }) { r.minutes = m }
                else if let hrs = cell(hc).flatMap({ Double($0.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }) }) { r.minutes = Int(hrs * 60) }
                r.tags = cell(tg)?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
                r.notes = cell(nc)
                rows.append(r)
            }
        }
        let titles = Set(lib.groups.map { Integrations.norm(lib.title($0)) })
        return Preview(rows: rows, matched: rows.filter { titles.contains(Integrations.norm($0.title)) }.count)
    }

    /// Applies an import: updates matching games, optionally creates the others as manual games.
    static func apply(_ p: Preview, createMissing: Bool, lib: Library) -> String {
        var updated = 0, created = 0
        for r in p.rows {
            let key: String
            if let g = lib.groups.first(where: { Integrations.norm(lib.title($0)) == Integrations.norm(r.title) }) {
                key = g.key
                if let m = r.minutes, m > lib.playtime(g) {
                    let extra = m - lib.playtime(g)
                    lib.update(key) { $0.trackedMinutes = ($0.trackedMinutes ?? 0) + extra }
                }
                updated += 1
            } else if createMissing {
                var m = ManualGame()
                m.title = r.title
                m.platform = r.platform ?? .custom
                m.playtimeHours = (r.minutes ?? 0) / 60
                ManualStore.upsert(m)
                key = m.game().groupKey
                created += 1
            } else { continue }
            lib.update(key) { e in
                if let s = r.status { e.status = s }
                if let n = r.rating, n > 0 { e.rating = n }
                if !r.tags.isEmpty { e.tags = Array(Set((e.tags ?? []) + r.tags)).sorted() }
                if let n = r.notes, (e.notes ?? "").isEmpty { e.notes = n }
            }
        }
        Task { await lib.refresh(sync: false) }
        return "\(updated) jeux mis à jour, \(created) jeux ajoutés"
    }

    // MARK: Mapping helpers

    private static func platform(_ v: Any?) -> Platform? {
        let s = ((v as? [String])?.first ?? (v as? String) ?? "").lowercased()
        guard !s.isEmpty else { return nil }
        // Consoles first ("Switch" contains "itch", "PS5" is not a store name…), then store names, then exact ids.
        if s.contains("switch") || s.contains("nintendo") || s.contains("wii") || s.contains("3ds") { return .nintendo }
        if s.contains("playstation") || s.range(of: "\\bps[1-5p]\\b|\\bpsn\\b|\\bvita\\b", options: .regularExpression) != nil { return .psn }
        if s.contains("xbox") || s.contains("game pass") || s.contains("microsoft") { return .xbox }
        if let p = Platform.allCases.first(where: { $0 != .other && s.contains($0.name.lowercased()) }) { return p }
        let words = Set(s.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        return Platform.allCases.first { words.contains($0.rawValue) }
    }

    private static func status(_ s: String) -> Completion? {
        let t = s.lowercased()
        if let c = Completion.allCases.first(where: { $0.label.lowercased() == t }) { return c }
        if t.contains("100") || t.contains("complet") || t.contains("mastered") { return .completed }
        if t.contains("beaten") || t.contains("finished") || t.contains("termin") || t.contains("fini") { return .beaten }
        if t.contains("playing") || t.contains("en cours") { return .playing }
        if t.contains("hold") || t.contains("pause") || t.contains("shelved") { return .onHold }
        if t.contains("abandon") || t.contains("dropped") { return .abandoned }
        if t.contains("plan") || t.contains("backlog") || t.contains("à jouer") || t.contains("wishlist") { return .planned }
        if t.contains("not played") || t.contains("pas commencé") { return Completion.none }
        return nil
    }

    /// Accepts 1–5, 1–10 or 1–100 scales.
    private static func normaliseRating(_ v: Double) -> Int {
        let five = v > 10 ? v / 20 : v > 5 ? v / 2 : v
        return max(0, min(5, Int(five.rounded())))
    }
}
