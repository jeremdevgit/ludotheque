// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation
import Darwin

/// Real-world speed, measured on this Mac and kept on this Mac (nothing is sent anywhere):
/// launch time (process start → window filled) and interface freezes (main thread busy > 250 ms).
/// Log: ~/Library/Application Support/Ludotheque/perf-log.json (last 500 entries).
final class PerfMonitor: @unchecked Sendable {
    static let shared = PerfMonitor()

    struct Entry: Codable {
        var date: Date
        var kind: Kind
        var ms: Int
        enum Kind: String, Codable { case launch, hang }
    }

    struct Summary {
        var launches = 0, medianLaunchMs = 0, lastLaunchMs = 0
        var hangs7d = 0, worstHangMs = 0
    }

    static let hangThreshold = 0.25
    let logURL = Paths.support.appendingPathComponent("perf-log.json")
    private let q = DispatchQueue(label: "ludotheque.perfmonitor", qos: .utility)
    private var entries: [Entry] = []
    private var timer: DispatchSourceTimer?
    private var pinging = false
    private var launched = false

    private init() {
        if let d = try? Data(contentsOf: logURL), let e = try? JSONDecoder().decode([Entry].self, from: d) { entries = e }
    }

    /// Starts the freeze watchdog: every 0.5 s a block is posted to the main thread; if it runs late,
    /// the main thread was blocked for that long.
    func start() {
        q.async { [self] in
            guard timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: q)
            t.schedule(deadline: .now() + 2, repeating: 0.5, leeway: .milliseconds(50))
            t.setEventHandler { [weak self] in self?.ping() }
            t.resume()
            timer = t
        }
    }

    private func ping() {
        guard !pinging else { return }
        pinging = true
        let t0 = DispatchTime.now().uptimeNanoseconds
        DispatchQueue.main.async { [self] in
            let ms = Int((DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
            q.async { [self] in
                pinging = false
                if Double(ms) / 1000 >= Self.hangThreshold { record(.hang, ms) }
            }
        }
    }

    /// Called once the main window shows content.
    func markLaunched() {
        q.async { [self] in
            guard !launched, let start = Self.processStart() else { return }
            launched = true
            record(.launch, Int(Date().timeIntervalSince(start) * 1000))
        }
    }

    private func record(_ kind: Entry.Kind, _ ms: Int) {
        entries.append(Entry(date: Date(), kind: kind, ms: ms))
        if entries.count > 500 { entries.removeFirst(entries.count - 500) }
        if let d = try? JSONEncoder().encode(entries) { try? d.write(to: logURL, options: .atomic) }
    }

    func summary() -> Summary {
        q.sync {
            var s = Summary()
            let launches = entries.filter { $0.kind == .launch }.map(\.ms)
            s.launches = launches.count
            s.lastLaunchMs = launches.last ?? 0
            if !launches.isEmpty { s.medianLaunchMs = launches.sorted()[launches.count / 2] }
            let week = Date().addingTimeInterval(-7 * 86400)
            let hangs = entries.filter { $0.kind == .hang && $0.date > week }
            s.hangs7d = hangs.count
            s.worstHangMs = hangs.map(\.ms).max() ?? 0
            return s
        }
    }

    func clear() {
        q.async { [self] in entries.removeAll(); try? FileManager.default.removeItem(at: logURL) }
    }

    /// Process start time from the kernel (counts the time before any of our code runs).
    private static func processStart() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let tv = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }
}
