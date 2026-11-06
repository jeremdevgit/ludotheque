// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI
import Combine

struct ContentView: View {
    @Environment(Library.self) var lib
    @AppStorage("onboardingDone") private var onboardingDone = false

    var body: some View {
        NavigationSplitView {
            Sidebar().navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            DetailRoot()
        }
        .sheet(item: Bindable(lib).uninstalling) { g in UninstallSheet(game: g).environment(lib) }
        .sheet(isPresented: Binding(get: { !onboardingDone }, set: { if !$0 && !onboardingDone { onboardingDone = true } })) {
            OnboardingView(close: { onboardingDone = true }).environment(lib)
        }
        .sheet(item: Bindable(lib).editing) { m in
            ManualGameSheet(game: m, isNew: ManualStore.get(m.id) == nil).environment(lib)
        }
    }
}

/// Detail column chrome: toolbar, search field, inspector, progress bar, status toast.
/// Its body reads two booleans only: switching pages or selecting a game never rebuilds the
/// NSToolbar (that rebuild used to be most of the cost of a page switch).
struct DetailRoot: View {
    @Environment(Library.self) var lib
    @Environment(\.openWindow) private var openWindow
    @AppStorage(UIKeys.hiddenToolbar) private var hiddenToolbar = ""

    var body: some View {
        let isLibrary = lib.libraryScope
        let inspector = lib.inspectorShown
        DetailPage()
            .onAppear { DispatchQueue.main.async { PerfMonitor.shared.markLaunched() } }   // after the first frame
            .searchable(text: Bindable(lib).searchInput, placement: .toolbar, prompt: "Rechercher un jeu")
            .inspector(isPresented: Binding(get: { inspector }, set: { if !$0 && lib.selected != nil { lib.selected = nil } })) {
                InspectorContent().inspectorColumnWidth(min: 320, ideal: 360, max: 480)
            }
            // Fixed-height progress bar, always on top: it never shifts the content.
            .safeAreaInset(edge: .top, spacing: 0) { TopProgressBar() }
            .toolbar { toolbar(isLibrary) }
            .overlay(alignment: .bottomTrailing) { StatusToast() }
    }

    private func show(_ t: ToolbarItemKind) -> Bool { !IdSet(raw: hiddenToolbar).contains(t.rawValue) }

    /// One item per control, each a small view with its own dependencies (a filter change redraws
    /// the filter menu only). Items are never inserted / removed on navigation: the filter menu is
    /// just disabled outside the game lists.
    @ToolbarContentBuilder private func toolbar(_ isLibrary: Bool) -> some ToolbarContent {
        if show(.filters) { ToolbarItem { FilterMenu().disabled(!isLibrary) } }
        if show(.view) { ToolbarItem { DisplayMenu() } }
        if show(.random) {
            ToolbarItem {
                Button { if lib.pickRandom() == nil { lib.flash(String(localized: "Aucun jeu dans cette vue")) } } label: {
                    Label("Jeu au hasard", systemImage: "dice")
                }.help("Choisir un jeu au hasard dans la vue actuelle")
            }
        }
        if show(.add) {
            ToolbarItem {
                Menu {
                    Button("Saisir un jeu manuellement…") { lib.newManual() }
                    Button("Ajouter une application Mac…") { lib.addApps() }
                } label: { Label("Ajouter", systemImage: "plus") }
            }
        }
        if show(.platforms) {
            ToolbarItem {
                Button { openWindow(id: "platforms") } label: { Label("Plateformes", systemImage: "person.crop.circle.badge.checkmark") }
                    .help("Gestion des plateformes : connecter ses comptes et synchroniser")
            }
        }
        if show(.more) {
            ToolbarItem {
                Menu {
                    Button("Mode TV (manette)") { openWindow(id: "tv") }
                    Button("Statistiques") { openWindow(id: "stats") }
                    Divider()
                    SettingsLink { Text("Émulateurs et réglages…") }
                } label: { Label("Plus", systemImage: "ellipsis.circle") }
            }
        }
        if show(.refresh) { ToolbarItem { RefreshButton() } }
    }
}

/// The page of the current scope (only this part is rebuilt when navigating).
struct DetailPage: View {
    @Environment(Library.self) var lib
    @AppStorage(UIKeys.background) private var background = "none"

    var body: some View {
        let scope = lib.scope
        GeometryReader { geo in
            Group {
                switch scope {
                case .home: HomeView()
                case .profile: ProfileView()
                case .options: OptionsView()
                case .statistics: StatsView()
                case .search: SearchView()
                case .freeLoot: FreeLootView()
                case .achievements: AchievementsView()
                case .windows: WindowsGamesView()
                case .refresh: RefreshView()
                case .freeGames: FreeGamesView()
                case .wishlist: WishlistView()
                case .performance: PerformanceView()
                case .emulators: EmulatorHubView()
                default: LibraryPage()
                }
            }
            .environment(\.stableWidth, geo.size.width)
        }
        .background {
            switch background {
            case "accent": Color.accentColor.opacity(0.08).ignoresSafeArea()
            case "gradient": LinearGradient(colors: [Color.accentColor.opacity(0.18), .clear, Color.accentColor.opacity(0.06)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            default: Color.clear
            }
        }
        .navigationTitle(lib.scopeTitle(scope))
        .navigationSubtitle(scope.isLibrary ? "\(lib.visibleGroups.count) jeux" : "")
    }
}

/// Grid or list of the games of a library scope.
struct LibraryPage: View {
    @Environment(Library.self) var lib
    @AppStorage("tileWidth") private var tileWidth = 150.0
    @AppStorage("viewMode") private var viewMode = "grid"
    @AppStorage("groupBy") private var groupBy = GroupBy.none.rawValue
    @AppStorage(UIKeys.gridEngine) private var gridEngine = UIKeys.defaultGridEngine

    var body: some View {
        let groups = lib.visibleGroups
        if groups.isEmpty && lib.hiddenByFilters > 0 {
            VStack { FilterBanner(); Spacer() }
        } else if groups.isEmpty {
            ContentUnavailableView(lib.scanning ? "Analyse en cours…" : "Aucun jeu", systemImage: "gamecontroller",
                                   description: Text(lib.scanning ? "" : "Essaie un autre filtre ou une autre recherche."))
        } else if viewMode == "list" {
            VStack(spacing: 0) { FilterBanner(); GameList(groups: groups) }
        } else {
            VStack(spacing: 0) {
                FilterBanner()
                if gridEngine == "native" { NativeGrid(sections: sections(groups), tileWidth: tileWidth) }
                else { GameGrid(sections: sections(groups), tileWidth: tileWidth) }
            }
        }
    }

    private func sections(_ groups: [GameGroup]) -> [(String, [GameGroup])] {
        let by = GroupBy(rawValue: groupBy) ?? .none
        guard by != .none else { return [("", groups)] }
        let keyed: [(String, Int, GameGroup)] = groups.map { g in
            switch by {
            case .availability: (g.primary.launchKind.label, g.primary.launchKind.rank, g)
            case .status: (lib.statusOf(g).label, lib.statusOf(g).rank, g)
            case .platform: (g.primary.platform.name, Platform.allCases.firstIndex(of: g.primary.platform)!, g)
            case .letter:
                { let c = lib.title(g).folding(options: .diacriticInsensitive, locale: nil).uppercased().first ?? "#"
                  let s = c.isLetter ? String(c) : "#"; return (s, s == "#" ? 0 : Int(c.unicodeScalars.first!.value), g) }()
            case .none: ("", 0, g)
            }
        }
        let dict = Dictionary(grouping: keyed, by: { $0.0 })
        return dict.map { ($0.key, $0.value.first!.1, $0.value.map(\.2)) }
            .sorted { $0.1 < $1.1 }.map { ($0.0, $0.2) }
    }
}

/// Native (AppKit) grid fed with the selection explicitly: it follows clicks made elsewhere
/// (random game, context menu, closing the details panel).
struct NativeGrid: View {
    @Environment(Library.self) var lib
    let sections: [(String, [GameGroup])]
    let tileWidth: Double

    var body: some View {
        GameCollectionView(sections: sections, tileWidth: tileWidth, selected: lib.selected,
                           scrollTarget: lib.scrollTarget, dataVersion: lib.version)
    }
}

struct InspectorContent: View {
    @Environment(Library.self) var lib
    var body: some View {
        if let g = lib.selectedGroup { GameDetailView(group: g) }
        else { Text("Sélectionne un jeu").foregroundStyle(.secondary) }
    }
}

/// "N jeux masqués par les filtres" banner.
struct FilterBanner: View {
    @Environment(Library.self) var lib
    var body: some View {
        let hidden = lib.hiddenByFilters
        if hidden > 0 {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill").foregroundStyle(Color.accentColor)
                Text(lib.filters.activeCount > 0 ? (hidden > 1 ? String(localized: "\(hidden) jeux masqués par les filtres") : String(localized: "1 jeu masqué par les filtres")) : (hidden > 1 ? String(localized: "\(hidden) jeux masqués par la recherche") : String(localized: "1 jeu masqué par la recherche")))
                Spacer()
                Button("Réinitialiser") { lib.filters = Filters(); lib.search = "" }.controlSize(.small)
            }
            .font(.callout)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.1))
        }
    }
}

/// Short confirmations (progress lives in the top bar). Only this view observes the messages.
struct StatusToast: View {
    @ObservedObject private var status = StatusCenter.shared
    var body: some View {
        Group {
            if let s = status.message {
                Text(s).font(.callout).lineLimit(2)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                    .padding(16)
                    .frame(maxWidth: 420, alignment: .trailing)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.2), value: status.message)
    }
}

/// "Affichage" menu: grid / list, sort, sections, tile size.
struct DisplayMenu: View {
    @Environment(Library.self) var lib
    @AppStorage("tileWidth") private var tileWidth = 150.0
    @AppStorage("viewMode") private var viewMode = "grid"
    @AppStorage("groupBy") private var groupBy = GroupBy.none.rawValue

    var body: some View {
        Menu {
            Picker("Affichage", selection: $viewMode) {
                Label("Grille", systemImage: "square.grid.2x2").tag("grid")
                Label("Liste", systemImage: "list.bullet").tag("list")
            }.pickerStyle(.inline)
            Picker("Trier par", selection: Bindable(lib).sort) {
                ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Sections", selection: $groupBy) {
                ForEach(GroupBy.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            if viewMode == "grid" {
                Divider()
                Button("Jaquettes plus grandes") { tileWidth = min(240, tileWidth + 20) }.keyboardShortcut("+")
                Button("Jaquettes plus petites") { tileWidth = max(110, tileWidth - 20) }.keyboardShortcut("-")
            }
        } label: { Label("Affichage", systemImage: viewMode == "list" ? "list.bullet" : "square.grid.2x2") }
    }
}

struct RefreshButton: View {
    @Environment(Library.self) var lib
    var body: some View {
        Button { Task { await lib.refreshAll(manual: true) } } label: {
            Label("Actualiser", systemImage: "arrow.clockwise")
        }
        .help("Tout actualiser : jeux, plateformes connectées, jaquettes, jeux gratuits, prix, performances (⌘R)")
        .disabled(lib.refreshingAll)
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Environment(Library.self) var lib
    @ObservedObject private var profile = ProfileStore.shared
    @ObservedObject private var badges = SidebarBadges.shared
    @AppStorage("showAllPlatforms") private var showAll = false
    @AppStorage("hiddenSidebarPlatforms") private var hiddenPlatforms = ""
    @AppStorage(UIKeys.hiddenSidebar) private var hiddenSidebar = ""
    @AppStorage(UIKeys.sectionOrder) private var sectionOrder = ""
    @AppStorage(UIKeys.hiddenSections) private var hiddenSections = ""
    @AppStorage(UIKeys.sidebarSize) private var sidebarSize = "medium"
    @AppStorage(UIKeys.showBadges) private var showBadges = true
    /// Always listed, even before any game is found.
    static let pinned: [Platform] = [.steam, .epic, .gog, .xbox, .psn, .nintendo, .itch, .battlenet, .ea, .ubisoft, .riot, .amazon, .humble, .appstore, .googleplay]

    var body: some View {
        let order = orderedIds(sectionOrder, all: SidebarSection.allCases.map(\.rawValue)).compactMap(SidebarSection.init(rawValue:))
        let hiddenSecs = IdSet(raw: hiddenSections)
        // Write only real changes: re-assigning the same value republishes the whole Library and the
        // list re-applies its selection → endless redraw loop. A nil selection (scope without a row,
        // e.g. Options) is ignored.
        List(selection: Binding(get: { lib.scope }, set: { if let v = $0, v != lib.scope { lib.scope = v } })) {
            ForEach(order.filter { !hiddenSecs.contains($0.rawValue) }) { sec in section(sec) }
        }
        .listStyle(.sidebar)
        .environment(\.sidebarRowSize, SidebarRowSize(sidebarSize))
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Button { lib.scope = .options } label: { Label("Options", systemImage: "gearshape.fill") }
                    .buttonStyle(.plain).font(.callout).foregroundStyle(lib.scope == .options ? Color.accentColor : .primary).padding(.bottom, 4)
                Toggle("Toutes les plateformes", isOn: $showAll)
                Toggle("Afficher les jeux masqués", isOn: Bindable(lib).showHidden)
            }
            .toggleStyle(.checkbox).font(.caption).padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func items(_ sec: SidebarSection) -> [SidebarItem] {
        let hidden = IdSet(raw: hiddenSidebar)
        return SidebarItem.allCases.filter { $0.section == sec && !hidden.contains($0.rawValue) }
    }

    @ViewBuilder private func section(_ sec: SidebarSection) -> some View {
        switch sec {
        case .top:
            ForEach(items(sec)) { itemRow($0) }
        case .library, .stores, .availability:
            let list = items(sec)
            if !list.isEmpty { Section(sec.title) { ForEach(list) { itemRow($0) } } }
        case .presets:
            Section(sec.title) {
                ForEach(lib.presets) { p in
                    Label(p.name, systemImage: "line.3.horizontal.decrease.circle")
                        .tag(Scope.preset(p.id))
                        .contextMenu { Button("Supprimer la vue", role: .destructive) { lib.deletePreset(p.id) } }
                }
                Button { askPresetName() } label: { Label("Enregistrer la vue actuelle…", systemImage: "plus") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        case .platforms:
            Section(sec.title) {
                ForEach(platformList) { p in
                    Label { Text(p.name) } icon: { PlatformLogo(platform: p, size: 16) }
                        .badge(showBadges ? lib.count(.platform(p)) : 0)
                        .tag(Scope.platform(p))
                        .contextMenu {
                            Button("Masquer de la barre latérale") { SidebarPrefs.setHidden(p, true) }
                        }
                }
            }
        }
    }

    private func itemRow(_ i: SidebarItem) -> some View {
        let name = i == .profile && !profile.profile.displayName.isEmpty ? profile.profile.displayName : i.title
        return Label { Text(name) } icon: { Image(systemName: i.symbol).foregroundStyle(i.tint) }
            .badge(showBadges && i.counted ? badge(i) : 0)
            .tag(i.scope)
            .contextMenu {
                Button("Masquer de la barre latérale") { var x = IdSet(raw: hiddenSidebar); x.set(i.rawValue, hidden: true); hiddenSidebar = x.raw }
            }
    }

    private func badge(_ i: SidebarItem) -> Int {
        switch i {
        case .freeGames: badges.freeGames
        case .freeLoot: badges.freeLoot
        case .wishlist: badges.deals
        default: lib.count(i.scope)
        }
    }

    private var platformList: [Platform] {
        let hidden = SidebarPrefs.hidden(hiddenPlatforms)
        if showAll { return Platform.allCases.filter { $0 != .other && !hidden.contains($0) } }
        let present = Set(lib.platforms).union(Self.pinned)
        return Platform.allCases.filter { present.contains($0) && !hidden.contains($0) }
    }

    private func askPresetName() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Enregistrer la vue actuelle")
        alert.informativeText = String(localized: "La vue, les filtres et le tri actuels seront enregistrés.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = String(localized: "Nom de la vue (ex. Coop sur Mac)")
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Enregistrer"))
        alert.addButton(withTitle: String(localized: "Annuler"))
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty { lib.savePreset(named: field.stringValue) }
    }
}

// MARK: - Filters

struct FilterMenu: View {
    @Environment(Library.self) var lib

    var body: some View {
        Menu {
            Section("Boutiques") {
                Label { Text("Jeux gratuits") } icon: { Image(systemName: "gift.fill").foregroundStyle(.green) }
                    .badge(SidebarBadges.shared.freeGames)
                    .tag(Scope.freeGames)
                Label { Text("Liste de souhaits") } icon: { Image(systemName: "heart.fill").foregroundStyle(.pink) }
                    .badge(SidebarBadges.shared.deals)
                    .tag(Scope.wishlist)
            }
            Section("Disponibilité") {
                ForEach(LaunchKind.allCases, id: \.self) { k in
                    Toggle(isOn: setBinding(\.kinds, k)) { Label("\(k.label) (\(lib.count(k)))", systemImage: k.symbol) }
                }
            }
            Menu("Statut") {
                ForEach(Completion.allCases) { c in Toggle(isOn: setBinding(\.statuses, c)) { Label(c.label, systemImage: c.symbol) } }
            }
            Menu(lib.filters.platforms.isEmpty ? "Plateformes" : "Plateformes (\(lib.filters.platforms.count))") {
                ForEach(lib.platforms) { p in Toggle(p.name, isOn: setBinding(\.platforms, p)) }
                Divider()
                Button("Toutes") { lib.filters.platforms = [] }
            }
            if !lib.allTags.isEmpty {
                Menu("Tags") { ForEach(lib.allTags, id: \.self) { t in Toggle(t, isOn: setBinding(\.tags, t)) } }
            }
            Picker("Note minimale", selection: Bindable(lib).filters.minRating) {
                Text("Toutes").tag(0)
                ForEach(1...5, id: \.self) { n in Text(String(repeating: "★", count: n)).tag(n) }
            }
            Section("Autres") {
                Toggle("Compatibles Mac uniquement", isOn: Bindable(lib).filters.macOnly)
                Toggle("Favoris uniquement", isOn: Bindable(lib).filters.favoritesOnly)
                Toggle("Déjà joués", isOn: Bindable(lib).filters.playedOnly)
            }
            if lib.filters.activeCount > 0 {
                Divider()
                Button("Réinitialiser les filtres") { lib.filters = Filters() }
            }
        } label: {
            Label(lib.filters.activeCount > 0 ? "Filtres (\(lib.filters.activeCount))" : "Filtres",
                  systemImage: lib.filters.activeCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .help("Filtrer : installé, installable localement, cloud, statut, plateformes, tags…")
    }

    private func setBinding<T: Hashable>(_ path: WritableKeyPath<Filters, Set<T>>, _ v: T) -> Binding<Bool> {
        Binding(get: { lib.filters[keyPath: path].contains(v) },
                set: { if $0 { lib.filters[keyPath: path].insert(v) } else { lib.filters[keyPath: path].remove(v) } })
    }
}

// MARK: - Grid

/// Library grid (SwiftUI). The AppKit grid (GameCollectionView) is available in Options → Interface.
struct GameGrid: View {
    @Environment(Library.self) var lib
    @Environment(\.stableWidth) private var width
    let sections: [(String, [GameGroup])]
    let tileWidth: Double

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: stableColumns(width, min: tileWidth, spacing: 18, padding: 40, max: tileWidth * 1.25),
                          spacing: 22, pinnedViews: sections.count > 1 ? [.sectionHeaders] : []) {
                    ForEach(sections, id: \.0) { name, groups in
                        Section {
                            ForEach(groups) { GroupTile(group: $0).id($0.id) }
                        } header: {
                            if !name.isEmpty {
                                HStack {
                                    Text(name).font(.title3.bold())
                                    Text("\(groups.count)").foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.vertical, 6).padding(.horizontal, 4)
                                .background(.bar)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .onChange(of: lib.scrollTarget) { _, id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }
}

@MainActor
final class HoverModel: ObservableObject {
    @Published var on = false
}

struct GroupTile: View {
    @Environment(Library.self) var lib
    let group: GameGroup
    @ObservedObject private var styleStore = TileStyleStore.shared
    @StateObject private var hoverModel = HoverModel()
    private var hover: Bool { hoverModel.on }

    var body: some View {
        let st = styleStore.style
        let (showTitle, showLogos, showSubtitle, showStatus, showBadge) = (st.title, st.logos, st.subtitle, st.status, st.badge)
        let (hoverEffect, dim, radius, aspect, titleFont) = (st.hover, st.dim, st.radius, st.aspect, st.font)
        let game = group.primary
        let kind = game.launchKind
        let selected = lib.selectionFlag(group.id).on     // own flag: a click redraws 2 tiles, not all
        let status = lib.statusOf(group)
        VStack(alignment: .leading, spacing: 5) {
            CoverImage(game: lib.coverGame(group), poster: aspect != "16:9")
                .aspectRatio(tileAspectRatio(aspect), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(alignment: .topTrailing) { if showBadge { badge(kind) } }
                .overlay(alignment: .topLeading) {
                    if showStatus && status != .none {
                        Image(systemName: status.symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 18, height: 18).background(status.color, in: Circle()).padding(6).shadow(radius: 2)
                    }
                }
                .overlay {
                    if hoverEffect && hover && kind != .none {
                        ZStack {
                            Color.black.opacity(0.35)
                            Image(systemName: icon(kind)).font(.system(size: 38)).foregroundStyle(.white).shadow(radius: 4)
                        }.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    }
                }
                .opacity(dim && kind == .none ? 0.55 : 1)
                // Cover + badges flattened into one GPU layer: much cheaper to move while scrolling.
                .drawingGroup()
                .overlay {
                    if selected { RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Color.accentColor, lineWidth: 3) }
                }
            if showTitle {
                HStack(spacing: 4) {
                    if lib.isFavorite(group) { Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption2) }
                    Text(lib.title(group)).font(titleFont == "small" ? .caption.weight(.medium) : titleFont == "large" ? .body.weight(.semibold) : .callout.weight(.medium))
                        .lineLimit(1).truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showLogos || showSubtitle {
                // One logo per platform owning the game; dimmed when not playable there.
                HStack(spacing: 5) {
                    if showLogos {
                        ForEach(group.bestPerPlatform.prefix(4)) { g in
                            PlatformLogo(platform: g.platform, size: 16)
                                .opacity(g.launchKind == .none ? 0.4 : 1)
                        }
                    }
                    if showSubtitle {
                        Text(subtitle(kind)).lineLimit(1).truncationMode(.tail).font(.caption).foregroundStyle(.secondary)
                            .layoutPriority(-1)   // shrinks before the logos: the row never exceeds the tile
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        // Hover just toggles an overlay (no animation, scale or shadow): tiles sliding under the
        // cursor while scrolling must cost nothing.
        .onHover { h in if hoverEffect, hoverModel.on != h { hoverModel.on = h } }
        // Single click selects immediately; double click also launches.
        .onTapGesture(count: 2) { if kind != .none { lib.launch(game) } else { lib.openStore(game) } }
        .simultaneousGesture(TapGesture().onEnded { if lib.selected != group.id { lib.selected = group.id } })
        // No per-tile tooltip: each one adds mouse tracking that is updated on every scroll step.
        .contextMenu { GroupMenu(group: group) }
    }

    @ViewBuilder private func badge(_ k: LaunchKind) -> some View {
        switch k {
        case .installed: dot("checkmark", .green)
        case .installable: dot("arrow.down", .orange)
        case .cloud: dot("cloud.fill", .blue)
        case .none: EmptyView()
        }
    }

    private func dot(_ s: String, _ c: Color) -> some View {
        Image(systemName: s).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            .frame(width: 18, height: 18).background(c, in: Circle()).padding(6).shadow(radius: 2)
    }

    private func icon(_ k: LaunchKind) -> String {
        switch k { case .installed: "play.fill"; case .installable: "arrow.down.circle.fill"; case .cloud: "cloud.fill"; case .none: "" }
    }

    private func subtitle(_ k: LaunchKind) -> String {
        var parts = [String]()
        switch k {
        case .installed: parts.append(String(localized: "Installé"))
        case .installable: parts.append(String(localized: "À installer"))
        case .cloud: parts.append(String(localized: "Cloud"))
        case .none: if group.games.count == 1 && group.primary.macNative == false { parts.append(String(localized: "Pas sur Mac")) }
        }
        let m = lib.playtime(group)
        if m > 0 { parts.append(m >= 60 ? "\(m / 60) h" : "\(m) min") }
        return parts.joined(separator: " · ")
    }

}

/// Context menu shared by the grid, the list and the details panel.
struct GroupMenu: View {
    @Environment(Library.self) var lib
    let group: GameGroup

    var body: some View {
        if group.games.count == 1 {
            GameActions(game: group.primary)
        } else {
            ForEach(group.games) { g in
                Menu("\(g.platform.name) — \(g.launchKind.label)") { GameActions(game: g) }
            }
        }
        Divider()
        Button("Afficher les détails") { lib.selected = group.id }
        Menu("Statut") {
            ForEach(Completion.allCases) { c in
                Button { lib.update(group.key) { $0.status = c } } label: { Label(c.label, systemImage: c.symbol) }
            }
        }
        Button(lib.isFavorite(group) ? "Retirer des favoris" : "Ajouter aux favoris") { lib.toggleFavorite(group) }
        Button(lib.isHidden(group) ? "Ne plus masquer" : "Masquer") { lib.toggleHidden(group) }
        Button(ProfileStore.shared.profile.showcase.contains(group.key) ? "Retirer de la vitrine du profil" : "Ajouter à la vitrine du profil") {
            ProfileStore.shared.toggleShowcase(group.key)
        }
        Button("Ajouter une autre version manuellement…") { lib.duplicateAsManual(group.primary) }
    }
}

/// Actions for one platform version of a game.
struct GameActions: View {
    @Environment(Library.self) var lib
    let game: Game

    var body: some View {
        switch game.launchKind {
        case .installed: Button("Jouer") { lib.launch(game) }
        case .installable: Button("Installer via \(game.platform.name)") { lib.launch(game) }
        case .cloud: Button("Jouer en streaming") { lib.launch(game) }
        case .none: EmptyView()
        }
        if lib.geforceNowAvailable && game.launchKind != .installed {
            Button("Chercher dans GeForce NOW") { lib.openInGeForceNow(game) }
        }
        if game.storeURL != nil { Button("Page du jeu") { lib.openStore(game) } }
        if game.appPath != nil || game.launchURL?.hasPrefix("emu:") == true { Button("Afficher dans le Finder") { lib.reveal(game) } }
        if game.manualId != nil { Button("Modifier…") { lib.edit(game) } }
        if game.launchKind == .installed { Button("Désinstaller…") { lib.uninstalling = game } }
        if game.platform == .custom && game.manualId == nil && game.appPath != nil {
            Button("Retirer de la bibliothèque", role: .destructive) { lib.removeCustom(game) }
        }
    }
}

// MARK: - List view

struct GameList: View {
    @Environment(Library.self) var lib
    let groups: [GameGroup]
    /// Logos arrive from the network: the visible rows are refreshed when one lands.
    @ObservedObject private var logos = LogoCache.shared

    var body: some View {
        // Reading `version` re-evaluates this view (and refreshes the visible rows) when statuses,
        // favourites or titles change.
        let _ = lib.version
        NativeGameTable(lib: lib, groups: groups, columns: Self.columns(lib), autosaveName: "libraryList",
                        onOpen: { g in Library.shared.launch(g.primary) })
    }

    private static func columns(_ lib: Library) -> [GameTableColumn] {
        [
            GameTableColumn(id: "title", title: String(localized: "Titre"), width: 320, minWidth: 220) { g in
                GameCell(text: lib.title(g), star: lib.isFavorite(g), cover: lib.coverGame(g))
            },
            GameTableColumn(id: "platforms", title: String(localized: "Plateformes"), width: 110, minWidth: 80) { g in
                GameCell(logos: g.bestPerPlatform.prefix(4).map { ($0.platform, $0.launchKind == .none) })
            },
            GameTableColumn(id: "availability", title: String(localized: "Disponibilité"), width: 150, minWidth: 100) { g in
                GameCell(text: g.primary.launchKind.label, symbol: g.primary.launchKind.symbol)
            },
            GameTableColumn(id: "status", title: String(localized: "Statut"), width: 130, minWidth: 90) { g in
                let s = lib.statusOf(g)
                return GameCell(text: s.label, color: NSColor(s.color), symbol: s.symbol)
            },
            GameTableColumn(id: "rating", title: String(localized: "Note"), width: 60, minWidth: 50, maxWidth: 90) { g in
                GameCell(text: String(repeating: "★", count: lib.entry(g.key).rating ?? 0), color: .systemYellow)
            },
            GameTableColumn(id: "playtime", title: String(localized: "Temps de jeu"), width: 100, minWidth: 80) { g in
                let m = lib.playtime(g)
                return GameCell(text: m == 0 ? "—" : (m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"), monospaced: true)
            },
            GameTableColumn(id: "last", title: String(localized: "Dernière partie"), width: 110, minWidth: 90) { g in
                GameCell(text: lib.lastPlayed(g)?.formatted(date: .abbreviated, time: .omitted) ?? "—")
            },
        ]
    }
}

/// Which platforms appear in the sidebar (Options → Barre latérale).
enum SidebarPrefs {
    static let key = "hiddenSidebarPlatforms"
    static func hidden(_ raw: String) -> Set<Platform> { Set(raw.split(separator: ",").compactMap { Platform(rawValue: String($0)) }) }
    static func setHidden(_ p: Platform, _ hide: Bool) {
        var set = hidden(UserDefaults.standard.string(forKey: key) ?? "")
        if hide { set.insert(p) } else { set.remove(p) }
        UserDefaults.standard.set(set.map(\.rawValue).sorted().joined(separator: ","), forKey: key)
    }
}

/// Tile appearance, read once from UserDefaults for every tile (instead of 10 observers per tile).
struct TileStyle: Equatable {
    var title = true, logos = true, subtitle = true, status = true, badge = true, hover = true, dim = true
    var radius = 10.0
    var aspect = "2:3"
    var font = "normal"

    static func read() -> TileStyle {
        let d = UserDefaults.standard
        func b(_ k: String) -> Bool { d.object(forKey: k) as? Bool ?? true }
        return TileStyle(title: b(UIKeys.tileTitle), logos: b(UIKeys.tileLogos), subtitle: b(UIKeys.tileSubtitle), status: b(UIKeys.tileStatus),
                         badge: b(UIKeys.tileBadge), hover: b(UIKeys.tileHover), dim: b(UIKeys.tileDim),
                         radius: d.object(forKey: UIKeys.tileRadius) as? Double ?? 10,
                         aspect: d.string(forKey: UIKeys.tileAspect) ?? "2:3", font: d.string(forKey: UIKeys.tileFont) ?? "normal")
    }
}

@MainActor
final class TileStyleStore: ObservableObject {
    static let shared = TileStyleStore()
    @Published private(set) var style = TileStyle.read()
    private init() {
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let s = TileStyle.read()
                // Publish only real changes: other settings writes must not redraw every tile.
                if s != TileStyleStore.shared.style { TileStyleStore.shared.style = s }
            }
        }
    }
}

/// Sidebar counters for the stores. The sidebar is expensive to redraw: it must not observe stores
/// that publish at every price / item update during a refresh, only these three numbers.
@MainActor
final class SidebarBadges: ObservableObject {
    static let shared = SidebarBadges()
    @Published private(set) var freeGames = 0
    @Published private(set) var freeLoot = 0
    @Published private(set) var deals = 0
    private var subs: [Any] = []

    private init() {
        recompute()
        for p in [FreeGamesStore.shared.objectWillChange.eraseToAnyPublisher(), WishlistStore.shared.objectWillChange.eraseToAnyPublisher()] {
            subs.append(p.debounce(for: .milliseconds(400), scheduler: RunLoop.main).sink { [weak self] _ in self?.recompute() })
        }
    }

    private func recompute() {
        let f = FreeGamesStore.shared, w = WishlistStore.shared
        let g = f.active.filter { !f.claimed.contains($0.id) }.count
        let l = f.activeLoot.filter { !f.claimed.contains($0.id) }.count
        let d = w.items.filter(\.onSale).count
        if g != freeGames { freeGames = g }
        if l != freeLoot { freeLoot = l }
        if d != deals { deals = d }
    }
}
