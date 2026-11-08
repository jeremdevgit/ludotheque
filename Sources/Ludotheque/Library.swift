// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation
import Combine
import Observation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum Scope: Hashable {
    case all, playable, installed, installable, cloud, favorites, recent
    case platform(Platform)
    case preset(String)
    case performance
    case emulators
    case home, freeGames, wishlist
    case profile, options, statistics, search, freeLoot, achievements, windows, refresh
}

extension Scope {
    /// Scopes shown as a game grid / list (the others are dedicated pages).
    var isLibrary: Bool {
        switch self {
        case .home, .freeGames, .wishlist, .profile, .options, .statistics, .search, .freeLoot, .achievements, .emulators, .performance, .windows, .refresh: false
        default: true
        }
    }
}

/// Per-tile observable flag (selection): only the tiles whose flag flips are redrawn.
@MainActor
@Observable
final class TileFlag { var on = false }

enum SortOrder: String, CaseIterable, Identifiable, Codable {
    case title = "Nom", recent = "Dernière partie", playtime = "Temps de jeu", rating = "Ma note"
    case status = "Statut", platform = "Plateforme", added = "Ajout"
    var id: String { rawValue }
}

enum GroupBy: String, CaseIterable, Identifiable {
    case none = "Aucun", availability = "Disponibilité", status = "Statut", platform = "Plateforme", letter = "Initiale"
    var id: String { rawValue }
}

/// Extra filters combined with the sidebar scope.
struct Filters: Equatable, Codable {
    var kinds: Set<LaunchKind> = []
    var platforms: Set<Platform> = []
    var statuses: Set<Completion> = []
    var tags: Set<String> = []
    var minRating = 0
    var macOnly = false
    var favoritesOnly = false
    var playedOnly = false

    var activeCount: Int {
        [!kinds.isEmpty, !platforms.isEmpty, !statuses.isEmpty, !tags.isEmpty, minRating > 0, macOnly, favoritesOnly, playedOnly]
            .filter { $0 }.count
    }
}

/// Observation (not ObservableObject): each view is redrawn only when a property it actually read
/// changes. Selecting a game no longer redraws the sidebar, the toolbar, the menus and every tile.
@MainActor
@Observable
final class Library {
    static let shared = Library()

    private(set) var games: [Game] = [] { didSet { regroup() } }
    /// Bumped whenever games, groups or user data change. Memoised accessors read it, so views that
    /// used a cached value are still invalidated when the underlying data changes.
    private(set) var version = 0
    // Memoised results: the views ask for them on every redraw.
    @ObservationIgnored private var visibleCache: (key: String, value: [GameGroup])?
    @ObservationIgnored private var countCache: [String: Int] = [:]
    @ObservationIgnored private var keyOf: [String: String] = [:]          // game id → group key
    @ObservationIgnored private var keyCache: [String: (title: String, key: String)] = [:]
    private func invalidate() { version += 1; visibleCache = nil; countCache.removeAll(keepingCapacity: true) }
    /// Group key of a game (cached; computing it is string-heavy).
    func gkey(_ g: Game) -> String { keyOf[g.id] ?? g.groupKey }
    private(set) var groups: [GameGroup] = []
    var scope: Scope = .home {
        didSet {
            // Leaving a saved view must not leave its filters silently applied.
            if case .preset = oldValue, scope != oldValue { filters = Filters() }
            applyPresetIfNeeded()
            if scope.isLibrary != libraryScope { libraryScope = scope.isLibrary }
        }
    }
    /// Derived flags that change far less often than what they derive from: the toolbar and the
    /// inspector read these instead of `scope` / `selected`, so they aren't rebuilt at every click.
    private(set) var libraryScope = false
    private(set) var inspectorShown = false
    /// What the search field shows; `search` (which filters the library) follows it 200 ms after the last keystroke.
    var searchInput = "" { didSet { if searchInput != oldValue { scheduleSearch() } } }
    var search = "" { didSet { if search.isEmpty && !searchInput.isEmpty { searchInput = "" } } }
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    private func scheduleSearch() {
        searchTask?.cancel()
        let q = searchInput
        // Typing from a page that isn't a game list jumps to "Tous les jeux".
        if !q.isEmpty && !scope.isLibrary { scope = .all }
        if q.isEmpty { if !search.isEmpty { search = "" }; return }   // clearing is immediate
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self, self.search != q else { return }
            self.search = q
        }
    }
    var sort: SortOrder = .title
    var filters = Filters()
    /// Group id shown in the details panel. Tiles don't read it (that would redraw all of them):
    /// each one watches its own flag, so a click redraws two tiles.
    var selected: String? {
        didSet {
            guard selected != oldValue else { return }
            if let o = oldValue { selectionFlags[o]?.on = false }
            if let n = selected { selectionFlags[n]?.on = true }
            if (selected != nil) != inspectorShown { inspectorShown = selected != nil }
        }
    }
    @ObservationIgnored private var selectionFlags: [String: TileFlag] = [:]
    func selectionFlag(_ id: String) -> TileFlag {
        if let f = selectionFlags[id] { return f }
        let f = TileFlag()
        f.on = _selected == id      // backing storage: no dependency for the caller
        selectionFlags[id] = f
        return f
    }
    var scrollTarget: String?      // set by "Jeu au hasard" to scroll the grid
    /// Short confirmations live in StatusCenter so they don't redraw every tile.
    var status: String? { StatusCenter.shared.message }
    private(set) var scanning = false
    private(set) var syncing: Set<Platform> = []
    var favorites: Set<String> { didSet { save(favorites, "favorites"); invalidate() } }
    var hidden: Set<String> { didSet { save(hidden, "hidden"); invalidate(); regroup() } }
    var showHidden = false { didSet { if showHidden != oldValue { invalidate(); regroup() } } }
    var editing: ManualGame?
    var uninstalling: Game?
    private(set) var user: [String: UserEntry] = Store<[String: UserEntry]>.load("user-data.json", [:])
    private(set) var presets: [Preset] = Store<[Preset]>.load("presets.json", []) { didSet { invalidate() } }

    @ObservationIgnored private let cacheURL = Paths.support.appendingPathComponent("library.json")
    @ObservationIgnored private var sessions: PlaySessions!
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        PerfMonitor.shared.start()
        favorites = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? [])
        hidden = Set(UserDefaults.standard.stringArray(forKey: "hidden") ?? [])
        // Instant start from the last scan; refresh in the background.
        if let d = try? Data(contentsOf: cacheURL), let g = try? JSONDecoder().decode([Game].self, from: d) { games = g }
        regroup()
        let ud = UserDefaults.standard
        if let raw = ud.string(forKey: "startScope"), let sc = try? JSONDecoder().decode(Scope.self, from: Data("\"\(raw)\"".utf8)) { scope = sc }
        sort = SortOrder(rawValue: ud.string(forKey: "defaultSort") ?? "") ?? .title
        #if DEBUG
        // `-debugScope platform:ubisoft` opens a given view (UI debugging).
        if let raw = UserDefaults.standard.string(forKey: "debugScope"),
           let sc = try? JSONDecoder().decode(Scope.self, from: Data("\"\(raw)\"".utf8)) { scope = sc }
        #endif
        sessions = PlaySessions { [weak self] key, minutes in self?.addPlaytime(key, minutes) }
        libraryScope = scope.isLibrary      // observers don't run during init
        Benchmark.startIfRequested(self)
        // Full refresh at launch, then every 6 hours while the app stays open.
        // Keychain lookups are slow: warm the cache off the main thread.
        Task.detached(priority: .utility) { for i in Integrations.all { _ = i.isConnected } }
        // Manual mode by default: the app opens on cached data. Automation is opt-in (Actualisations tab).
        Task {
            try? await Task.sleep(for: .milliseconds(1200))   // let the window appear first
            if ud.object(forKey: "refreshAtLaunch") as? Bool ?? false { await RefreshCenter.shared.runAll(self) }
            while !Task.isCancelled {
                let h = ud.object(forKey: "refreshHours") as? Int ?? 0
                try? await Task.sleep(for: .seconds(Double(max(1, h)) * 3600))
                if h > 0 { await RefreshCenter.shared.runAll(self) }
            }
        }
    }

    private func save(_ s: Set<String>, _ key: String) { UserDefaults.standard.set(Array(s), forKey: key) }

    // MARK: User data (status, rating, notes, tags, overrides, tracked time)

    func entry(_ key: String) -> UserEntry { user[key] ?? UserEntry() }

    func update(_ key: String, _ change: (inout UserEntry) -> Void) {
        var e = entry(key)
        change(&e)
        guard user[key] != e else { return }
        user[key] = e
        invalidate()
        // Debounced: notes are edited keystroke by keystroke.
        saveTask?.cancel()
        let snapshot = user
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            Store<[String: UserEntry]>.save("user-data.json", snapshot)
        }
    }

    func binding(_ key: String) -> Binding<UserEntry> {
        Binding(get: { self.entry(key) }, set: { v in self.update(key) { $0 = v } })
    }

    func title(_ g: GameGroup) -> String { user[g.key]?.customTitle.flatMap { $0.isEmpty ? nil : $0 } ?? g.title }

    func coverGame(_ g: GameGroup) -> Game {
        var c = g.coverGame
        if let custom = user[g.key]?.customCover, !custom.isEmpty { c.coverURL = custom; c.altCoverURL = nil }
        return c
    }

    func playtime(_ g: GameGroup) -> Int { g.playtime + (user[g.key]?.trackedMinutes ?? 0) }
    func lastPlayed(_ g: GameGroup) -> Date? { [g.lastPlayed, user[g.key]?.lastLaunched].compactMap { $0 }.max() }
    func statusOf(_ g: GameGroup) -> Completion { user[g.key]?.status ?? .none }

    var allTags: [String] { Array(Set(user.values.flatMap { $0.tags ?? [] })).sorted() }

    private func addPlaytime(_ key: String, _ minutes: Int) {
        guard key != "__untracked__" else { return }
        let title = groups.first { $0.key == key }.map(title) ?? key
        SessionLog.shared.add(key: key, title: title, minutes: minutes)
        update(key) {
            $0.trackedMinutes = ($0.trackedMinutes ?? 0) + minutes
            if $0.status == nil || $0.status == Completion.none || $0.status == .planned { $0.status = .playing }
        }
        flash(String(localized: "\(minutes) min de jeu enregistrées"))
    }

    // MARK: Grouping & filtering

    func reloadGrouping() { regroup() }

    private func regroup() {
        invalidate()
        // Group keys only depend on the title: recompute them only for new / renamed games.
        var keys = [String: String](minimumCapacity: games.count)
        for g in games {
            if let c = keyCache[g.id], c.title == g.title { keys[g.id] = c.key }
            else { let k = g.groupKey; keyCache[g.id] = (g.title, k); keys[g.id] = k }
        }
        keyOf = keys
        let shown = games.filter { showHidden || !hidden.contains($0.id) }
        let merge = UserDefaults.standard.object(forKey: "groupDuplicates") as? Bool ?? true
        groups = Dictionary(grouping: shown, by: { merge ? keys[$0.id]! : $0.id }).map { GameGroup(id: $0.key, games: $0.value, key: keys[$0.value[0].id]) }
        // Remember when each game first appeared ("Ajout" sort).
        let now = Date()
        var changed = false
        for g in groups where user[g.key]?.added == nil {
            var e = user[g.key] ?? UserEntry()
            e.added = now
            user[g.key] = e
            changed = true
        }
        if changed { Store<[String: UserEntry]>.save("user-data.json", user) }
    }

    private var baseScope: Scope {
        if case .preset(let id) = scope, let p = presets.first(where: { $0.id == id }) { return p.scope }
        return scope
    }

    func matches(_ g: Game, _ s: Scope) -> Bool {
        switch s {
        case .all: true
        case .playable: g.launchKind != .none
        case .installed: g.launchKind == .installed
        case .installable: g.launchKind == .installable
        case .cloud: g.launchKind == .cloud
        case .favorites: favorites.contains(g.id)
        case .recent: (g.lastPlayed ?? user[gkey(g)]?.lastLaunched).map { $0 > Date().addingTimeInterval(-60 * 86400) } ?? false
        case .platform(let p): g.platform == p
        case .preset(let id): presets.first { $0.id == id }.map { matches(g, $0.scope) } ?? true
        case .performance: g.launchKind == .installed || g.launchKind == .installable
        case .emulators: g.launchURL?.hasPrefix("emu:") == true
        case .home, .freeGames, .wishlist, .profile, .options, .statistics, .search, .freeLoot, .achievements, .windows, .refresh: true
        }
    }

    func passes(_ g: Game) -> Bool { passes(g, filters) }

    func passes(_ g: Game, _ f: Filters) -> Bool {
        if !f.kinds.isEmpty && !f.kinds.contains(g.launchKind) { return false }
        if !f.platforms.isEmpty && !f.platforms.contains(g.platform) { return false }
        if f.macOnly && g.macNative != true { return false }
        if f.favoritesOnly && !favorites.contains(g.id) { return false }
        let u = user[gkey(g)]
        if f.playedOnly && (g.playtimeMinutes ?? 0) == 0 && g.lastPlayed == nil && u?.lastLaunched == nil { return false }
        if !f.statuses.isEmpty && !f.statuses.contains(u?.status ?? .none) { return false }
        if f.minRating > 0 && (u?.rating ?? 0) < f.minRating { return false }
        if !f.tags.isEmpty && f.tags.isDisjoint(with: u?.tags ?? []) { return false }
        return true
    }

    /// Same game on several platforms → one tile, except inside a platform view.
    var visibleGroups: [GameGroup] {
        let key = "\(scope)|\(filters)|\(search)|\(sort)|\(version)|\(UserDefaults.standard.bool(forKey: "playableOnlyInAll"))"
        if let c = visibleCache, c.key == key { return c.value }
        let v = sortedGroups(filtered(filters, search))
        visibleCache = (key, v)
        return v
    }

    /// Groups of the current view for given filters / search (no sorting, no state change).
    private func filtered(_ f: Filters, _ search: String) -> [GameGroup] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let scope = baseScope
        var list: [GameGroup]
        if case .platform = scope {
            list = games.filter { (showHidden || !hidden.contains($0.id)) && matches($0, scope) && passes($0, f) }
                .map { GameGroup(id: $0.id, games: [$0]) }
        } else {
            list = groups.filter { grp in grp.games.contains { matches($0, scope) && passes($0, f) } }
            if scope == .all, UserDefaults.standard.bool(forKey: "playableOnlyInAll") {
                list = list.filter { $0.games.contains { $0.launchKind != .none } }
            }
        }
        if !q.isEmpty { list = list.filter { title($0).lowercased().contains(q) || $0.games.contains { $0.title.lowercased().contains(q) } } }
        return list
    }

    /// Sort keys are computed once per group (not at every comparison).
    private func sortedGroups(_ input: [GameGroup]) -> [GameGroup] {
        let titles = input.map { title($0).lowercased() }
        func by<T: Comparable>(_ value: (GameGroup) -> T, descending: Bool) -> [GameGroup] {
            let vals = input.map(value)
            return input.indices.sorted { i, j in
                if vals[i] != vals[j] { return descending ? vals[i] > vals[j] : vals[i] < vals[j] }
                return titles[i] < titles[j]
            }.map { input[$0] }
        }
        switch sort {
        case .title: return input.indices.sorted { titles[$0] < titles[$1] }.map { input[$0] }
        case .recent: return by({ self.lastPlayed($0) ?? .distantPast }, descending: true)
        case .playtime: return by({ self.playtime($0) }, descending: true)
        case .rating: return by({ self.user[$0.key]?.rating ?? 0 }, descending: true)
        case .status: return by({ self.statusOf($0).rank }, descending: false)
        case .platform: return by({ $0.primary.platform.name }, descending: false)
        case .added: return by({ self.user[$0.key]?.added ?? .distantPast }, descending: true)
        }
    }

    /// Games of the current view hidden by the filters / search (shown in a banner).
    /// Memoised: the banner asks on every redraw, and each pass used to filter the whole library twice.
    var hiddenByFilters: Int {
        guard filters.activeCount > 0 || !search.isEmpty else { return 0 }
        let key = "unfiltered|\(scope)|\(version)|\(UserDefaults.standard.bool(forKey: "playableOnlyInAll"))"
        let all: Int
        if let c = countCache[key] { all = c } else { all = filtered(Filters(), "").count; countCache[key] = all }
        return max(0, all - visibleGroups.count)
    }

    func count(_ s: Scope) -> Int {
        _ = version         // dependency for the caller, even on a cache hit
        let k = "\(s)"
        if let c = countCache[k] { return c }
        let v = countUncached(s)
        countCache[k] = v
        return v
    }

    private func countUncached(_ s: Scope) -> Int {
        if case .platform(let p) = s { return games.lazy.filter { $0.platform == p && (self.showHidden || !self.hidden.contains($0.id)) }.count }
        return groups.lazy.filter { $0.games.contains { self.matches($0, s) } }.count
    }

    func count(_ k: LaunchKind) -> Int { _ = version; return groups.lazy.filter { $0.games.contains { $0.launchKind == k } }.count }

    var platforms: [Platform] {
        let present = Set(games.map(\.platform))
        return Platform.allCases.filter(present.contains)
    }

    var selectedGroup: GameGroup? {
        guard let s = selected else { return nil }
        return groups.first { $0.id == s } ?? games.first { $0.id == s }.map { GameGroup(id: $0.id, games: [$0]) }
    }

    func isFavorite(_ grp: GameGroup) -> Bool { grp.games.contains { favorites.contains($0.id) } }
    func toggleFavorite(_ grp: GameGroup) {
        if isFavorite(grp) { favorites.subtract(grp.games.map(\.id)) } else { favorites.formUnion(grp.games.map(\.id)) }
    }
    func isHidden(_ grp: GameGroup) -> Bool { grp.games.allSatisfy { hidden.contains($0.id) } }
    func toggleHidden(_ grp: GameGroup) {
        if isHidden(grp) { hidden.subtract(grp.games.map(\.id)) } else { hidden.formUnion(grp.games.map(\.id)) }
    }

    // MARK: Presets

    private func applyPresetIfNeeded() {
        guard case .preset(let id) = scope, let p = presets.first(where: { $0.id == id }) else { return }
        filters = p.filters
        sort = p.sort
    }

    func savePreset(named name: String) {
        let p = Preset(name: name, scope: baseScope, filters: filters, sort: sort)
        presets.append(p)
        Store<[Preset]>.save("presets.json", presets)
        scope = .preset(p.id)
    }

    func deletePreset(_ id: String) {
        presets.removeAll { $0.id == id }
        Store<[Preset]>.save("presets.json", presets)
        if scope == .preset(id) { scope = .all }
    }

    func scopeTitle(_ s: Scope) -> String {
        switch s {
        case .all: String(localized: "Tous les jeux")
        case .playable: String(localized: "Jouables sur ce Mac")
        case .installed: String(localized: "Installés")
        case .installable: String(localized: "Installables localement")
        case .cloud: String(localized: "Cloud")
        case .favorites: String(localized: "Favoris")
        case .recent: String(localized: "Joués récemment")
        case .platform(let p): p.name
        case .preset(let id): presets.first { $0.id == id }?.name ?? String(localized: "Vue")
        case .performance: String(localized: "Performances")
        case .emulators: String(localized: "Émulateurs")
        case .home: String(localized: "Accueil")
        case .freeGames: String(localized: "Jeux gratuits")
        case .wishlist: String(localized: "Liste de souhaits")
        case .profile: String(localized: "Profil")
        case .options: String(localized: "Options")
        case .statistics: String(localized: "Statistiques")
        case .search: String(localized: "Recherche de prix")
        case .freeLoot: String(localized: "Objets gratuits")
        case .achievements: String(localized: "Succès")
        case .windows: String(localized: "Jeux Windows")
        case .refresh: String(localized: "Actualisations")
        }
    }

    private(set) var refreshingAll = false
    private(set) var lastFullRefresh: Date?

    /// "Actualiser": everything that goes stale — local scan, every connected platform,
    /// metadata, free games, wishlist prices and requirements of newly playable games.
    /// `manual` = the user pressed "Actualiser": results replace the library. Automatic refreshes
    /// (launch, periodic) merge: games missing from a pass (offline source, API error) are kept.
    func refreshAll(manual: Bool = false) async {
        guard !refreshingAll else { return }
        refreshingAll = true
        defer { refreshingAll = false }
        await RefreshCenter.shared.runAll(self)
    }

    func markFullRefresh() { lastFullRefresh = Date() }

    /// "Rechercher les jeux": rescan everything and force every connected API.
    func searchGames(replace: Bool = true) async {
        let connected = Integrations.all.filter(\.isConnected)
        if connected.isEmpty { await refresh(sync: false, replace: replace); flash(String(localized: "\(groups.count) jeux trouvés")) }
        else { await runSync(connected, replace: replace) }
    }

    // MARK: Random game

    /// Picks a random game in the current view, preferring playable ones.
    @discardableResult
    func pickRandom() -> GameGroup? {
        let list = visibleGroups
        let pool = list.filter { $0.primary.launchKind != .none }
        guard let g = (pool.isEmpty ? list : pool).randomElement() else { return nil }
        selected = g.id
        scrollTarget = g.id
        return g
    }

    // MARK: Scanning

    func refresh(sync: Bool = true, replace: Bool = false) async {
        guard !scanning else { return }
        scanning = true
        TaskCenter.shared.begin("scan", String(localized: "Analyse des bibliothèques"))

        var merged = await Task.detached(priority: .utility) { Self.scanAll() }.value
        merged = await GamesDB.shared.applyCached(merged)
        await publish(merged, replace: replace)

        // Resolve names / covers for ids we couldn't identify locally.
        let pending = merged.values.filter { !$0.hasTitle || $0.coverURL == nil }
        if !pending.isEmpty {
            TaskCenter.shared.begin("metadata", String(localized: "Titres et jaquettes"))
            let found = await GamesDB.shared.fetch(Array(pending)) { done, total in
                await MainActor.run { TaskCenter.shared.progress("metadata", done, total, "GOG GamesDB") }
            }
            TaskCenter.shared.end("metadata")
            if !found.isEmpty {
                for (id, e) in found { if var g = merged[id] { GamesDB.apply(e, to: &g); merged[id] = g } }
                await publish(merged, replace: replace)
            }
        }
        TaskCenter.shared.end("scan")
        scanning = false

        if sync, UserDefaults.standard.object(forKey: "autoSyncAPIs") as? Bool ?? true {
            let stale = Integrations.all.filter(Integrations.stale)
            if !stale.isEmpty { await runSync(stale) }
        }
    }

    /// Calls the platform APIs, then rescans to merge their games.
    func runSync(_ list: [Integration], replace: Bool = false) async {
        guard !list.isEmpty else { return }
        syncing.formUnion(list.map(\.platform))
        TaskCenter.shared.begin("sync", String(localized: "Synchronisation des plateformes"))
        TaskCenter.shared.detail("sync", list.map(\.platform.name).joined(separator: ", "))
        let messages = await withTaskGroup(of: String.self) { group in
            for i in list { group.addTask { await Integrations.run(i) } }
            var out = [String]()
            for await m in group { out.append(m) }
            return out
        }
        syncing.subtract(list.map(\.platform))
        TaskCenter.shared.end("sync")
        while scanning { try? await Task.sleep(for: .milliseconds(200)) }
        await refresh(sync: false, replace: replace)
        flash(messages.joined(separator: " · "))
    }

    func flash(_ s: String, seconds: Double = 5) {
        StatusCenter.shared.message = s
        Task { try? await Task.sleep(for: .seconds(seconds)); if StatusCenter.shared.message == s { StatusCenter.shared.message = nil } }
    }

    private func publish(_ dict: [String: Game], replace: Bool = false) async {
        // Filtering, merging and the "did anything change?" check run off the main thread.
        let current = games
        let next = await Task.detached(priority: .userInitiated) { () -> [Game]? in
            // Unidentifiable entries (no title anywhere) and DLCs are dropped; test servers, editors,
            // soundtracks and closed betas too unless the user wants them.
            let hideJunk = UserDefaults.standard.object(forKey: "hideNonGames") as? Bool ?? true
            let fresh = dict.values.filter { $0.hasTitle && !$0.isDLC && !(hideJunk && Self.isNonGame($0.title)) }
            var result = fresh
            if !replace && !current.isEmpty {
                // Incremental update: keep what this pass didn't see, unless it clearly disappeared from disk.
                let ids = Set(fresh.map(\.id))
                result += current.filter { g in
                    guard !ids.contains(g.id), g.manualId == nil, !(hideJunk && Self.isNonGame(g.title)) else { return false }
                    if let p = g.appPath, g.installed, !Paths.exists(p) { return false }
                    if g.launchURL?.hasPrefix("emu:") == true, !Paths.exists(g.externalId) { return false }
                    return true
                }
            }
            // Nothing changed → no republish (no redraw, no regroup).
            if result.count == current.count {
                let old = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                if result.allSatisfy({ old[$0.id] == $0 }) { return nil }
            }
            return result
        }.value
        guard let next else { return }
        games = next
        let snapshot = games
        Task.detached(priority: .utility) { [cacheURL] in
            if let d = try? JSONEncoder().encode(snapshot) { try? d.write(to: cacheURL, options: .atomic) }
        }
    }

    nonisolated static func isNonGame(_ title: String) -> Bool {
        title.range(of: "(test server|public test(ing)?|playtest|dedicated server|benchmark|\\bsdk\\b|soundtrack|\\bpts$|\\(beta\\)|\\bbeta$|pre-game editor|\\d{4} editor$|\\bdemo$)",
                    options: [.regularExpression, .caseInsensitive]) != nil
    }

    nonisolated static func scanAll() -> [String: Game] {
        // Independent sources in parallel.
        var steam: (games: [Game], info: [UInt32: SteamAppInfo]) = ([], [:])
        var parts = [[Game]](repeating: [], count: 8)
        var epicCatalog = [String: EpicScanner.CatalogEntry]()
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: 8) { i in
            switch i {
            case 0: let s = SteamScanner.scan(); lock.withLock { steam = s }
            case 1: let c = EpicScanner.catalog(); lock.withLock { epicCatalog = c }
            case 2: let g = EpicScanner.installed(); lock.withLock { parts[0] = g }
            case 3: let g = HeroicScanner.scan(); lock.withLock { parts[1] = g }
            case 4: let g = ItchScanner.scan(); lock.withLock { parts[2] = g }
            case 5: let g = ApiStore.loadAll(); lock.withLock { parts[5] = g }
            case 6: let g = Emulation.scan(); lock.withLock { parts[7] = g }
            default: let g = AppScanner.scan(); lock.withLock { parts[3] = g }
            }
        }
        parts[4] = GalaxyScanner.scan(steamInfo: steam.info) // needs Steam names
        parts[6] = ManualStore.load().map { $0.game() }

        // Steam API entries get local appinfo (Mac support, covers) too.
        parts[5] = parts[5].map { g in
            guard g.platform == .steam else { return g }
            var base = SteamScanner.make(id: g.externalId, info: steam.info)
            base.merge(g)
            return base
        }

        var dict = [String: Game]()
        for g in steam.games + parts.joined() {
            if dict[g.id] != nil { dict[g.id]!.merge(g) } else { dict[g.id] = g }
        }

        for (id, var g) in dict where g.platform == .epic {
            EpicScanner.enrich(&g, epicCatalog)
            dict[id] = g
        }

        // Drop native .app duplicates of games already known through a store.
        let storeInstalled = Set(dict.values.filter { $0.installed && ![.mac, .appstore, .custom].contains($0.platform) }.map(\.normalizedTitle))
        for (id, g) in dict where g.platform == .mac && storeInstalled.contains(g.normalizedTitle) { dict[id] = nil }
        return dict
    }

    // MARK: Actions

    func launch(_ g: Game) {
        defer {
            switch UserDefaults.standard.integer(forKey: "afterLaunch") {
            case 1: NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }.forEach { $0.miniaturize(nil) }
            case 2: NSApp.hide(nil)
            default: break
            }
        }
        let tracking = UserDefaults.standard.object(forKey: "trackPlaytime") as? Bool ?? true
        let key = tracking ? g.groupKey : "__untracked__"
        update(g.groupKey) { $0.lastLaunched = Date(); $0.launchCount = ($0.launchCount ?? 0) + 1 }
        guard let target = g.launchURL else { openStore(g); return }
        guard Self.launchAllowed(target, game: g) else { return }
        if target.hasPrefix("emu:") {
            if !Emulation.launch(target, onStart: { [weak self] pid in self?.sessions.track(key, pid: pid) }) {
                flash(String(localized: "Impossible de lancer l'émulateur — vérifie sa configuration dans Réglages → Émulateurs"))
            }
        } else if target.hasPrefix("/") {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: target), configuration: .init()) { [weak self] app, _ in
                guard let pid = app?.processIdentifier else { return }
                DispatchQueue.main.async { self?.sessions.track(key, pid: pid) }
            }
        } else if let u = URL(string: target) {
            if g.launchKind == .installed { sessions.expect(key) }
            NSWorkspace.shared.open(u)
        }
    }

    private static let knownSchemes: Set<String> = ["steam", "com.epicgames.launcher", "goggalaxy", "battlenet", "heroic", "itch",
                                                     "uplay", "origin2", "link2ea", "macappstore", "geforcenow", "https", "http"]

    /// Launch targets can come from imported / restored data: never run scripts or raw executables,
    /// and ask before opening an unusual URL scheme.
    static func launchAllowed(_ target: String, game g: Game,
                              trustedSchemes: Set<String>? = nil, rememberDecision: Bool = true,
                              requireURLScheme: Bool = false, allowEmulator: Bool = true) -> Bool {
        if requireURLScheme && URL(string: target)?.scheme == nil {
            let a = NSAlert(); a.messageText = String(localized: "Lien invalide")
            a.informativeText = String(localized: "Le lien de désinstallation de « \(g.title) » n'est pas valide.")
            a.runModal(); return false
        }
        if target.hasPrefix("emu:"), allowEmulator { return true }
        if target.hasPrefix("/") {
            guard target.hasSuffix(".app") || target.hasSuffix(".app/") else {
                let a = NSAlert(); a.messageText = String(localized: "Lancement bloqué")
                a.informativeText = String(localized: "« \(g.title) » pointe vers un fichier qui n'est pas une application (\(target)). Pour ta sécurité, seules les applications .app peuvent être lancées.")
                a.runModal(); return false
            }
            return true
        }
        guard let scheme = URL(string: target)?.scheme?.lowercased(), scheme != "file" else {
            let a = NSAlert(); a.messageText = String(localized: "Lien invalide"); a.informativeText = String(localized: "Le lien de lancement de « \(g.title) » n'est pas valide."); a.runModal()
            return false
        }
        if (trustedSchemes ?? knownSchemes).contains(scheme) { return true }
        let key = "allowedScheme.\(g.id).\(scheme)"
        if rememberDecision && UserDefaults.standard.bool(forKey: key) { return true }
        let a = NSAlert()
        a.messageText = String(localized: "Ouvrir avec « \(scheme) » ?")
        a.informativeText = String(localized: "« \(g.title) » va ouvrir le lien \(target). Continue seulement si tu l'as configuré toi-même.")
        a.addButton(withTitle: String(localized: "Ouvrir")); a.addButton(withTitle: String(localized: "Annuler"))
        guard a.runModal() == .alertFirstButtonReturn else { return false }
        if rememberDecision { UserDefaults.standard.set(true, forKey: key) }
        return true
    }

    func openStore(_ g: Game) {
        if let s = g.storeURL, let u = URL(string: s), ["https", "http", "steam", "macappstore"].contains(u.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(u) }
    }

    func reveal(_ g: Game) {
        if let p = g.appPath { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
        else if g.launchURL?.hasPrefix("emu:") == true { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: g.externalId)]) }
    }

    var geforceNowAvailable: Bool { Launchers.installed(Launchers.geforceNow) }

    func openInGeForceNow(_ g: Game) {
        // GFN has no public per-game deep link: open the app on its search.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(g.title, forType: .string)
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Launchers.geforceNow) {
            NSWorkspace.shared.openApplication(at: u, configuration: .init())
        }
        flash(String(localized: "« \(g.title) » copié — colle-le dans la recherche GeForce NOW"))
    }

    func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = String(localized: "Choisis les jeux à ajouter à la bibliothèque")
        guard panel.runModal() == .OK else { return }
        CustomApps.save(Array(Set(CustomApps.load() + panel.urls.map(\.path))))
        Task { await refresh(sync: false) }
    }

    func removeCustom(_ g: Game) {
        CustomApps.save(CustomApps.load().filter { $0 != g.appPath })
        games.removeAll { $0.id == g.id }
    }

    // MARK: Manual games

    func newManual(platform: Platform? = nil) {
        var m = ManualGame()
        if let platform { m.platform = platform } else if case .platform(let p) = scope { m.platform = p }
        editing = m
    }

    func edit(_ g: Game) {
        if let id = g.manualId { editing = ManualStore.get(id) }
    }

    /// Prefills a manual entry from an existing game (to add another copy / fix it).
    func duplicateAsManual(_ g: Game) {
        var m = ManualGame()
        m.title = g.title
        m.coverURL = g.coverURL ?? ""
        m.storeURL = g.storeURL ?? ""
        editing = m
    }

    func saveManual(_ m: ManualGame) {
        ManualStore.upsert(m)
        editing = nil
        Task { await refresh(sync: false) }
    }

    func deleteManual(_ id: String) {
        ManualStore.delete(id)
        editing = nil
        games.removeAll { $0.manualId == id }
    }

    // MARK: Export / backup

    func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Ludothèque.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        func esc(_ s: String) -> String { CSV.escape(s) }
        let df = ISO8601DateFormatter()
        var lines = ["Titre;Plateformes;Disponibilité;Statut;Note;Temps de jeu (min);Dernière partie;Tags"]
        for g in groups.sorted(by: { title($0) < title($1) }) {
            let u = entry(g.key)
            lines.append([esc(title(g)), esc(g.platforms.map(\.name).joined(separator: ", ")), esc(g.primary.launchKind.label),
                          esc(statusOf(g).label), "\(u.rating ?? 0)", "\(playtime(g))",
                          lastPlayed(g).map(df.string) ?? "", esc((u.tags ?? []).joined(separator: ", "))].joined(separator: ";"))
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        flash(String(localized: "Bibliothèque exportée"))
    }

    /// Backup of everything the user typed (no credentials: they stay in the Keychain).
    func backup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Ludothèque-sauvegarde.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Store<[String: UserEntry]>.save("user-data.json", user)
        var dump = [String: Any]()
        for f in ["user-data.json", "manual-games.json", "presets.json", "emulators.json", "custom-apps.json", "profile.json", "sessions.json", "wishlist.json", "dlcompare-tracked.json", "achievements.json"] {
            if let d = try? Data(contentsOf: Paths.support.appendingPathComponent(f)), let o = try? JSONSerialization.jsonObject(with: d) { dump[f] = o }
        }
        dump["favorites"] = Array(favorites)
        dump["hidden"] = Array(hidden)
        if let d = try? JSONSerialization.data(withJSONObject: dump, options: [.prettyPrinted]) { try? d.write(to: url) }
        flash(String(localized: "Sauvegarde enregistrée"))
    }

    func restore() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url, let d = try? Data(contentsOf: url),
              let dump = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        for f in ["user-data.json", "manual-games.json", "presets.json", "emulators.json", "custom-apps.json", "profile.json", "sessions.json", "wishlist.json", "dlcompare-tracked.json", "achievements.json"] {
            if let o = dump[f], let data = try? JSONSerialization.data(withJSONObject: o) { try? data.write(to: Paths.support.appendingPathComponent(f)) }
        }
        if let f = dump["favorites"] as? [String] { favorites = Set(f) }
        if let h = dump["hidden"] as? [String] { hidden = Set(h) }
        user = Store<[String: UserEntry]>.load("user-data.json", [:])
        presets = Store<[Preset]>.load("presets.json", [])
        // In-memory stores would otherwise overwrite the restored files on their next save.
        ProfileStore.shared.reload()
        SessionLog.shared.reload()
        WishlistStore.shared.reload()
        DLCompareStore.shared.reload()
        Task { await refresh(sync: false) }
        flash(String(localized: "Sauvegarde restaurée"))
    }
}

extension Completion {
    var rank: Int { Self.allCases.firstIndex(of: self)! }
}



@MainActor
final class StatusCenter: ObservableObject {
    static let shared = StatusCenter()
    @Published var message: String?
}
