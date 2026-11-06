// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation
import AppKit
import Metal
import IOKit

// MARK: - This Mac

/// Hardware of the current Mac plus a GPU performance index on the same
/// scale as the PC graphics cards in game requirements (GTX 1060 = 100).
struct MacSpecs {
    let chip: String
    let performanceCores: Int
    let efficiencyCores: Int
    let memoryGB: Int
    let gpuName: String
    let gpuCores: Int?
    let screenWidth: Int
    let screenHeight: Int
    let refreshRate: Int
    let gpuIndex: Int
    var details = Details()

    /// Precise hardware figures (frequencies from the power manager tables, memory, storage, Metal).
    struct Details {
        var model = ""                 // "MacBookAir10,1"
        var pCoreMHz: Int?             // max performance-core frequency
        var eCoreMHz: Int?             // max efficiency-core frequency
        var gpuMHz: Int?               // max GPU frequency
        var l2P: Int?                  // bytes
        var l2E: Int?
        var memoryType = ""            // "LPDDR4"
        var memoryVendor = ""
        var memorySpeed: Int?          // MT/s
        var bandwidth: Double?         // GB/s
        var ssd: Bool?
        var storageBus = ""
        var storageTotalGB: Int?
        var storageFreeGB: Int?
        var metal3 = false
        var raytracing = false
        var maxWorkingSetGB: Double?
        var tflops: Double?
        var fanless = false
        var thermal = ""
    }

    static let current = MacSpecs.detect()

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
    private static func sysctlInt(_ name: String) -> Int? {
        var v: Int64 = 0, size = MemoryLayout<Int64>.size
        return sysctlbyname(name, &v, &size, nil, 0) == 0 ? Int(v) : nil
    }

    private static func appleGPUCores() -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int
    }

    static func detect() -> MacSpecs {
        let chip = sysctl("machdep.cpu.brand_string") ?? "Mac"
        let p = sysctlInt("hw.perflevel0.physicalcpu") ?? sysctlInt("hw.physicalcpu") ?? 0
        let e = sysctlInt("hw.perflevel1.physicalcpu") ?? 0
        let gpu = MTLCreateSystemDefaultDevice()?.name ?? "GPU"
        let cores = appleGPUCores()
        let screen = NSScreen.main
        let scale = screen?.backingScaleFactor ?? 1
        let w = Int((screen?.frame.width ?? 1920) * scale), h = Int((screen?.frame.height ?? 1080) * scale)
        let hz = screen?.maximumFramesPerSecond ?? 60
        var specs = MacSpecs(chip: chip, performanceCores: p, efficiencyCores: e,
                             memoryGB: Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824),
                             gpuName: gpu, gpuCores: cores, screenWidth: w, screenHeight: h, refreshRate: hz,
                             gpuIndex: appleIndex(chip: chip, cores: cores) ?? GPUIndex.of(gpu) ?? 20)
        // Precise details need external tools (system_profiler, diskutil): never on this path.
        // Waiting for them here spun the run loop inside the static initializer, a view asked for
        // `current` again and the app crashed ("trying to lock recursively").
        return specs
    }

    // MARK: Precise details

    /// Max frequency (MHz) of a pmgr "voltage-states" table: pairs of (Hz, mV) as little-endian UInt32.
    private static func pmgrMaxMHz(_ keys: [String]) -> Int? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleARMIODevice"), &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        while case let entry = IOIteratorNext(it), entry != 0 {
            defer { IOObjectRelease(entry) }
            var name = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(entry, &name)
            guard String(cString: name) == "pmgr" else { continue }
            for key in keys {
                guard let data = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
                      data.count >= 8 else { continue }
                let maxHz = stride(from: 0, to: data.count - 3, by: 8).map { i in
                    data[i..<i + 4].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
                }.max() ?? 0
                if maxHz > 100_000_000 { return Int(maxHz / 1_000_000) }
            }
        }
        return nil
    }

    private static func run(_ path: String, _ args: [String]) -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return Data() }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return d
    }

    nonisolated static func detectDetails(chip: String, gpuCores: Int?) -> Details {
        var d = Details()
        d.model = sysctl("hw.model") ?? ""
        d.fanless = d.model.hasPrefix("MacBookAir")
        d.pCoreMHz = pmgrMaxMHz(["voltage-states5-sram", "voltage-states5"])
        d.eCoreMHz = pmgrMaxMHz(["voltage-states1-sram", "voltage-states1"])
        d.gpuMHz = pmgrMaxMHz(["voltage-states9"])
        d.l2P = sysctlInt("hw.perflevel0.l2cachesize")
        d.l2E = sysctlInt("hw.perflevel1.l2cachesize")

        // Memory: type / vendor from System Information, speed and bandwidth from the chip generation.
        if let json = try? JSONSerialization.jsonObject(with: run("/usr/sbin/system_profiler", ["SPMemoryDataType", "-json"])) as? [String: Any],
           let mem = (json["SPMemoryDataType"] as? [[String: Any]])?.first {
            d.memoryType = mem["dimm_type"] as? String ?? ""
            d.memoryVendor = mem["dimm_manufacturer"] as? String ?? ""
        }
        let c = chip.lowercased()
        let tier = c.contains("ultra") ? 3 : c.contains("max") ? 2 : c.contains("pro") ? 1 : 0
        let table: [String: (Int, [Double])] = [   // MT/s, bandwidth GB/s by tier (base, Pro, Max, Ultra)
            "m1": (4266, [68.25, 200, 400, 800]), "m2": (6400, [100, 200, 400, 800]), "m3": (6400, [100, 150, 400, 800]),
            "m4": (7500, [120, 273, 546, 819]), "m5": (9600, [153, 307, 614, 1228]),
        ]
        if let r = c.range(of: "m\\d", options: .regularExpression), let t = table[String(c[r])] {
            d.memorySpeed = tier >= 1 && c.contains("m4") ? 8533 : t.0
            d.bandwidth = t.1[tier]
        }

        // Storage of the startup volume.
        if let plist = try? PropertyListSerialization.propertyList(from: run("/usr/sbin/diskutil", ["info", "-plist", "/"]), format: nil) as? [String: Any] {
            d.ssd = plist["SolidState"] as? Bool
            d.storageBus = plist["BusProtocol"] as? String ?? ""
            if let total = (plist["APFSContainerSize"] ?? plist["TotalSize"]) as? NSNumber { d.storageTotalGB = Int(total.int64Value / 1_000_000_000) }
            if let free = (plist["APFSContainerFree"] ?? plist["FreeSpace"]) as? NSNumber { d.storageFreeGB = Int(free.int64Value / 1_000_000_000) }
        }

        if let dev = MTLCreateSystemDefaultDevice() {
            d.metal3 = dev.supportsFamily(.metal3)
            // Metal exposes ray tracing on every Apple GPU, but it is hardware-accelerated only from M3 on.
            let gen = Int(c.range(of: "m(\\d+)", options: .regularExpression).map { String(c[$0].dropFirst()) } ?? "") ?? 0
            d.raytracing = dev.supportsRaytracing && gen >= 3
            d.maxWorkingSetGB = Double(dev.recommendedMaxWorkingSetSize) / 1_073_741_824
        }
        if let n = gpuCores, let f = d.gpuMHz { d.tflops = Double(n) * 128 * 2 * Double(f) / 1_000_000 }   // FP32 ALUs × FMA
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: d.thermal = String(localized: "Normale")
        case .fair: d.thermal = String(localized: "Tiède")
        case .serious: d.thermal = String(localized: "Chaude (performances réduites)")
        case .critical: d.thermal = String(localized: "Critique")
        @unknown default: d.thermal = ""
        }
        return d
    }

    /// Apple Silicon: per-GPU-core performance by generation, slight loss of scaling on big chips.
    static func appleIndex(chip: String, cores: Int?) -> Int? {
        let c = chip.lowercased()
        guard let r = c.range(of: "apple m(\\d+)", options: .regularExpression),
              let gen = Int(c[r].filter(\.isNumber)) else { return nil }
        let perCore: [Int: Double] = [1: 7.0, 2: 7.4, 3: 8.6, 4: 9.4, 5: 12.0]
        let defaultCores = c.contains("ultra") ? 64 : c.contains("max") ? 32 : c.contains("pro") ? 16 : 8
        let n = Double(cores ?? defaultCores)
        let scaling = n > 24 ? 0.85 : n > 12 ? 0.93 : 1
        return Int(n * (perCore[gen] ?? 13) * scaling)
    }

    /// Readable equivalent, e.g. "≈ GTX 1050 Ti".
    var equivalent: String { GPUIndex.closest(gpuIndex) }
}

// MARK: - GPU index table (GTX 1060 = 100)

enum GPUIndex {
    /// Most specific patterns first (matched with `contains` on a normalised string).
    static let table: [(String, Int)] = [
        ("rtx 4090", 500), ("rtx 4080", 390), ("rtx 4070 ti", 330), ("rtx 4070", 290), ("rtx 4060 ti", 240), ("rtx 4060", 210),
        ("rtx 3090", 330), ("rtx 3080", 300), ("rtx 3070 ti", 255), ("rtx 3070", 240), ("rtx 3060 ti", 210), ("rtx 3060", 170), ("rtx 3050", 105),
        ("rtx 2080 ti", 240), ("rtx 2080 super", 205), ("rtx 2080", 195), ("rtx 2070 super", 180), ("rtx 2070", 165),
        ("rtx 2060 super", 160), ("rtx 2060", 140),
        ("gtx 1660 ti", 120), ("gtx 1660 super", 118), ("gtx 1660", 105), ("gtx 1650 super", 95), ("gtx 1650", 70),
        ("gtx 1080 ti", 210), ("gtx 1080", 165), ("gtx 1070 ti", 150), ("gtx 1070", 135), ("gtx 1060", 100),
        ("gtx 1050 ti", 60), ("gtx 1050", 50), ("gt 1030", 25),
        ("gtx titan x", 120), ("gtx 980 ti", 125), ("gtx 980", 105), ("gtx 970", 90), ("gtx 960", 65), ("gtx 950", 55),
        ("gtx 780 ti", 75), ("gtx 780", 65), ("gtx 770", 55), ("gtx 760", 48), ("gtx 750 ti", 35), ("gtx 750", 30),
        ("gtx 680", 50), ("gtx 670", 45), ("gtx 660 ti", 42), ("gtx 660", 38), ("gtx 650 ti", 25), ("gtx 650", 18),
        ("gtx 580", 30), ("gtx 570", 26), ("gtx 560", 22), ("gtx 550", 15), ("gtx 480", 26), ("gtx 470", 22), ("gtx 460", 18),
        ("gts 450", 12), ("gt 740", 14), ("gt 730", 9), ("gt 640", 10), ("gt 630", 7), ("gtx 285", 12), ("gtx 260", 9),
        ("9800", 7), ("8800", 6),
        ("rx 7900 xtx", 440), ("rx 7900", 380), ("rx 7800 xt", 330), ("rx 7700 xt", 280), ("rx 7600", 190),
        ("rx 6950", 340), ("rx 6900", 320), ("rx 6800 xt", 300), ("rx 6800", 270), ("rx 6750", 240), ("rx 6700", 225),
        ("rx 6650", 185), ("rx 6600 xt", 180), ("rx 6600", 160), ("rx 6500", 75), ("rx 6400", 60),
        ("rx 5700 xt", 155), ("rx 5700", 140), ("rx 5600", 130), ("rx 5500", 95), ("rx vega 64", 130), ("vega 64", 130),
        ("rx vega 56", 120), ("vega 56", 120), ("rx 590", 110), ("rx 580", 100), ("rx 570", 90), ("rx 480", 95), ("rx 470", 85),
        ("rx 560", 50), ("rx 550", 30), ("rx 460", 40), ("r9 fury", 115), ("r9 390", 90), ("r9 380", 65), ("r9 290", 85),
        ("r9 285", 60), ("r9 280", 60), ("r9 270", 45), ("r7 370", 40), ("r7 260", 30), ("r7 250", 18),
        ("hd 7970", 55), ("hd 7950", 48), ("hd 7870", 42), ("hd 7850", 36), ("hd 7770", 25), ("hd 7750", 20),
        ("hd 6970", 30), ("hd 6950", 27), ("hd 6870", 24), ("hd 6850", 20), ("hd 6770", 15), ("hd 5870", 22), ("hd 5850", 19),
        ("hd 5770", 13), ("hd 4870", 10), ("hd 4850", 8),
        ("arc a770", 180), ("arc a750", 165), ("arc a580", 140), ("arc a380", 65), ("iris xe", 35), ("iris plus", 18),
        ("uhd 770", 20), ("uhd 750", 18), ("uhd 630", 15), ("uhd 620", 12), ("hd 630", 14), ("hd 620", 12), ("hd 530", 12),
        ("hd 520", 11), ("hd 4600", 9), ("hd 4400", 7), ("hd 4000", 6), ("hd 3000", 3),
        ("radeon pro 5600m", 120), ("radeon pro 5500m", 85), ("radeon pro 5300m", 70), ("radeon pro 560", 40), ("radeon pro 555", 32),
        ("radeon pro vega", 110), ("radeon pro w5700", 150),
        ("steam deck", 40), ("apple m1", 55), ("apple m2", 72), ("apple m3", 85), ("apple m4", 95),
    ]

    static func normalise(_ s: String) -> String {
        var t = s.lowercased()
        for (a, b) in [("geforce", ""), ("nvidia", ""), ("amd", ""), ("radeon", ""), ("intel", ""), ("®", ""), ("™", ""), ("graphics", ""),
                       ("-", " "), ("rx vega", "rx vega")] { t = t.replacingOccurrences(of: a, with: b) }
        // "GTX1060" → "gtx 1060"
        t = t.replacingOccurrences(of: "(gtx|rtx|gt|gts|rx|r9|r7|hd|uhd|arc)(\\d)", with: "$1 $2", options: .regularExpression)
        // Bare model numbers on AMD lines ("Radeon RX580" / "R9 290X")
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return " " + t + " "
    }

    /// Index of a single GPU name.
    static func of(_ name: String) -> Int? {
        let t = normalise(name)
        for (pattern, v) in table where t.contains(pattern) { return v }
        return nil
    }

    /// Parsed lines (regex-heavy): verdicts are computed for every game at every redraw of the
    /// Performances and Statistiques pages. NSCache is thread-safe.
    private static let lineCache = NSCache<NSString, NSNumber>()

    /// Index for a requirements line listing alternatives ("GTX 970 / RX 480"): average of the matches,
    /// falling back on the amount of VRAM.
    static func parseLine(_ line: String) -> Int? {
        if let n = lineCache.object(forKey: line as NSString) { return n.intValue < 0 ? nil : n.intValue }
        let v = parseLineUncached(line)
        lineCache.setObject(NSNumber(value: v ?? -1), forKey: line as NSString)
        return v
    }

    private static func parseLineUncached(_ line: String) -> Int? {
        let parts = line.components(separatedBy: CharacterSet(charactersIn: "/|,;")).flatMap { $0.components(separatedBy: " or ") }
        let found = parts.compactMap(of)
        if !found.isEmpty { return found.reduce(0, +) / found.count }
        if let r = line.range(of: "(\\d+)\\s*(gb|go)", options: [.regularExpression, .caseInsensitive]) {
            let gb = Int(line[r].filter(\.isNumber)) ?? 0
            switch gb { case ..<1: return nil; case 1: return 30; case 2: return 50; case 3: return 70; case 4: return 90; case 5...6: return 120; default: return 160 }
        }
        if line.range(of: "\\d{3,}\\s*mb", options: [.regularExpression, .caseInsensitive]) != nil { return 15 }
        return nil
    }

    static func closest(_ v: Int) -> String {
        let pc = table.filter { $0.0.hasPrefix("gtx") || $0.0.hasPrefix("rtx") }
        let best = pc.min { abs($0.1 - v) < abs($1.1 - v) }
        return best.map { "≈ " + $0.0.uppercased() } ?? ""
    }
}

// MARK: - Game requirements (Steam store)

struct Requirements: Codable {
    var appId: String?
    var minGPU: String?
    var recGPU: String?
    var minRAM: Int?
    var recRAM: Int?
    var source: String?          // "PCGamingWiki", "Steam", "GOG", String(localized: "Estimation émulation")
    var fetchedAt: Date?
    var estMin: Int?             // direct index (emulation estimates)
    var estRec: Int?

    var minIndex: Int? { estMin ?? minGPU.flatMap(GPUIndex.parseLine) }
    var recIndex: Int? { estRec ?? recGPU.flatMap(GPUIndex.parseLine) }
    var known: Bool { minIndex != nil || recIndex != nil }
}

enum Verdict: Int, Comparable {
    case unknown, insufficient, low, smooth1080, smooth1440
    static func < (a: Verdict, b: Verdict) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .unknown: String(localized: "Inconnu")
        case .insufficient: String(localized: "Insuffisant")
        case .low: String(localized: "Jouable (réglages bas)")
        case .smooth1080: String(localized: "Fluide \(PerfTarget.minimum.label)")
        case .smooth1440: String(localized: "Recommandé \(PerfTarget.recommended.label)")
        }
    }
    var symbol: String {
        switch self {
        case .unknown: "questionmark.circle"
        case .insufficient: "xmark.octagon.fill"
        case .low: "tortoise.fill"
        case .smooth1080: "checkmark.circle.fill"
        case .smooth1440: "bolt.circle.fill"
        }
    }
    var color: NSColor {
        switch self {
        case .unknown: .secondaryLabelColor
        case .insufficient: .systemRed
        case .low: .systemOrange
        case .smooth1080: .systemGreen
        case .smooth1440: .systemTeal
        }
    }
}

/// A performance target: resolution + frame rate.
struct PerfTarget: Hashable {
    let height: Int
    let fps: Int
    static let heights = [720, 1080, 1440, 2160]
    static let rates = [30, 60, 120, 144, 165, 240]
    var label: String { "\(height == 2160 ? "4K" : "\(height)p") \(fps)" }
    /// GPU load relative to 1080p 60 (what Steam "recommended" specs roughly target).
    var factor: Double { Double(height * height * 16 / 9) / Double(1080 * 1920) * Double(fps) / 60 }

    static var minimum: PerfTarget { stored("perfMin", PerfTarget(height: 1080, fps: 60)) }
    static var recommended: PerfTarget { stored("perfRec", PerfTarget(height: 1440, fps: 144)) }
    private static func stored(_ k: String, _ d: PerfTarget) -> PerfTarget {
        let ud = UserDefaults.standard
        let h = ud.integer(forKey: k + "H"), f = ud.integer(forKey: k + "F")
        return h > 0 && f > 0 ? PerfTarget(height: h, fps: f) : d
    }
}

enum PerfMath {
    /// Windows games run through a translation layer (CrossOver / Game Porting Toolkit).
    static let translationPenalty = 0.6

    static func effectiveIndex(for g: Game, mac: MacSpecs = .current) -> Double {
        Double(mac.gpuIndex) * (g.macNative == true || g.launchURL?.hasPrefix("emu:") == true ? 1 : translationPenalty)
    }

    static func verdict(_ r: Requirements?, game: Game, mac: MacSpecs = .current) -> Verdict {
        guard let r, r.known else { return .unknown }
        let idx = effectiveIndex(for: game, mac: mac)
        let rec = Double(r.recIndex ?? Int(Double(r.minIndex ?? 0) * 1.6))   // ≈ 1080p60
        let low = Double(r.minIndex ?? Int(rec / 1.6))
        let ram = mac.memoryGB
        if idx >= rec * PerfTarget.recommended.factor, ram >= (r.recRAM ?? 0) { return .smooth1440 }
        if idx >= rec * PerfTarget.minimum.factor, ram >= (r.recRAM ?? r.minRAM ?? 0) { return .smooth1080 }
        if idx >= low, ram >= (r.minRAM ?? 0) { return .low }
        return .insufficient
    }
}

/// Fetches and caches requirements; keyed by group key.
@MainActor
final class PerfStore: ObservableObject {
    static let shared = PerfStore()
    @Published private(set) var reqs: [String: Requirements] = Store<[String: Requirements]>.load("requirements.json", [:])
    @Published private(set) var progress: (done: Int, total: Int)?

    func requirements(_ g: GameGroup) -> Requirements? { reqs[g.key] }

    private var queue: [GameGroup] = []
    private var pending: [String: Requirements] = [:]

    private func flushPending() {
        guard !pending.isEmpty else { return }
        reqs.merge(pending) { _, new in new }
        pending.removeAll()
    }

    /// Queues games for analysis; runs as a background job (survives tab changes).
    func analyze(_ groups: [GameGroup]) async {
        let queued = Set(queue.map(\.key))
        let todo = groups.filter { g in reqs[g.key] == nil && !queued.contains(g.key) }
        queue += todo
        guard !queue.isEmpty else { return }
        await TaskCenter.shared.runAndWait("perf", String(localized: "Recherche des performances")) { [self] in
            var done = 0
            defer { flushPending(); progress = nil; Store<[String: Requirements]>.save("requirements.json", reqs) }
            while !queue.isEmpty, !Task.isCancelled {
                let g = queue.removeFirst()
                let total = done + queue.count + 1
                progress = (done, total)
                TaskCenter.shared.progress("perf", done, total, g.title)
                let r = await Self.fetch(g)
                if Task.isCancelled { break }
                pending[g.key] = r ?? Requirements()
                done += 1
                // Batched: each publish redraws the performance table / stats.
                if pending.count >= 8 || queue.isEmpty { flushPending() }
                if done % 10 == 0 { Store<[String: Requirements]>.save("requirements.json", reqs) }
                // Steam's store API is rate-limited (~200 requests / 5 min): go gently.
                try? await Task.sleep(for: .milliseconds(350))
            }
            queue.removeAll()
        }
    }

    func forget(_ g: GameGroup) { reqs[g.key] = nil }

    /// "Rechercher à nouveau": drop cached results and search the web again.
    func searchAgain(_ groups: [GameGroup]) async {
        for g in groups { reqs[g.key] = nil }
        await analyze(groups)
    }

    nonisolated private static func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }

    /// Tries every source in turn, so non-Steam games (Epic, GOG, Xbox, Ubisoft, ROMs…) are covered too.
    private static func fetch(_ g: GameGroup) async -> Requirements? {
        if let e = emulationEstimate(g) { return e }
        if g.games.allSatisfy({ $0.launchKind == .cloud }) { return nil }
        let steamId = g.games.first { $0.platform == .steam }?.externalId
        for source in [pcgw, steam, gog] {
            if var r = await source(g, steamId), r.known {
                r.fetchedAt = Date()
                return r
            }
        }
        return nil
    }

    // PCGamingWiki: community-maintained requirements for almost every PC game.
    private static let pcgw: (GameGroup, String?) async -> Requirements? = { g, _ in
        let api = "https://www.pcgamingwiki.com/w/api.php?format=json"
        var page: String?
        if let r = try? await HTTP.json("\(api)&action=query&list=search&srlimit=5&srsearch=\(g.title.urlQueryEscaped)"),
           let hits = (r["query"] as? [String: Any])?["search"] as? [[String: Any]] {
            let titles = hits.compactMap { $0["title"] as? String }
            page = titles.first { norm($0) == norm(g.title) } ?? titles.first { norm($0).hasPrefix(norm(g.title)) } ?? titles.first
        }
        guard let page,
              let r = try? await HTTP.json("\(api)&action=parse&redirects=1&prop=wikitext&page=\(page.urlQueryEscaped)"),
              let text = ((r["parse"] as? [String: Any])?["wikitext"] as? [String: Any])?["*"] as? String else { return nil }
        // First "System requirements" block for Windows.
        let blocks = text.components(separatedBy: "{{System requirements").dropFirst()
        guard let block = blocks.first(where: { $0.contains("OSfamily = Windows") || $0.contains("OSfamily=Windows") }) ?? blocks.first else { return nil }
        var fields = [String: String]()
        for line in block.components(separatedBy: "\n") {
            if line.hasPrefix("}}") { break }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "| \t")) }
            if parts.count == 2, !parts[1].isEmpty { fields[parts[0]] = parts[1].replacingOccurrences(of: "\\[\\[|\\]\\]", with: "", options: .regularExpression) }
        }
        func gpu(_ p: String) -> String? {
            [fields["\(p)GPU"], fields["\(p)GPU2"], fields["\(p)GPU3"]].compactMap { $0 }.joined(separator: " / ").nilIfEmpty
        }
        func ram(_ p: String) -> Int? { fields["\(p)RAM"].flatMap { parse("Memory: \($0)").1 } }
        var out = Requirements(minGPU: gpu("min"), recGPU: gpu("rec"), minRAM: ram("min"), recRAM: ram("rec"), source: "PCGamingWiki")
        if out.recGPU == nil, let v = fields["minVRAM"] { out.minGPU = out.minGPU ?? "\(v) VRAM" }
        return out
    }

    // Steam store (by app id, or by title search).
    private static let steam: (GameGroup, String?) async -> Requirements? = { g, steamId in
        var appId = steamId
        if appId == nil { appId = await CoverSearch.search(g.title).first { norm($0.name) == norm(g.title) }?.id }
        guard let appId,
              let r = try? await HTTP.json("https://store.steampowered.com/api/appdetails?appids=\(appId)&l=english&cc=us"),
              let data = (r[appId] as? [String: Any])?["data"] as? [String: Any] else { return nil }
        let pc = data["pc_requirements"] as? [String: Any]
        let (minG, minR) = parse(pc?["minimum"] as? String)
        let (recG, recR) = parse(pc?["recommended"] as? String)
        return Requirements(appId: appId, minGPU: minG, recGPU: recG, minRAM: minR, recRAM: recR, source: "Steam")
    }

    // GOG catalog (by GOG id, or by title search).
    private static let gog: (GameGroup, String?) async -> Requirements? = { g, _ in
        var id = g.games.first { $0.platform == .gog }?.externalId
        if id == nil, let r = try? await HTTP.json("https://catalog.gog.com/v1/catalog?limit=5&query=like:\(g.title.urlQueryEscaped)"),
           let products = r["products"] as? [[String: Any]] {
            id = products.first { norm($0["title"] as? String ?? "") == norm(g.title) }?["id"] as? String
        }
        guard let id, let r = try? await HTTP.json("https://api.gog.com/v2/games/\(id)"),
              let oses = (r["_embedded"] as? [String: Any])?["supportedOperatingSystems"] as? [[String: Any]],
              let win = oses.first(where: { ($0["operatingSystem"] as? [String: Any])?["name"] as? String == "windows" }) ?? oses.first
        else { return nil }
        var out = Requirements(source: "GOG")
        for req in win["systemRequirements"] as? [[String: Any]] ?? [] {
            let items = req["requirements"] as? [[String: Any]] ?? []
            let gpu = items.first { $0["id"] as? String == "graphics" }?["description"] as? String
            let ram = (items.first { $0["id"] as? String == "memory" }?["description"] as? String).flatMap { parse("Memory: \($0)").1 }
            if req["type"] as? String == "recommended" { out.recGPU = gpu; out.recRAM = ram } else { out.minGPU = gpu; out.minRAM = ram }
        }
        return out
    }

    /// Emulated console games: typical needs of the emulator, by system (index scale, GTX 1060 = 100).
    private static func emulationEstimate(_ g: GameGroup) -> Requirements? {
        guard let sys = g.games.first(where: { $0.launchURL?.hasPrefix("emu:") == true })?.system?.lowercased() else { return nil }
        let table: [(String, Int, Int)] = [
            ("switch", 50, 100), ("wii u", 45, 90), ("playstation 2", 30, 60), ("gamecube", 20, 45), ("wii", 25, 50),
            ("3ds", 20, 40), ("portable", 15, 30), ("playstation", 5, 10), ("64", 5, 12), ("ds", 5, 10),
        ]
        let (mn, rc) = table.first { sys.contains($0.0) }.map { ($0.1, $0.2) } ?? (2, 4)
        return Requirements(minRAM: 4, recRAM: 8, source: String(localized: "Estimation émulation"), fetchedAt: Date(), estMin: mn, estRec: rc)
    }

    /// Extracts "Graphics:" and "Memory:" from Steam's HTML requirement block.
    nonisolated static func parse(_ html: String?) -> (String?, Int?) {
        guard let html else { return (nil, nil) }
        let text = html.replacingOccurrences(of: "<br>", with: "\n").replacingOccurrences(of: "</li>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        var gpu: String?, ram: Int?
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            if gpu == nil, ["graphics:", "video:", "video card:", "graphics card:", "gpu:"].contains(where: lower.hasPrefix) {
                gpu = String(line[line.index(after: line.firstIndex(of: ":")!)...]).trimmingCharacters(in: .whitespaces)
            } else if ram == nil, lower.hasPrefix("memory:") || lower.hasPrefix("ram:") {
                if let r = lower.range(of: "(\\d+(\\.\\d+)?)\\s*(gb|mb)", options: .regularExpression) {
                    let s = String(lower[r])
                    let n = Double(s.filter { $0.isNumber || $0 == "." }) ?? 0
                    ram = s.hasSuffix("mb") ? max(1, Int(n / 1024)) : Int(n.rounded(.up))
                }
            }
        }
        return (gpu, ram)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Precise hardware details, loaded once in the background (see MacSpecs.detectDetails).
@MainActor
final class MacDetailsStore: ObservableObject {
    static let shared = MacDetailsStore()
    @Published private(set) var details: MacSpecs.Details?
    private var loading = false

    func load() {
        guard details == nil, !loading else { return }
        loading = true
        let chip = MacSpecs.current.chip, cores = MacSpecs.current.gpuCores
        Task.detached(priority: .utility) {
            let d = MacSpecs.detectDetails(chip: chip, gpuCores: cores)
            await MainActor.run { MacDetailsStore.shared.details = d }
        }
    }
}
