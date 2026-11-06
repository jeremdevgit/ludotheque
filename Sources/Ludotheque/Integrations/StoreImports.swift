// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation

/// Apple and Google have no public API for a user's purchases: both are
/// imported from the official personal-data exports.
extension Integrations {

    // MARK: App Store — Apple "Data & Privacy" export

    static let appStore = Integration(
        platform: .appstore,
        summary: String(localized: "Les jeux App Store / Apple Arcade installés sont détectés automatiquement. Pour retrouver aussi ceux achetés mais non installés, importe l'export de tes données Apple."),
        steps: [String(localized: "Sur privacy.apple.com, demande une copie de tes données → coche « Informations Apple Media Services »."),
                String(localized: "Quand Apple t'envoie l'archive (quelques jours), décompresse-la."),
                String(localized: "Choisis le dossier décompressé (ou le fichier CSV d'historique d'achats) ci-dessous puis synchronise.")],
        links: [(String(localized: "Données et confidentialité Apple"), "https://privacy.apple.com/"),
                (String(localized: "Mes achats App Store"), "macappstore://showPurchasesPage")],
        fields: [IntegrationField(key: "file", label: String(localized: "Export Apple"), placeholder: String(localized: "Dossier ou fichier .csv"), secret: false, file: true)],
        connectedKeys: ["file"]
    ) { c in
        guard let path = c["file"] else { throw SyncError(String(localized: "Choisis l'export Apple")) }
        let csvs = files(at: path, ext: "csv")
        guard !csvs.isEmpty else { throw SyncError(String(localized: "Aucun fichier CSV trouvé dans l'export")) }
        var games = [String: Game]()
        for f in csvs {
            guard let rows = CSV.read(f), let header = rows.first?.map({ $0.lowercased() }) else { continue }
            func col(_ names: [String]) -> Int? { header.firstIndex { h in names.contains { h.contains($0) } } }
            guard let titleCol = col(["item description", "content name", "item name", "title", "description"]) else { continue }
            let typeCol = col(["content type", "item type", "media type", "product type", "kind"])
            let genreCol = col(["genre", "category"])
            for row in rows.dropFirst() where row.count > titleCol {
                let title = row[titleCol].trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { continue }
                let type = typeCol.flatMap { row.count > $0 ? row[$0].lowercased() : nil } ?? ""
                let genre = genreCol.flatMap { row.count > $0 ? row[$0].lowercased() : nil } ?? ""
                // Keep apps; if a genre is given, keep games only.
                if !type.isEmpty && !(type.contains("app") || type.contains("game") || type.contains("jeu")) { continue }
                if !genre.isEmpty && !(genre.contains("game") || genre.contains("jeu")) { continue }
                var g = Game(id: "appstore_\(norm(title))", platform: .appstore, externalId: title, title: title)
                g.storeURL = "https://apps.apple.com/fr/search?term=\(title.urlQueryEscaped)"
                g.launchURL = "macappstore://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?q=\(title.urlQueryEscaped)"
                g.macNative = true
                games[g.id] = g
            }
        }
        return Array(games.values)
    }

    // MARK: Google Play Games — Google Takeout

    static let googlePlay = Integration(
        platform: .googleplay,
        summary: String(localized: "Importe tes jeux Google Play (Android) depuis Google Takeout. Ces jeux ne se lancent pas sur Mac mais sont répertoriés avec ton temps de jeu."),
        steps: [String(localized: "Sur takeout.google.com, sélectionne « Google Play Jeux » et « Google Play Store », puis exporte."),
                String(localized: "Décompresse l'archive reçue."),
                String(localized: "Choisis le dossier « Takeout » ci-dessous puis synchronise. Les jeux viennent de « Google Play Jeux » ; à défaut, de la bibliothèque Play Store.")],
        links: [("Google Takeout", "https://takeout.google.com/"), ("Google Play Jeux", "https://play.google.com/store/games")],
        fields: [IntegrationField(key: "file", label: String(localized: "Dossier Takeout"), placeholder: "…/Takeout", secret: false, file: true)],
        connectedKeys: ["file"]
    ) { c in
        guard let path = c["file"] else { throw SyncError(String(localized: "Choisis le dossier Takeout")) }
        let root = URL(fileURLWithPath: path)
        var titles = Set<String>()
        // 1. Play Games Services: one folder per game the account has played.
        let fm = FileManager.default
        for name in ["Google Play Games Services", "Google Play Jeux", "Google Play Games"] {
            for base in [root, root.appendingPathComponent("Takeout")] {
                let gamesDir = base.appendingPathComponent(name).appendingPathComponent("Games")
                for d in (try? fm.contentsOfDirectory(atPath: gamesDir.path)) ?? [] where !d.hasPrefix(".") { titles.insert(d) }
            }
        }
        // 2. Fallback: Play Store library / installs / purchases (Android apps).
        if titles.isEmpty {
            for f in files(at: path, ext: "json") where ["library", "installs", "purchase"].contains(where: f.lastPathComponent.lowercased().contains) {
                guard let arr = (try? JSONSerialization.jsonObject(with: Data(contentsOf: f))) as? [[String: Any]] else { continue }
                for item in arr {
                    let inner = item.values.first as? [String: Any]
                    let doc = inner?["doc"] as? [String: Any]
                    if let t = doc?["title"] as? String, (doc?["documentType"] as? String ?? "").contains("App") { titles.insert(t) }
                }
            }
        }
        guard !titles.isEmpty else { throw SyncError(String(localized: "Aucun jeu trouvé dans ce dossier Takeout")) }
        return titles.map { t in
            var g = Game(id: "googleplay_\(norm(t))", platform: .googleplay, externalId: t, title: t)
            g.macNative = false
            g.storeURL = "https://play.google.com/store/search?q=\(t.urlQueryEscaped)&c=apps"
            return g
        }
    }

    // MARK: Helpers

    static func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }

    /// A file, or every file with that extension under a folder.
    static func files(at path: String, ext: String) -> [URL] {
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue { return url.pathExtension.lowercased() == ext ? [url] : [] }
        let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
        return (en?.allObjects as? [URL] ?? []).filter { $0.pathExtension.lowercased() == ext }
    }
}

/// Minimal RFC 4180 CSV reader (quoted fields, commas or semicolons).
enum CSV {
    /// Quotes a field and neutralises spreadsheet formulas (=, +, -, @) coming from remote data.
    static func escape(_ s: String) -> String {
        var v = s
        if let f = v.first, "=+-@\t\r".contains(f) { v = "'" + v }
        return "\"\(v.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    static func read(_ url: URL) -> [[String]]? {
        // UTF-8 first, then UTF-16 (Excel "Unicode text") and Latin-1 (older Excel / Windows exports).
        guard let text = [String.Encoding.utf8, .utf16, .isoLatin1].lazy.compactMap({ try? String(contentsOf: url, encoding: $0) }).first else { return nil }
        let firstLine = text.prefix { $0 != "\n" }
        let sep: Character = firstLine.filter { $0 == ";" }.count > firstLine.filter { $0 == "," }.count ? ";" : ","
        var rows = [[String]](), row = [String](), field = "", quoted = false
        var it = text.makeIterator()
        while let ch = it.next() {
            if quoted {
                if ch == "\"" {
                    if let n = it.next() {
                        if n == "\"" { field.append("\"") } else { quoted = false; handle(n) }
                    } else { quoted = false }
                } else { field.append(ch) }
            } else { handle(ch) }
        }
        func handle(_ ch: Character) {
            switch ch {
            case "\"": quoted = true
            case sep: row.append(field); field = ""
            case "\n", "\r\n": row.append(field); field = ""; rows.append(row); row = []
            case "\r": break
            default: field.append(ch)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
