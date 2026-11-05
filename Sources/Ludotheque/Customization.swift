// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI

/// Interface customisation: what is shown, in which order, and how.
/// Everything is stored in UserDefaults ("ui.*") and read with @AppStorage by the views.

/// A set of hidden ids stored as a comma-separated string.
struct IdSet {
    var raw: String
    var ids: Set<String> { Set(raw.split(separator: ",").map(String.init)) }
    func contains(_ id: String) -> Bool { ids.contains(id) }
    mutating func set(_ id: String, hidden: Bool) {
        var s = ids
        if hidden { s.insert(id) } else { s.remove(id) }
        raw = s.sorted().joined(separator: ",")
    }
}

/// An ordered list of ids stored as a comma-separated string; unknown ids are dropped, new ones appended.
func orderedIds(_ raw: String, all: [String]) -> [String] {
    let saved = raw.split(separator: ",").map(String.init).filter(all.contains)
    return saved + all.filter { !saved.contains($0) }
}

// MARK: - Catalogues of customisable elements

enum SidebarSection: String, CaseIterable, Identifiable {
    case top, library, stores, availability, presets, platforms
    var id: String { rawValue }
    var title: String {
        switch self {
        case .top: "En-tête (Accueil, Profil…)"
        case .library: "Bibliothèque"
        case .stores: "Boutiques"
        case .availability: "Disponibilité"
        case .presets: "Vues enregistrées"
        case .platforms: "Plateformes"
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case home, profile, statistics, achievements, refresh
    case all, playable, recent, favorites, performance, emulators, windows
    case search, freeGames, freeLoot, wishlist
    case installed, installable, cloud
    var id: String { rawValue }

    var section: SidebarSection {
        switch self {
        case .home, .profile, .statistics, .achievements, .refresh: .top
        case .all, .playable, .recent, .favorites, .performance, .emulators, .windows: .library
        case .search, .freeGames, .freeLoot, .wishlist: .stores
        case .installed, .installable, .cloud: .availability
        }
    }
    var title: String {
        switch self {
        case .home: "Accueil"
        case .profile: "Profil"
        case .statistics: "Statistiques"
        case .achievements: "Succès"
        case .refresh: "Actualisations"
        case .all: "Tous les jeux"
        case .playable: "Jouables"
        case .recent: "Récents"
        case .favorites: "Favoris"
        case .performance: "Performances"
        case .emulators: "Émulateurs"
        case .windows: "Jouer aux jeux Windows"
        case .search: "Recherche de prix"
        case .freeGames: "Jeux gratuits"
        case .freeLoot: "Objets gratuits"
        case .wishlist: "Liste de souhaits"
        case .installed: LaunchKind.installed.label
        case .installable: LaunchKind.installable.label
        case .cloud: LaunchKind.cloud.label
        }
    }
    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .profile: "person.crop.circle.fill"
        case .statistics: "chart.bar.xaxis"
        case .achievements: "trophy.fill"
        case .refresh: "arrow.triangle.2.circlepath"
        case .all: "square.grid.2x2.fill"
        case .playable: "play.circle.fill"
        case .recent: "clock.fill"
        case .favorites: "star.fill"
        case .performance: "gauge.with.dots.needle.67percent"
        case .emulators: "arcade.stick.console"
        case .windows: "pc"
        case .search: "tag.fill"
        case .freeGames: "gift.fill"
        case .freeLoot: "shippingbox.fill"
        case .wishlist: "heart.fill"
        case .installed: LaunchKind.installed.symbol
        case .installable: LaunchKind.installable.symbol
        case .cloud: LaunchKind.cloud.symbol
        }
    }
    var tint: Color {
        switch self {
        case .home, .refresh: .accentColor
        case .profile: .indigo
        case .statistics: .orange
        case .achievements, .favorites: .yellow
        case .performance: .pink
        case .emulators: .purple
        case .windows: .blue
        case .search: .teal
        case .freeGames, .installed: .green
        case .freeLoot: .purple
        case .wishlist: .pink
        case .installable: .orange
        case .cloud: .blue
        default: .accentColor
        }
    }
    var scope: Scope {
        switch self {
        case .home: .home
        case .profile: .profile
        case .statistics: .statistics
        case .achievements: .achievements
        case .refresh: .refresh
        case .all: .all
        case .playable: .playable
        case .recent: .recent
        case .favorites: .favorites
        case .performance: .performance
        case .emulators: .emulators
        case .windows: .windows
        case .search: .search
        case .freeGames: .freeGames
        case .freeLoot: .freeLoot
        case .wishlist: .wishlist
        case .installed: .installed
        case .installable: .installable
        case .cloud: .cloud
        }
    }
    /// Shows a count badge.
    var counted: Bool { [.all, .playable, .recent, .favorites, .installed, .installable, .cloud, .freeGames, .freeLoot, .wishlist].contains(self) }
}

enum ToolbarItemKind: String, CaseIterable, Identifiable {
    case filters, view, random, add, platforms, more, refresh
    var id: String { rawValue }
    var title: String {
        switch self {
        case .filters: "Filtres"
        case .view: "Affichage et tri"
        case .random: "Jeu au hasard"
        case .add: "Ajouter un jeu"
        case .platforms: "Gestion des plateformes"
        case .more: "Plus (mode TV, statistiques…)"
        case .refresh: "Actualiser"
        }
    }
}

enum HomeSection: String, CaseIterable, Identifiable {
    case resume, week, free, deals, backlog, news
    var id: String { rawValue }
    var title: String {
        switch self {
        case .resume: "Reprendre"
        case .week: "Temps de jeu de la semaine"
        case .free: "Gratuit en ce moment"
        case .deals: "Promos de la liste de souhaits"
        case .backlog: "Ta pile de jeux"
        case .news: "Actualités de tes jeux"
        }
    }
}

enum DetailSection: String, CaseIterable, Identifiable {
    case play, performance, personal, stats, achievements, news, metadata, screenshots, customize
    var id: String { rawValue }
    var title: String {
        switch self {
        case .play: "Boutons Jouer / Installer par plateforme"
        case .performance: "Verdict de performances"
        case .personal: "Statut, note, tags et notes"
        case .stats: "Temps de jeu et historique"
        case .achievements: "Succès"
        case .news: "Actualités et notes de patch"
        case .metadata: "Description, genres, studio"
        case .screenshots: "Captures d'écran"
        case .customize: "Personnaliser (titre, jaquette)"
        }
    }
}

enum UIKeys {
    static let hiddenSidebar = "ui.hiddenSidebar"
    static let sectionOrder = "ui.sectionOrder"
    static let hiddenSections = "ui.hiddenSections"
    static let hiddenToolbar = "ui.hiddenToolbar"
    static let homeOrder = "ui.homeOrder"
    static let hiddenHome = "ui.hiddenHome"
    static let detailOrder = "ui.detailOrder"
    static let hiddenDetail = "ui.hiddenDetail"
    static let sidebarSize = "ui.sidebarSize"
    static let showBadges = "ui.showBadges"
    static let tileTitle = "ui.tileTitle"
    static let tileLogos = "ui.tileLogos"
    static let tileSubtitle = "ui.tileSubtitle"
    static let tileStatus = "ui.tileStatus"
    static let tileBadge = "ui.tileBadge"
    static let tileHover = "ui.tileHover"
    static let tileDim = "ui.tileDim"
    static let tileRadius = "ui.tileRadius"
    static let tileAspect = "ui.tileAspect"
    static let tileFont = "ui.tileFont"
    static let background = "ui.background"
    static let detailBanner = "ui.detailBanner"
    static let gridEngine = "ui.gridEngine"
    /// AppKit grid by default: recycled tiles, 60/120 fps scrolling, less memory (measured 5 Nov 2026).
    static let defaultGridEngine = "native"

    /// Every key that the "reset" and "export" actions cover (plus older settings shown in Options).
    static let all = [hiddenSidebar, sectionOrder, hiddenSections, hiddenToolbar, homeOrder, hiddenHome, detailOrder, hiddenDetail,
                      sidebarSize, showBadges, tileTitle, tileLogos, tileSubtitle, tileStatus, tileBadge, tileHover, tileDim, tileRadius,
                      tileAspect, tileFont, background, detailBanner, gridEngine, "appearance", "accent", "tileWidth", "viewMode", "groupBy",
                      "hiddenSidebarPlatforms", "showAllPlatforms", "menuBarExtra"]
}

extension SidebarRowSize {
    init(_ raw: String) { self = raw == "small" ? .small : raw == "large" ? .large : .medium }
}

/// Grid tile aspect ratio.
func tileAspectRatio(_ raw: String) -> CGFloat {
    switch raw { case "1:1": 1; case "3:4": 3 / 4; case "16:9": 16 / 9; default: 2 / 3 }
}

// MARK: - Editors

/// Toggle + reorder editor for an ordered list of elements.
struct OrderedToggleList: View {
    let items: [(id: String, title: String)]
    @Binding var orderRaw: String
    @Binding var hiddenRaw: String

    var body: some View {
        let order = orderedIds(orderRaw, all: items.map(\.id))
        VStack(spacing: 4) {
            ForEach(Array(order.enumerated()), id: \.element) { i, id in
                HStack {
                    Toggle(items.first { $0.id == id }?.title ?? id, isOn: Binding(
                        get: { !IdSet(raw: hiddenRaw).contains(id) },
                        set: { v in var s = IdSet(raw: hiddenRaw); s.set(id, hidden: !v); hiddenRaw = s.raw }))
                    Spacer()
                    Button { move(order, i, -1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.borderless).disabled(i == 0)
                    Button { move(order, i, 1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.borderless).disabled(i == order.count - 1)
                }
            }
        }
    }

    private func move(_ order: [String], _ i: Int, _ d: Int) {
        var o = order
        o.swapAt(i, i + d)
        orderRaw = o.joined(separator: ",")
    }
}

struct CustomizationView: View {
    @Environment(Library.self) var lib
    @AppStorage(UIKeys.hiddenSidebar) private var hiddenSidebar = ""
    @AppStorage(UIKeys.sectionOrder) private var sectionOrder = ""
    @AppStorage(UIKeys.hiddenSections) private var hiddenSections = ""
    @AppStorage(UIKeys.hiddenToolbar) private var hiddenToolbar = ""
    @AppStorage(UIKeys.homeOrder) private var homeOrder = ""
    @AppStorage(UIKeys.hiddenHome) private var hiddenHome = ""
    @AppStorage(UIKeys.detailOrder) private var detailOrder = ""
    @AppStorage(UIKeys.hiddenDetail) private var hiddenDetail = ""
    @AppStorage(UIKeys.sidebarSize) private var sidebarSize = "medium"
    @AppStorage(UIKeys.showBadges) private var showBadges = true
    @AppStorage(UIKeys.tileTitle) private var tileTitle = true
    @AppStorage(UIKeys.tileLogos) private var tileLogos = true
    @AppStorage(UIKeys.tileSubtitle) private var tileSubtitle = true
    @AppStorage(UIKeys.tileStatus) private var tileStatus = true
    @AppStorage(UIKeys.tileBadge) private var tileBadge = true
    @AppStorage(UIKeys.tileHover) private var tileHover = true
    @AppStorage(UIKeys.tileDim) private var tileDim = true
    @AppStorage(UIKeys.tileRadius) private var tileRadius = 10.0
    @AppStorage(UIKeys.tileAspect) private var tileAspect = "2:3"
    @AppStorage(UIKeys.tileFont) private var tileFont = "normal"
    @AppStorage(UIKeys.background) private var background = "none"
    @AppStorage(UIKeys.detailBanner) private var detailBanner = true
    @AppStorage("tileWidth") private var tileWidth = 150.0
    @AppStorage(UIKeys.gridEngine) private var gridEngine = UIKeys.defaultGridEngine

    /// Two halves shown as separate Options tabs (each builds half as many native controls).
    enum Part { case interface, tiles }
    var part: Part = .interface

    var body: some View {
        Form {
            switch part {
            case .interface:
            Section("Barre latérale — sections") {
                OrderedToggleList(items: SidebarSection.allCases.map { ($0.rawValue, $0.title) }, orderRaw: $sectionOrder, hiddenRaw: $hiddenSections)
            }
            Section("Barre latérale — éléments") {
                ForEach(SidebarSection.allCases.filter { s in SidebarItem.allCases.contains { $0.section == s } }) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        FixedColumns(items: SidebarItem.allCases.filter { $0.section == s }, columns: 3) { item in
                                Toggle(isOn: Binding(get: { !IdSet(raw: hiddenSidebar).contains(item.id) },
                                                     set: { v in var x = IdSet(raw: hiddenSidebar); x.set(item.id, hidden: !v); hiddenSidebar = x.raw })) {
                                    Label(item.title, systemImage: item.symbol)
                                }.toggleStyle(.checkbox)
                        }
                    }
                }
                Picker("Taille des lignes", selection: $sidebarSize) { Text("Compacte").tag("small"); Text("Normale").tag("medium"); Text("Grande").tag("large") }
                    .pickerStyle(.segmented)
                Toggle("Afficher les compteurs (badges)", isOn: $showBadges)
                Text("Les plateformes affichées se règlent dans Options → Bibliothèque → Barre latérale.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Barre d'outils") {
                FixedColumns(items: ToolbarItemKind.allCases, columns: 3) { t in
                        Toggle(t.title, isOn: Binding(get: { !IdSet(raw: hiddenToolbar).contains(t.id) },
                                                      set: { v in var x = IdSet(raw: hiddenToolbar); x.set(t.id, hidden: !v); hiddenToolbar = x.raw }))
                            .toggleStyle(.checkbox)
                }
            }
            Section("Fond") {
                Picker("Fond de la bibliothèque", selection: $background) {
                    Text("Aucun").tag("none"); Text("Teinte d'accent").tag("accent"); Text("Dégradé").tag("gradient")
                }.pickerStyle(.segmented)
            }
            Section("Préréglages") {
                HStack {
                    Button("Minimaliste") { applyMinimal() }
                    Button("Complet") { resetAll() }
                    Spacer()
                    Button("Exporter mes réglages…") { exportSettings() }
                    Button("Importer…") { importSettings() }
                }
                Text("« Minimaliste » ne garde que la bibliothèque, les jaquettes et le bouton Actualiser. « Complet » rétablit tout par défaut.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            case .tiles:
            Section("Tuiles de jeux") {
                Picker("Moteur de la grille", selection: $gridEngine) {
                    Text("Natif AppKit (le plus fluide)").tag("native"); Text("SwiftUI").tag("swiftui")
                }.pickerStyle(.segmented)
                Toggle("Titre sous la jaquette", isOn: $tileTitle)
                Toggle("Logos des plateformes", isOn: $tileLogos)
                Toggle("Ligne d'informations (disponibilité, temps de jeu)", isOn: $tileSubtitle)
                Toggle("Pastille de statut (en cours, terminé…)", isOn: $tileStatus)
                Toggle("Pastille de disponibilité (installé, cloud…)", isOn: $tileBadge)
                Toggle("Effet au survol", isOn: $tileHover)
                Toggle("Assombrir les jeux non jouables", isOn: $tileDim)
                Picker("Format des jaquettes", selection: $tileAspect) {
                    Text("Portrait 2:3").tag("2:3"); Text("Portrait 3:4").tag("3:4"); Text("Carré").tag("1:1"); Text("Paysage 16:9").tag("16:9")
                }
                Picker("Taille du titre", selection: $tileFont) { Text("Petite").tag("small"); Text("Normale").tag("normal"); Text("Grande").tag("large") }
                    .pickerStyle(.segmented)
                LabeledContent("Arrondi des coins") { Slider(value: $tileRadius, in: 0...24).frame(width: 220) }
                LabeledContent("Taille des jaquettes") { Slider(value: $tileWidth, in: 110...240).frame(width: 220) }
            }
            Section("Accueil — sections") {
                OrderedToggleList(items: HomeSection.allCases.map { ($0.rawValue, $0.title) }, orderRaw: $homeOrder, hiddenRaw: $hiddenHome)
            }
            Section("Fiche d'un jeu — sections") {
                Toggle("Bannière avec image de fond", isOn: $detailBanner)
                OrderedToggleList(items: DetailSection.allCases.map { ($0.rawValue, $0.title) }, orderRaw: $detailOrder, hiddenRaw: $hiddenDetail)
            }
            }
        }
        .formStyle(.grouped)
    }

    private func resetAll() {
        for k in UIKeys.all where k.hasPrefix("ui.") { UserDefaults.standard.removeObject(forKey: k) }
        lib.flash("Interface réinitialisée")
    }

    private func applyMinimal() {
        resetAll()
        hiddenSidebar = [SidebarItem.profile, .statistics, .achievements, .performance, .emulators, .windows, .search, .freeLoot,
                         .installable, .cloud].map(\.rawValue).joined(separator: ",")
        hiddenSections = [SidebarSection.presets, .stores].map(\.rawValue).joined(separator: ",")
        hiddenToolbar = [ToolbarItemKind.random, .platforms, .more].map(\.rawValue).joined(separator: ",")
        hiddenHome = [HomeSection.news, .deals, .backlog].map(\.rawValue).joined(separator: ",")
        tileLogos = false
        tileSubtitle = false
        tileStatus = false
        lib.flash("Préréglage minimaliste appliqué")
    }

    private func exportSettings() {
        var dict = [String: Any]()
        for k in UIKeys.all { if let v = UserDefaults.standard.object(forKey: k) { dict[k] = v } }
        guard let d = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Ludothèque-interface.json"
        guard panel.runModal() == .OK, let u = panel.url else { return }
        try? d.write(to: u)
        lib.flash("Réglages d'interface exportés")
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let u = panel.url, let d = try? Data(contentsOf: u),
              let dict = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        // Only known keys with simple values are accepted.
        for (k, v) in dict where UIKeys.all.contains(k) && (v is String || v is NSNumber) { UserDefaults.standard.set(v, forKey: k) }
        lib.flash("Réglages d'interface importés")
    }
}

/// Grid with a fixed number of columns. Width-adaptive grids inside forms can oscillate forever
/// (scroll bar appears → fewer columns → taller → scroll bar disappears → …) and pin the CPU.
struct FixedColumns<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    var columns = 3
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
            ForEach(rows.indices, id: \.self) { r in
                GridRow {
                    ForEach(rows[r]) { cell($0) }
                }
            }
        }
    }
}

// MARK: - Stable grid columns

private struct StableWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 900 }
extension EnvironmentValues {
    /// Width of the content area measured outside any scroll view (unaffected by scroll bars).
    var stableWidth: CGFloat {
        get { self[StableWidthKey.self] }
        set { self[StableWidthKey.self] = newValue }
    }
}

/// Column count derived from the outer width with room reserved for a scroll bar, so it never
/// changes when the scroll bar appears/disappears (which made adaptive grids loop forever).
func stableColumns(_ width: CGFloat, min: CGFloat, spacing: CGFloat, padding: CGFloat = 48, max maxWidth: CGFloat = .infinity) -> [GridItem] {
    let usable = width - padding - 18
    let n = Swift.max(1, Int((usable + spacing) / (min + spacing)))
    return Array(repeating: GridItem(.flexible(minimum: min * 0.75, maximum: maxWidth), spacing: spacing, alignment: .top), count: n)
}
