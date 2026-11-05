// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation
import AppKit

/// Finds what belongs to an installed game and moves it to the Trash (never a hard delete).
enum Uninstaller {
    enum Kind: String { case game = "Jeu", config = "Configuration et sauvegardes", cache = "Caches et journaux" }

    struct Item: Identifiable, Hashable {
        let url: URL
        let kind: Kind
        var size: Int64 = 0
        var uncertain = false     // matched by name only: listed but unchecked by default
        var id: String { url.path }
    }

    /// How the main files are removed.
    enum Method: Equatable {
        case trash                        // we move the app / folder / ROM to the Trash ourselves
        case launcher(String, URL)        // the store's launcher uninstalls the game (keeps it consistent)
    }

    struct Plan {
        let method: Method
        var items: [Item]
    }

    private static let home = Paths.home
    /// Never touched, whatever the name matching says.
    private static let protected: [String] = ["Steam", "Epic", "GOG.com", "GOG Galaxy", "Battle.net", "Blizzard", "Electronic Arts", "EA app",
                                              "Origin", "heroic", "itch", "CrossOver", "Ludotheque", "com.apple", "Apple", "Google", "Unity"]

    static func plan(for g: Game) -> Plan {
        var items = [Item]()
        var method = Method.trash
        let app = g.appPath.map(URL.init(fileURLWithPath:))

        // 1. Main files
        switch g.platform {
        case .steam:
            method = .launcher("Steam", URL(string: "steam://uninstall/\(g.externalId)")!)
        case .epic where app == nil || !(app!.path.hasPrefix("/Applications")):
            if let u = URL(string: g.launchURL?.replacingOccurrences(of: "action=launch", with: "action=uninstall") ?? "") { method = .launcher("Epic Games", u) }
        case .gog where g.manualId == nil && app == nil:
            method = .launcher("GOG Galaxy", URL(string: "goggalaxy://openGameView/gog_\(g.externalId)")!)
        case .battlenet where app == nil:
            if let l = g.launchURL, let u = URL(string: l) { method = .launcher("Battle.net", u) }
        default:
            break
        }
        if g.launchURL?.hasPrefix("heroic://") == true, let u = URL(string: "heroic://") { method = .launcher("Heroic", u) }
        if case .trash = method {
            if g.launchURL?.hasPrefix("emu:") == true { items.append(Item(url: URL(fileURLWithPath: g.externalId), kind: .game)) }
            else if let app { items.append(Item(url: app, kind: .game)) }
        }

        // 2. Associated files (by bundle id, app name, Unity company/product)
        var names = Set<String>()
        var bundleId: String?
        if let app, let info = Bundle2.info(app) {
            bundleId = info["CFBundleIdentifier"] as? String
            for k in ["CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"] { if let n = info[k] as? String { names.insert(n) } }
            names.insert(app.deletingPathExtension().lastPathComponent)
        }
        names.insert(g.title)
        names = names.filter { $0.count >= 3 && !protected.contains($0) }
        let lib = home.appendingPathComponent("Library")
        let dirs: [(String, Kind)] = [
            ("Application Support", .config), ("Preferences", .config), ("Containers", .config), ("Group Containers", .config),
            ("Saved Application State", .config), ("Application Scripts", .config),
            ("Caches", .cache), ("Logs", .cache), ("HTTPStorages", .cache), ("WebKit", .cache), ("Cookies", .cache),
        ]
        let fm = FileManager.default
        func byId(_ name: String) -> Bool {
            let n = name.lowercased()
            if let b = bundleId?.lowercased(), n.contains(b) { return true }
            return n.hasPrefix("unity.")
        }
        func matches(_ name: String) -> Bool {
            let n = name.lowercased()
            if let b = bundleId?.lowercased(), n == b || n.hasPrefix(b + ".") || n.hasPrefix(b + "_") || n == b + ".plist" || n == b + ".savedstate" || n == b + ".binarycookies" || n.hasSuffix("." + b) {
                return true
            }
            for raw in names {
                let t = raw.lowercased()
                if n == t || n == t + ".plist" { return true }
                // Unity: Preferences/unity.<Company>.<Product>.plist, Application Support/unity.<Company>.<Product>
                if n.hasPrefix("unity.") && (n.hasSuffix("." + t) || n.hasSuffix("." + t + ".plist")) { return true }
            }
            return false
        }
        for (dir, kind) in dirs {
            let base = lib.appendingPathComponent(dir)
            for entry in (try? fm.contentsOfDirectory(atPath: base.path)) ?? [] {
                if protected.contains(where: { entry.hasPrefix($0) }) && !(bundleId.map { entry.contains($0) } ?? false) {
                    // "<Company>/<Product>" nested one level (e.g. Unity, Unreal)
                    continue
                }
                let url = base.appendingPathComponent(entry)
                if matches(entry) { items.append(Item(url: url, kind: kind, uncertain: !byId(entry))); continue }
                // Company folder containing a folder named like the game
                if kind == .config, dir == "Application Support",
                   let sub = try? fm.contentsOfDirectory(atPath: url.path), sub.contains(where: matches), sub.count <= 3 {
                    for s in sub where matches(s) { items.append(Item(url: url.appendingPathComponent(s), kind: kind, uncertain: !byId(s))) }
                }
            }
        }
        // Never list the app twice / never list a parent of the app.
        var seen = Set<String>()
        items = items.filter { seen.insert($0.url.path).inserted }
        return Plan(method: method, items: items)
    }

    static func size(_ url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0) }
        var total: Int64 = 0
        let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: [], errorHandler: nil)
        while let f = en?.nextObject() as? URL {
            total += Int64((try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// Moves the selected items to the Trash; returns the ones that failed.
    static func trash(_ items: [Item]) -> [Item] {
        items.filter { (try? FileManager.default.trashItem(at: $0.url, resultingItemURL: nil)) == nil }
    }
}
