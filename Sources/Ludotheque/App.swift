// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI

@main
struct LudothequeApp: App {
    /// One library for every window (Observation: no @StateObject needed, views track what they read).
    private var lib: Library { Library.shared }
    @AppStorage("appearance") private var appearance = 0
    @AppStorage("menuBarExtra") private var menuBarExtra = true
    @AppStorage("accent") private var accent = Accent.blue.rawValue
    private var tint: Color { (Accent(rawValue: accent) ?? .blue).color }

    #if DEBUG
    init() {
        // `Ludotheque --dump`: scan and print a summary without UI (debug builds only).
        if CommandLine.arguments.contains("--dump") {
            let t0 = Date()
            var d = Library.scanAll()
            print("SCAN", Date().timeIntervalSince(t0), "s")
            let sem = DispatchSemaphore(value: 0)
            Task.detached {
                d = await GamesDB.shared.applyCached(d)
                sem.signal()
            }
            sem.wait()
            let games = d.values.filter { $0.hasTitle && !$0.isDLC }
            let groups = Dictionary(grouping: games, by: \.groupKey)
            print("GROUPS", groups.count, "MULTI", groups.values.filter { $0.count > 1 }.count,
                  "KINDS", Dictionary(grouping: games, by: \.launchKind).mapValues(\.count))
            print("PLATFORMS", Dictionary(grouping: games, by: \.platform.rawValue).mapValues(\.count))
            for g in games where g.platform == .riot || g.title.lowercased().contains("minecraft") {
                print("CHECK", g.platform.rawValue, g.title, g.launchKind.rawValue, g.launchURL ?? "-")
            }
            print("SELFTEST", Emulation.cleanTitle("Legend of Zelda, The - Link's Awakening DX (USA, Europe) (Rev 2) [!]"),
                  Emulation.tokenize("-L \"~/My Cores/x.dylib\" {rom}"), Integrations.isoDurationMinutes("PT2H5M") ?? -1)
            let m = MacSpecs.current
            print("MAC", m.chip, m.gpuCores ?? -1, "cores", m.memoryGB, "GB", m.screenWidth, m.screenHeight, m.refreshRate, "Hz", "index", m.gpuIndex, m.equivalent)
            for l in ["GeForce GTX 1060 6GB or Radeon RX 580 8GB or Arc A380", "Nvidia GeForce 9800 GTX", "Intel HD Graphics 4000",
                      "NVIDIA GeForce RTX 2060 SUPER / AMD Radeon RX 5700 XT", "2 GB VRAM, DirectX 11", "GeForce GTX660"] {
                print("GPU", l, "=>", GPUIndex.parseLine(l) ?? -1)
            }
            print("PARSE", PerfStore.parse("<li><strong>Memory:</strong> 12 GB RAM<br></li><li><strong>Graphics:</strong> GeForce GTX 970</li>"))
            print("TARGET", PerfTarget.minimum.label, PerfTarget.minimum.factor, PerfTarget.recommended.label, PerfTarget.recommended.factor)
            var g = Game(id: "t", platform: .steam, externalId: "1", title: "t"); g.macNative = true
            for (mn, rc) in [(38, 65), (100, 160), (12, 25)] {
                print("VERDICT min", mn, "rec", rc, "=>", PerfMath.verdict(Requirements(minRAM: 4, recRAM: 8, estMin: mn, estRec: rc), game: g).label)
            }
            print("TOTAL", games.count, "in", Date().timeIntervalSince(t0), "s")
            exit(0)
        }
        if UserDefaults.standard.bool(forKey: "debugPageScroll") { Self.startPageScrollTest() }
    }
    #endif

    #if DEBUG
    /// `-debugPageScroll YES`: scrolls the biggest scroll view of the window continuously (any page).
    static func startPageScrollTest() {
        Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
            func all(_ v: NSView) -> [NSScrollView] { (v as? NSScrollView).map { [$0] } ?? [] + v.subviews.flatMap(all) }
            guard let root = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })?.contentView,
                  let sv = all(root).filter({ ($0.documentView?.frame.height ?? 0) > $0.bounds.height + 50 })
                    .max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) else { print("no scroll view"); return }
            print("scrolling", type(of: sv.documentView!), sv.documentView!.frame.height); fflush(stdout)
            var down = true
            Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
                let clip = sv.contentView, maxY = (sv.documentView?.frame.height ?? 0) - clip.bounds.height
                var y = clip.bounds.origin.y + (down ? 12 : -12)
                if y >= maxY { y = maxY; down = false } else if y <= 0 { y = 0; down = true }
                clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
                sv.reflectScrolledClipView(clip)
            }
        }
    }
    #endif

    private var scheme: ColorScheme? { appearance == 1 ? .light : appearance == 2 ? .dark : nil }

    var body: some Scene {
        WindowGroup("Ludothèque", id: "main") {
            ContentView()
                .environment(lib)
                .frame(minWidth: 860, minHeight: 540)
                .preferredColorScheme(scheme)
                .tint(tint)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Saisir un jeu manuellement…") { lib.newManual() }.keyboardShortcut("n")
                Button("Ajouter une application Mac…") { lib.addApps() }.keyboardShortcut("o")
                Divider()
                Button("Exporter la bibliothèque (CSV)…") { lib.exportCSV() }
                Button("Sauvegarder mes données…") { lib.backup() }
            }
            CommandMenu("Bibliothèque") {
                Button("Tout actualiser") { Task { await lib.refreshAll(manual: true) } }.keyboardShortcut("r")
                Button("Rechercher les jeux") { Task { await lib.searchGames() } }
                Button("Synchroniser les API") { Task { await lib.runSync(Integrations.all.filter(\.isConnected)) } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Jeu au hasard") { lib.pickRandom() }.keyboardShortcut("j")
                Divider()
                Button("Tous les jeux") { lib.scope = .all }.keyboardShortcut("1")
                Button("Jouables") { lib.scope = .playable }.keyboardShortcut("2")
                Button("Installés") { lib.scope = .installed }.keyboardShortcut("3")
                Button("Installables localement") { lib.scope = .installable }.keyboardShortcut("4")
                Button("Cloud") { lib.scope = .cloud }.keyboardShortcut("5")
                Button("Récents") { lib.scope = .recent }.keyboardShortcut("6")
                Button("Favoris") { lib.scope = .favorites }.keyboardShortcut("7")
                Divider()
                Button("Réinitialiser les filtres") { lib.filters = Filters() }.keyboardShortcut("0")
            }
            CommandGroup(replacing: .appInfo) {
                Button("À propos de Ludothèque") { showAbout() }
            }
            CommandGroup(replacing: .help) {
                OpenWindowButton(title: "Mes autres logiciels…", id: "myapps", key: nil)
                Link("Ludothèque sur GitHub", destination: Author.repo)
            }
            CommandGroup(after: .windowArrangement) {
                OpenWindowButton(title: "Gestion des plateformes", id: "platforms", key: "p")
                OpenWindowButton(title: "Mode TV (manette)", id: "tv", key: "t")
                OpenWindowButton(title: "Statistiques", id: "stats", key: "i")
            }
        }

        Window("Mode TV", id: "tv") {
            TVModeView().environment(lib).preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)

        Window("Gestion des plateformes", id: "platforms") {
            IntegrationsView().environment(lib).preferredColorScheme(scheme).tint(tint)
        }

        Window("Mes logiciels", id: "myapps") {
            MyAppsView().preferredColorScheme(scheme).tint(tint)
        }
        .windowResizability(.contentSize)

        Window("Statistiques", id: "stats") {
            StatsView().environment(lib).preferredColorScheme(scheme).tint(tint).frame(minWidth: 760, minHeight: 600)
        }

        // Never bind `isInserted` straight to @AppStorage: SwiftUI writes the (unchanged) value back on
        // every app update → UserDefaults notification → every view redrawn → 100 % CPU loop.
        MenuBarExtra("Ludothèque", systemImage: "gamecontroller.fill",
                     isInserted: Binding(get: { menuBarExtra }, set: { if $0 != menuBarExtra { menuBarExtra = $0 } })) {
            MenuBarContent().environment(lib)
        }

        Settings {
            SettingsView().environment(lib).preferredColorScheme(scheme).tint(tint)
        }
    }
}

private struct OpenWindowButton: View {
    @Environment(\.openWindow) private var openWindow
    let title: String, id: String, key: KeyEquivalent?
    var body: some View {
        if let key {
            Button(title) { openWindow(id: id) }.keyboardShortcut(key, modifiers: [.command, .shift])
        } else {
            Button(title) { openWindow(id: id) }
        }
    }
}

/// Fenêtre « À propos » de macOS, avec le crédit de l'auteur.
private func showAbout() {
    let credits = NSAttributedString(
        string: "Créé par \(Author.name) — github.com/\(Author.name)\nLogiciel libre sous licence GPL-3.0-or-later.",
        attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    NSApp.activate(ignoringOtherApps: true)
}

/// Quick launcher in the menu bar (like the Steam / Battle.net tray menus).
private struct MenuBarContent: View {
    @Environment(Library.self) var lib
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let recent = lib.groups.filter { $0.primary.launchKind == .installed }
            .sorted { (lib.lastPlayed($0) ?? .distantPast) > (lib.lastPlayed($1) ?? .distantPast) }.prefix(10)
        Section("Jouer") {
            ForEach(Array(recent)) { g in
                Button(lib.title(g)) { lib.launch(g.primary) }
            }
            if recent.isEmpty { Text("Aucun jeu installé") }
        }
        Divider()
        Button("Jeu au hasard") {
            if let g = lib.groups.filter({ $0.primary.launchKind == .installed }).randomElement() { lib.launch(g.primary) }
        }
        let free = FreeGamesStore.shared.active.filter { !FreeGamesStore.shared.claimed.contains($0.id) }
        if !free.isEmpty {
            Menu("Jeux gratuits (\(free.count))") {
                ForEach(free.prefix(10)) { gv in Button(gv.cleanTitle) { if let u = URL(string: gv.url) { NSWorkspace.shared.open(u) } } }
            }
        }
        Divider()
        Button("Tout actualiser") { Task { await lib.refreshAll(manual: true) } }
        Button("Ouvrir Ludothèque") {
            NSApp.activate(ignoringOtherApps: true)
            if let w = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true }) {
                w.makeKeyAndOrderFront(nil)
            } else { openWindow(id: "main") }
        }
        Button("Mode TV") { openWindow(id: "tv") }
        Divider()
        Button("Quitter") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
