// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation
import Security

// MARK: - Keychain (credentials never touch disk in clear)

enum Keychain {
    static let service = (Bundle.main.bundleIdentifier ?? "Ludotheque") + ".credentials"
    // Keychain lookups are slow: keep what we read in memory.
    private static var cache: [String: String?] = [:]
    private static let lock = NSLock()

    static func get(_ account: String) -> String? {
        if let hit = lock.withLock({ cache[account] }) { return hit }
        let v = read(account)
        lock.withLock { cache[account] = .some(v) }
        return v
    }

    private static func read(_ account: String) -> String? {
        var out: AnyObject?
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true]
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func set(_ account: String, _ value: String?) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        lock.withLock { cache[account] = .some(value?.isEmpty == false ? value : nil) }
        guard let value, !value.isEmpty else { SecItemDelete(q as CFDictionary); return }
        let data = Data(value.utf8)
        if SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}

/// Credentials of one integration, persisted in the Keychain as "<platform>.<key>".
final class Creds: @unchecked Sendable {
    let platform: Platform
    init(_ p: Platform) { platform = p }
    subscript(_ key: String) -> String? {
        get { Keychain.get("\(platform.rawValue).\(key)")?.trimmingCharacters(in: .whitespacesAndNewlines) }
        set { Keychain.set("\(platform.rawValue).\(key)", newValue?.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}

// MARK: - HTTP

struct SyncError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

enum HTTP {
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ s: URLSession, task: URLSessionTask, willPerformHTTPRedirection r: HTTPURLResponse,
                        newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    static let noRedirect = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)

    static func form(_ f: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return Data(f.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&").utf8)
    }

    static func raw(_ url: String, method: String = "GET", headers: [String: String] = [:], form f: [String: String]? = nil,
                    jsonBody: [String: Any]? = nil, session: URLSession = .shared) async throws -> (Data, HTTPURLResponse) {
        guard let u = URL(string: url) else { throw SyncError(String(localized: "URL invalide : \(url)")) }
        var req = URLRequest(url: u, timeoutInterval: 30)
        req.httpMethod = method
        req.setValue("Ludotheque/1.0 (macOS game launcher)", forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let f {
            req.httpBody = form(f)
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        if let jsonBody {
            req.httpBody = try? JSONSerialization.data(withJSONObject: jsonBody)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (d, r) = try await session.data(for: req)
        guard let http = r as? HTTPURLResponse else { throw SyncError(String(localized: "Réponse invalide")) }
        return (d, http)
    }

    static func json(_ url: String, method: String = "GET", headers: [String: String] = [:], form f: [String: String]? = nil,
                     jsonBody: [String: Any]? = nil) async throws -> [String: Any] {
        let (d, r) = try await raw(url, method: method, headers: headers, form: f, jsonBody: jsonBody)
        guard (200..<300).contains(r.statusCode) else {
            if r.statusCode == 401 || r.statusCode == 403 { throw SyncError(String(localized: "Accès refusé (\(r.statusCode)) — identifiants invalides ou expirés")) }
            throw SyncError(String(localized: "Erreur HTTP \(r.statusCode) sur \(r.url?.host ?? url)"))
        }
        guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw SyncError(String(localized: "Réponse illisible de \(r.url?.host ?? url)")) }
        return o
    }
}

// MARK: - Integration catalogue

struct IntegrationField {
    let key: String
    let label: String
    var placeholder = ""
    var secret = true
    var prefill: (() -> String?)? = nil
    var file = false           // pick a file or folder instead of typing
}

struct Integration {
    let platform: Platform
    let summary: String
    let steps: [String]
    let links: [(String, String)]
    let fields: [IntegrationField]
    /// Keys whose presence means "connected" (any of them).
    let connectedKeys: [String]
    let sync: (Creds) async throws -> [Game]

    var isConnected: Bool {
        let c = Creds(platform)
        return connectedKeys.contains { c[$0] != nil }
    }

    func disconnect() {
        let c = Creds(platform)
        for k in Set(fields.map(\.key) + connectedKeys + ["refresh"]) { c[k] = nil }
        ApiStore.clear(platform)
    }
}

enum Integrations {
    static let all: [Integration] = [steam, epic, gog, xbox, psn, nintendo, appStore, googlePlay, itch, humble]
    static func of(_ p: Platform) -> Integration? { all.first { $0.platform == p } }

    /// Platforms GOG Galaxy can import (when you connect them inside Galaxy).
    static let galaxy: Set<Platform> = [.steam, .epic, .gog, .xbox, .psn, .nintendo, .battlenet, .ea, .ubisoft, .itch,
                                        .amazon, .humble, .rockstar, .bethesda, .riot, .indiegala, .fanatical, .gmg,
                                        .paradox, .wargaming, .meta, .emulation]

    /// What we read on disk for each platform, shown in the Integrations panel.
    static func local(_ p: Platform) -> String? {
        switch p {
        case .steam: String(localized: "Jeux installés, bibliothèque, temps de jeu et jaquettes lus depuis Steam.")
        case .epic: String(localized: "Jeux installés et catalogue lus depuis l'Epic Games Launcher (et Heroic).")
        case .gog: String(localized: "Base de données de GOG Galaxy (jeux installés, temps de jeu).")
        case .battlenet: String(localized: "Jeux installés et lancement direct via Battle.net.")
        case .ea: String(localized: "Jeux installés dans /Applications/EA Games.")
        case .itch: String(localized: "Base de l'app itch (jeux possédés et installés).")
        case .amazon: String(localized: "Bibliothèque Amazon Prime Gaming via Heroic Games Launcher.")
        case .appstore: String(localized: "Jeux App Store, Apple Arcade et jeux iPhone/iPad installés (détectés via Spotlight).")
        case .mac: String(localized: "Applications de la catégorie Jeux dans /Applications et ~/Applications.")
        case .xbox: String(localized: "Minecraft Launcher et Prism Launcher (Minecraft appartient à Microsoft).")
        case .crossover: String(localized: "Raccourcis CrossOver / Whisky (~/Applications/CrossOver).")
        case .playcover: String(localized: "Applications iOS installées dans PlayCover.")
        case .riot: String(localized: "Riot Client et League of Legends (client Mac natif) dans /Applications.")
        default: nil
        }
    }

    // MARK: Status / scheduling

    static func lastSync(_ p: Platform) -> Date? { UserDefaults.standard.object(forKey: "sync.\(p.rawValue).date") as? Date }
    static func lastError(_ p: Platform) -> String? { UserDefaults.standard.string(forKey: "sync.\(p.rawValue).error") }

    static func stale(_ i: Integration) -> Bool {
        guard i.isConnected else { return false }
        return Date().timeIntervalSince(lastSync(i.platform) ?? .distantPast) > 6 * 3600
    }

    /// Runs one integration and stores its games; returns a user-facing message.
    @discardableResult
    static func run(_ i: Integration) async -> String {
        let d = UserDefaults.standard
        do {
            let games = try await i.sync(Creds(i.platform))
            ApiStore.save(i.platform, games)
            d.set(Date(), forKey: "sync.\(i.platform.rawValue).date")
            d.removeObject(forKey: "sync.\(i.platform.rawValue).error")
            return String(localized: "\(games.count) jeux importés depuis \(i.platform.name)")
        } catch {
            let m = error.localizedDescription
            d.set(m, forKey: "sync.\(i.platform.rawValue).error")
            return "\(i.platform.name) : \(m)"
        }
    }
}

enum ApiStore {
    static func url(_ p: Platform) -> URL { Paths.api.appendingPathComponent("\(p.rawValue).json") }
    static func save(_ p: Platform, _ g: [Game]) { try? JSONEncoder().encode(g).write(to: url(p), options: .atomic) }
    static func load(_ p: Platform) -> [Game] { (try? JSONDecoder().decode([Game].self, from: Data(contentsOf: url(p)))) ?? [] }
    static func clear(_ p: Platform) { try? FileManager.default.removeItem(at: url(p)) }
    static func loadAll() -> [Game] { Integrations.all.flatMap { load($0.platform) } }
}

// MARK: - Helpers

extension Integrations {
    static func date(_ s: Any?) -> Date? {
        guard let s = s as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    /// "PT12H3M45S" → 723 minutes.
    static func isoDurationMinutes(_ s: String?) -> Int? {
        guard let s, s.hasPrefix("P") else { return nil }
        var total = 0.0, num = ""
        var inTime = false
        for c in s.dropFirst() {
            if c == "T" { inTime = true; continue }
            if c.isNumber || c == "." { num.append(c); continue }
            let v = Double(num) ?? 0; num = ""
            switch c {
            case "D": total += v * 1440
            case "H": total += v * 60
            case "M": total += inTime ? v : v * 43200
            case "S": total += v / 60
            default: break
            }
        }
        return Int(total)
    }

    static func string(_ v: Any?) -> String? {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    /// Accepts a raw code, a pasted redirect URL ("…?code=XYZ") or JSON ("authorizationCode":"XYZ").
    static func extractCode(_ input: String, jsonKey: String = "authorizationCode") -> String {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let re = try? NSRegularExpression(pattern: "\"\(jsonKey)\"\\s*:\\s*\"([^\"]+)\""),
           let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), let r = Range(m.range(at: 1), in: s) {
            return String(s[r])
        }
        if let comps = URLComponents(string: s), let c = comps.queryItems?.first(where: { $0.name == "code" })?.value { return c }
        return s
    }
}
