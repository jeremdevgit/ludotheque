// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation
import SQLite3

// MARK: - Valve text KeyValues (.vdf / .acf)

indirect enum VDF {
    case string(String)
    case dict([String: VDF])

    subscript(_ key: String) -> VDF? {
        guard case .dict(let d) = self else { return nil }
        // Valve keys are case-insensitive in practice ("apps" vs "Apps").
        return d[key] ?? d.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }
    var string: String? { if case .string(let s) = self { return s }; return nil }
    var dict: [String: VDF] { if case .dict(let d) = self { return d }; return [:] }

    static func parse(file: URL) -> VDF? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> VDF? {
        let bytes = [UInt8](data)
        var i = 0
        func skip() {
            while i < bytes.count {
                let c = bytes[i]
                if c == 0x2F, i + 1 < bytes.count, bytes[i + 1] == 0x2F { // // comment
                    while i < bytes.count, bytes[i] != 0x0A { i += 1 }
                } else if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { i += 1 } else { return }
            }
        }
        func token() -> String? {
            skip()
            guard i < bytes.count else { return nil }
            if bytes[i] == 0x22 {
                i += 1
                var out = [UInt8]()
                while i < bytes.count, bytes[i] != 0x22 {
                    if bytes[i] == 0x5C, i + 1 < bytes.count { // backslash escape
                        i += 1
                        switch bytes[i] { case 0x6E: out.append(0x0A); case 0x74: out.append(0x09); default: out.append(bytes[i]) }
                    } else { out.append(bytes[i]) }
                    i += 1
                }
                i += 1
                return String(decoding: out, as: UTF8.self)
            }
            let start = i
            while i < bytes.count, ![0x20, 0x09, 0x0A, 0x0D, 0x7B, 0x7D, 0x22].contains(bytes[i]) { i += 1 }
            return String(decoding: bytes[start..<i], as: UTF8.self)
        }
        func object() -> [String: VDF] {
            var d = [String: VDF]()
            while true {
                skip()
                guard i < bytes.count else { return d }
                if bytes[i] == 0x7D { i += 1; return d }
                guard let key = token() else { return d }
                skip()
                if i < bytes.count, bytes[i] == 0x7B { i += 1; d[key] = .dict(object()) }
                else if let v = token() { d[key] = .string(v) }
            }
        }
        return .dict(object())
    }
}

// MARK: - Steam binary appinfo.vdf (v27/v28/v29)

struct SteamAppInfo { var name: String; var type: String; var oslist: String }

enum AppInfoVDF {
    static func parse(_ url: URL) -> [UInt32: SteamAppInfo] {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped), data.count > 16 else { return [:] }
        return data.withUnsafeBytes { raw -> [UInt32: SteamAppInfo] in
            let b = raw.bindMemory(to: UInt8.self)
            let n = b.count
            func u32(_ o: Int) -> UInt32 { o + 4 <= n ? UInt32(b[o]) | UInt32(b[o+1]) << 8 | UInt32(b[o+2]) << 16 | UInt32(b[o+3]) << 24 : 0 }
            func i64(_ o: Int) -> Int { Int(u32(o)) | Int(u32(o + 4)) << 32 }
            func cstr(_ o: inout Int) -> String {
                let s = o
                while o < n, b[o] != 0 { o += 1 }
                defer { o += 1 }
                return String(decoding: UnsafeBufferPointer(rebasing: b[s..<min(o, n)]), as: UTF8.self)
            }

            let magic = u32(0)
            let version = magic & 0xFF
            guard magic >> 8 == 0x075644, version >= 0x27 else { return [:] }
            var pos = 8
            var strings: [String] = []
            if version >= 0x29 {
                var o = i64(8)
                pos = 16
                let count = Int(u32(o)); o += 4
                strings.reserveCapacity(count)
                for _ in 0..<count where o < n { strings.append(cstr(&o)) }
            }

            // Reads one KV section; only keeps the few keys we need.
            var result = [UInt32: SteamAppInfo]()
            while pos + 8 <= n {
                let appId = u32(pos)
                if appId == 0 { break }
                let size = Int(u32(pos + 4))
                let next = pos + 8 + size
                var o = pos + 8 + (version >= 0x28 ? 60 : 40)
                var path: [String] = []
                var info = SteamAppInfo(name: "", type: "", oslist: "")
                while o < next {
                    let t = b[o]; o += 1
                    if t == 0x08 { if path.isEmpty { break }; path.removeLast(); continue }
                    let key: String
                    if version >= 0x29 { let idx = Int(u32(o)); o += 4; key = idx < strings.count ? strings[idx] : "" }
                    else { key = cstr(&o) }
                    switch t {
                    case 0x00: path.append(key)
                    case 0x01:
                        let v = cstr(&o)
                        if path.count == 2, path[1] == "common" {
                            switch key.lowercased() {
                            case "name": info.name = v
                            case "type": info.type = v.lowercased()
                            case "oslist": info.oslist = v
                            default: break
                            }
                        }
                    case 0x02, 0x03, 0x04, 0x06: o += 4
                    case 0x07, 0x0A: o += 8
                    case 0x05: while o + 1 < n, !(b[o] == 0 && b[o+1] == 0) { o += 2 }; o += 2
                    default: o = next
                    }
                }
                if !info.name.isEmpty { result[appId] = info }
                pos = next
            }
            return result
        }
    }
}

// MARK: - Minimal read-only SQLite

final class SQLiteDB {
    private var db: OpaquePointer?

    init?(path: String) {
        guard Paths.exists(path) else { return nil }
        // mode=ro honours WAL; immutable avoids locks if the launcher holds the DB.
        for uri in ["file:\(path)?mode=ro", "file:\(path)?immutable=1"] {
            if sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
               sqlite3_exec(db, "select 1 from sqlite_master limit 1", nil, nil, nil) == SQLITE_OK {
                sqlite3_busy_timeout(db, 500)
                return
            }
            sqlite3_close(db); db = nil
        }
        return nil
    }
    deinit { sqlite3_close(db) }

    /// Rows as arrays of optional strings. Errors (missing table…) yield [].
    func rows(_ sql: String) -> [[String?]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out = [[String?]]()
        let cols = sqlite3_column_count(stmt)
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append((0..<cols).map { c in sqlite3_column_text(stmt, c).map { String(cString: $0) } })
        }
        return out
    }
}

// MARK: - Helpers

enum JSON {
    static func load(_ url: URL) -> Any? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }
}

enum Bundle2 {
    static func info(_ app: URL) -> [String: Any]? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
    }
    static func displayName(_ app: URL) -> String {
        let i = info(app)
        return (i?["CFBundleDisplayName"] as? String) ?? (i?["CFBundleName"] as? String)
            ?? app.deletingPathExtension().lastPathComponent
    }
    static func apps(in dir: URL, depth: Int = 1) -> [URL] {
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var out = [URL]()
        for u in items {
            if u.pathExtension == "app" { out.append(u) }
            else if depth > 0, (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                out += apps(in: u, depth: depth - 1)
            }
        }
        return out
    }
}
