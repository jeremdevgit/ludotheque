// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import AppKit
import Combine
import QuartzCore

/// Scripted fluidity benchmark, only with the launch argument `-benchmark YES` (never in normal use).
/// Drives the real UI (navigation, selection, search, scrolling) and measures every frame with a
/// display link: a frame that arrives late means the main thread was busy (a visible stutter).
/// Results: printed and written to `-benchmarkOut <path>` (JSON), then the app quits.
@MainActor
final class Benchmark: NSObject {
    static var current: Benchmark?

    static func startIfRequested(_ lib: Library) {
        guard UserDefaults.standard.bool(forKey: "benchmark"), current == nil else { return }
        let b = Benchmark()
        current = b
        Task { await b.run(lib) }
    }

    struct Step: Codable {
        var name: String
        var firstFrameMs: Double     // action → next frame on screen
        var worstGapMs: Double       // longest time between two frames in the window
        var hitchMs: Double          // total lateness (sum of frame overruns) in the window
        var frames: Int
        var seconds: Double
    }

    private var link: CADisplayLink?
    private var ticks: [CFTimeInterval] = []
    private var interval: CFTimeInterval = 1.0 / 60
    private var steps: [Step] = []
    private var scrollSpeed: CGFloat = 0           // pt/s while scrolling
    private weak var scrollView: NSScrollView?
    private var lastTick: CFTimeInterval = 0

    @objc private func tick(_ l: CADisplayLink) {
        let now = CACurrentMediaTime()
        if scrollSpeed > 0, let sv = scrollView, let doc = sv.documentView {
            let dt = lastTick > 0 ? min(0.1, now - lastTick) : interval
            let clip = sv.contentView
            var y = clip.bounds.origin.y + scrollSpeed * dt
            if y > doc.bounds.height - clip.bounds.height { y = 0 }
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
            sv.reflectScrolledClipView(clip)
        }
        lastTick = now
        ticks.append(now)
    }

    private func startLink() {
        guard let screen = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })?.screen ?? NSScreen.main else { return }
        interval = 1.0 / Double(max(30, screen.maximumFramesPerSecond))
        let l = screen.displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    /// Runs `action`, then records frames for `seconds`.
    private func measure(_ name: String, seconds: Double = 1.2, _ action: () -> Void) async {
        ticks.removeAll(keepingCapacity: true)
        let t0 = CACurrentMediaTime()
        action()
        try? await Task.sleep(for: .seconds(seconds))
        let t = ticks.filter { $0 >= t0 }
        var worst = 0.0, hitch = 0.0
        var prev = t0
        for x in t {
            let gap = x - prev
            worst = max(worst, gap)
            if gap > interval * 1.5 { hitch += gap - interval }
            prev = x
        }
        let first = (t.first ?? CACurrentMediaTime()) - t0
        steps.append(Step(name: name, firstFrameMs: first * 1000, worstGapMs: worst * 1000, hitchMs: hitch * 1000,
                          frames: t.count, seconds: seconds))
    }

    private func biggestScrollView() -> NSScrollView? {
        func all(_ v: NSView) -> [NSScrollView] { ((v as? NSScrollView).map { [$0] } ?? []) + v.subviews.flatMap(all) }
        guard let root = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })?.contentView else { return nil }
        return all(root).filter { ($0.documentView?.frame.height ?? 0) > $0.bounds.height + 50 }
            .max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
    }

    private static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    private static func cpuSeconds() -> Double {
        var u = rusage()
        getrusage(RUSAGE_SELF, &u)
        return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1_000_000
    }

    private func run(_ lib: Library) async {
        // Measured window in front (an occluded window is not redrawn) and no App Nap throttling.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical, .idleDisplaySleepDisabled],
                                                             reason: "benchmark")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        try? await Task.sleep(for: .seconds(1))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .seconds(5))      // startup finished, first covers loaded
        startLink()
        var extra: [String: Double] = [:]
        extra["memStartMB"] = Self.footprintMB()

        // `-benchmarkScrollOnly 8`: only scrolls the library grid for that many seconds (profiling).
        let scrollOnly = UserDefaults.standard.double(forKey: "benchmarkScrollOnly")
        if scrollOnly > 0 {
            lib.scope = .all
            try? await Task.sleep(for: .seconds(1))
            scrollView = biggestScrollView()
            await measure("défilement grille", seconds: scrollOnly) { scrollSpeed = 2500 }
            scrollSpeed = 0
            try? await Task.sleep(for: .seconds(1.5))
            // `-benchmarkSnapshot file.png`: picture of the window after scrolling (checks what is displayed).
            if let path = UserDefaults.standard.string(forKey: "benchmarkSnapshot"),
               let v = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })?.contentView,
               let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            report(extra)
            NSApp.terminate(nil)
            return
        }

        // Idle: nothing should run when nobody touches the app.
        // `-benchmarkRoute all,wishlist -benchmarkRepeat 6`: only these page switches (profiling one page).
        if let raw = UserDefaults.standard.string(forKey: "benchmarkRoute") {
            let scopes = raw.split(separator: ",").compactMap { try? JSONDecoder().decode(Scope.self, from: Data("\"\($0)\"".utf8)) }
            let n = max(1, UserDefaults.standard.integer(forKey: "benchmarkRepeat"))
            for i in 0..<n { for s in scopes { await measure("nav \(s) #\(i + 1)") { lib.scope = s } } }
            report(extra)
            NSApp.terminate(nil)
            return
        }

        // Who invalidates the UI while idle (each publish redraws every observing view).
        var counts: [String: Int] = [:]
        var snap = UserDefaults.standard.dictionaryRepresentation()
        let pubs: [(String, AnyPublisher<Void, Never>)] = [
            ("FreeGames", FreeGamesStore.shared.objectWillChange.map { _ in }.eraseToAnyPublisher()),
            ("Wishlist", WishlistStore.shared.objectWillChange.map { _ in }.eraseToAnyPublisher()),
            ("SessionLog", SessionLog.shared.objectWillChange.map { _ in }.eraseToAnyPublisher()),
            ("TaskCenter", TaskCenter.shared.objectWillChange.map { _ in }.eraseToAnyPublisher()),
            ("Profile", ProfileStore.shared.objectWillChange.map { _ in }.eraseToAnyPublisher()),
            ("SidebarBadges", SidebarBadges.shared.objectWillChange.map { _ in }.eraseToAnyPublisher()),
            ("Status", StatusCenter.shared.objectWillChange.map { _ in }.eraseToAnyPublisher()),
            ("Logos", LogoCache.shared.objectWillChange.map { _ in }.eraseToAnyPublisher()),
            ("TileStyle", TileStyleStore.shared.objectWillChange.map { _ in }.eraseToAnyPublisher()),
            ("News", NewsStore.shared.objectWillChange.map { _ in }.eraseToAnyPublisher()),
            ("Refresh", RefreshCenter.shared.objectWillChange.map { _ in }.eraseToAnyPublisher()),
            ("Perf", PerfStore.shared.objectWillChange.map { _ in }.eraseToAnyPublisher()),
            ("Achievements", AchievementHub.shared.objectWillChange.map { _ in }.eraseToAnyPublisher()),
        ]
        var subs = pubs.map { name, p in p.sink { counts[name, default: 0] += 1 } }
        subs.append(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).sink { _ in
            counts["UserDefaults", default: 0] += 1
            let now = UserDefaults.standard.dictionaryRepresentation()
            for (k, v) in now where !((snap[k] as? NSObject)?.isEqual(v) ?? false) { counts["clé " + k, default: 0] += 1 }
            snap = now
        })
        UserDefaults.benchSwizzle()
        UserDefaults.benchRecording = true
        let c0 = Self.cpuSeconds()
        await measure("idle", seconds: 3) {}
        UserDefaults.benchRecording = false
        for (k, v) in UserDefaults.benchWrites { extra["idle write " + k] = Double(v) }
        if let out = UserDefaults.standard.string(forKey: "benchmarkOut") {
            let txt = UserDefaults.benchStacks.map { "== \($0.key)\n\($0.value)" }.joined(separator: "\n\n")
            try? txt.write(toFile: out + ".writes.txt", atomically: true, encoding: .utf8)
        }
        extra["idleCPUPercent"] = (Self.cpuSeconds() - c0) / 3 * 100
        for (k, v) in counts { extra["idle publish " + k] = Double(v) }
        subs.removeAll()

        // Sidebar navigation.
        let route: [(String, Scope)] = [("nav Tous les jeux", .all), ("nav Accueil", .home), ("nav Steam", .platform(.steam)),
                                        ("nav Statistiques", .statistics), ("nav Tous les jeux (2)", .all), ("nav Succès", .achievements),
                                        ("nav Performances", .performance), ("nav Jeux gratuits", .freeGames), ("nav Souhaits", .wishlist),
                                        ("nav Profil", .profile), ("nav Options", .options), ("nav Actualisations", .refresh),
                                        ("nav Installés", .installed), ("nav Jeux Windows", .windows), ("nav Tous les jeux (3)", .all)]
        for (name, s) in route { await measure(name) { lib.scope = s } }

        // Selecting games (details panel).
        var rng = SystemRandomNumberGenerator()
        let pool = Array(lib.visibleGroups.prefix(40))
        for i in 0..<8 where !pool.isEmpty {
            let g = pool.randomElement(using: &rng)!
            await measure("sélection \(i + 1)", seconds: 0.8) { lib.selected = g.id }
        }
        await measure("fermer la fiche", seconds: 0.8) { lib.selected = nil }

        // Typing in the search field, then clearing it.
        ticks.removeAll()
        let typed = "the witcher"
        await measure("recherche (frappe)", seconds: Double(typed.count) * 0.12 + 0.8) {
            for (i, _) in typed.enumerated() {
                let prefix = String(typed.prefix(i + 1))
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.12) { lib.searchInput = prefix }
            }
        }
        await measure("recherche (effacer)") { lib.searchInput = "" }

        // Scrolling the library grid.
        lib.scope = .all
        try? await Task.sleep(for: .seconds(1))
        scrollView = biggestScrollView()
        if let sv = scrollView { sv.contentView.scroll(to: .zero); sv.reflectScrolledClipView(sv.contentView) }
        await measure("défilement grille", seconds: 6) { scrollSpeed = 2500 }
        scrollSpeed = 0
        // Content check, not just speed: every tile in the visible area must exist and show a cover.
        try? await Task.sleep(for: .seconds(1.5))
        if let cv = scrollView?.documentView as? NSCollectionView, let layout = cv.collectionViewLayout {
            let vr = cv.visibleRect
            let expected = layout.layoutAttributesForElements(in: vr).filter { $0.representedElementCategory == .item && $0.frame.intersects(vr) }.count
            let shown = cv.visibleItems().filter { $0.view.superview != nil && !$0.view.isHidden && $0.view.frame.intersects(vr) }
            extra["grilleTuilesAttendues"] = Double(expected)
            extra["grilleTuilesAffichées"] = Double(shown.count)
            extra["grilleTuilesAvecJaquette"] = Double(shown.filter { ($0.view.layer?.sublayers?.first?.contents) != nil }.count)
            extra["grillePositionY"] = Double(vr.minY)
        }
        extra["memAfterScrollMB"] = Self.footprintMB()

        // Scrolling the home page.
        lib.scope = .home
        try? await Task.sleep(for: .seconds(1))
        scrollView = biggestScrollView()
        await measure("défilement accueil", seconds: 3) { scrollSpeed = 1500 }
        scrollSpeed = 0

        extra["memEndMB"] = Self.footprintMB()
        report(extra)
        NSApp.terminate(nil)
    }

    private func report(_ extra: [String: Double]) {
        var lines = ["ÉTAPE                         1re image   pire écart   retard total"]
        for s in steps {
            lines.append(s.name.padding(toLength: 30, withPad: " ", startingAt: 0)
                         + String(format: "%8.0f ms %10.0f ms %12.0f ms", s.firstFrameMs, s.worstGapMs, s.hitchMs))
        }
        for (k, v) in extra.sorted(by: { $0.key < $1.key }) { lines.append("\(k): \(String(format: "%.1f", v))") }
        print(lines.joined(separator: "\n"))
        fflush(stdout)
        if let out = UserDefaults.standard.string(forKey: "benchmarkOut") {
            struct R: Codable { var steps: [Step]; var extra: [String: Double] }
            if let d = try? JSONEncoder().encode(R(steps: steps, extra: extra)) { try? d.write(to: URL(fileURLWithPath: out)) }
        }
    }
}

// MARK: - Benchmark diagnostics: who writes to UserDefaults (each write notifies every @AppStorage view)

extension UserDefaults {
    nonisolated(unsafe) static var benchWrites: [String: Int] = [:]
    nonisolated(unsafe) static var benchStacks: [String: String] = [:]
    nonisolated(unsafe) static var benchRecording = false

    nonisolated static func benchNote(_ key: String) {
        guard benchRecording else { return }
        benchWrites[key, default: 0] += 1
        if benchStacks[key] == nil {
            benchStacks[key] = Thread.callStackSymbols.prefix(28).joined(separator: "\n")
        }
    }

    @objc dynamic func bench_setObject(_ value: Any?, forKey key: String) {
        UserDefaults.benchNote(key)
        bench_setObject(value, forKey: key)
    }
    @objc dynamic func bench_removeObject(forKey key: String) {
        UserDefaults.benchNote("(remove) " + key)
        bench_removeObject(forKey: key)
    }

    static func benchSwizzle() {
        let pairs: [(Selector, Selector)] = [
            (NSSelectorFromString("setObject:forKey:"), #selector(bench_setObject(_:forKey:))),
            (NSSelectorFromString("removeObjectForKey:"), #selector(bench_removeObject(forKey:))),
        ]
        for (a, b) in pairs {
            guard let m1 = class_getInstanceMethod(UserDefaults.self, a), let m2 = class_getInstanceMethod(UserDefaults.self, b) else { continue }
            method_exchangeImplementations(m1, m2)
        }
    }
}
