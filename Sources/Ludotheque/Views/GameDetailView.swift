// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI

@MainActor
final class DetailsModel: ObservableObject {
    @Published var details: GamesDB.Details?
    @Published var loading = false
    @Published var achievements: (platform: Platform, list: [Achievement])?
    @Published var achievementsLoaded = false
    @Published var news: [NewsItem] = []
    private var loadedFor: String?
    private var extrasFor: String?

    /// Achievements and news are only fetched when their sections are shown.
    func loadExtras(_ g: GameGroup, achievements wantAch: Bool, news wantNews: Bool) async {
        guard extrasFor != g.id else { return }
        extrasFor = g.id
        achievements = nil; achievementsLoaded = false; news = []
        if wantNews, let id = News.steamId(g) { news = await News.fetch(appId: id, game: g.title, count: 3) }
        if wantAch { achievements = await Achievements.fetch(g) }
        achievementsLoaded = true
    }

    func load(_ g: GameGroup) async {
        guard loadedFor != g.id else { return }
        loadedFor = g.id
        details = nil
        loading = true
        details = await GamesDB.shared.details(for: g.games)
        loading = false
    }
}

struct GameDetailView: View {
    @Environment(Library.self) var lib
    let group: GameGroup
    @StateObject private var model = DetailsModel()

    @AppStorage(UIKeys.detailOrder) private var detailOrder = ""
    @AppStorage(UIKeys.hiddenDetail) private var hiddenDetail = ""
    @AppStorage(UIKeys.detailBanner) private var showBanner = true

    var body: some View {
        let order = orderedIds(detailOrder, all: DetailSection.allCases.map(\.rawValue)).compactMap(DetailSection.init(rawValue:))
        let hidden = IdSet(raw: hiddenDetail)
        let visible = order.filter { !hidden.contains($0.rawValue) }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                ForEach(visible) { sec in detailSection(sec) }
            }
            .padding(16)
        }
        .task(id: group.id) {
            await model.load(group)
            await model.loadExtras(group, achievements: visible.contains(.achievements), news: visible.contains(.news))
        }
        .toolbar {
            ToolbarItem {
                Button { lib.selected = nil } label: { Label("Fermer", systemImage: "sidebar.trailing") }
            }
        }
    }

    @ViewBuilder private func detailSection(_ sec: DetailSection) -> some View {
        let e = lib.binding(group.key)
        switch sec {
        case .play:
            playButtons
        case .performance:
            PerfBadge(group: group)
        case .personal:
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Picker("Statut", selection: Binding(get: { e.wrappedValue.status ?? Completion.none }, set: { e.wrappedValue.status = $0 })) {
                    ForEach(Completion.allCases) { c in Label(c.label, systemImage: c.symbol).tag(c) }
                }
                HStack {
                    Text("Ma note")
                    Spacer()
                    ForEach(1...5, id: \.self) { n in
                        Image(systemName: n <= (e.wrappedValue.rating ?? 0) ? "star.fill" : "star")
                            .foregroundStyle(.yellow)
                            .onTapGesture { e.wrappedValue.rating = e.wrappedValue.rating == n ? nil : n }
                    }
                }
                TextField("Tags (séparés par des virgules)", text: Binding(
                    get: { (e.wrappedValue.tags ?? []).joined(separator: ", ") },
                    set: { e.wrappedValue.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                Text("Notes").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: Binding(get: { e.wrappedValue.notes ?? "" }, set: { e.wrappedValue.notes = $0 }))
                    .font(.callout).frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }
        case .stats:
            stats(e.wrappedValue)
        case .achievements:
            achievementsSection
        case .news:
            if !model.news.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Actualités").font(.headline)
                    ForEach(model.news) { NewsRow(item: $0) }
                }
            }
        case .metadata:
            if let d = model.details { metadata(d, screenshots: false) }
            else if model.loading { SkeletonLines(count: 5) }
        case .screenshots:
            if let d = model.details, !d.screenshots.isEmpty { screenshots(d) }
        case .customize:
            DisclosureGroup("Personnaliser") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Titre affiché", text: Binding(get: { e.wrappedValue.customTitle ?? "" }, set: { e.wrappedValue.customTitle = $0.isEmpty ? nil : $0 }),
                              prompt: Text(group.title))
                    TextField("URL de la jaquette", text: Binding(get: { e.wrappedValue.customCover ?? "" }, set: { e.wrappedValue.customCover = $0.isEmpty ? nil : $0 }),
                              prompt: Text("https://… ou laisser vide"))
                    Button("Choisir une image…") { chooseCover() }
                }.padding(.top, 6)
            }
        }
    }

    @ViewBuilder private var achievementsSection: some View {
        if let a = model.achievements, !a.list.isEmpty {
            let done = a.list.filter { $0.unlocked != nil }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Succès").font(.headline)
                    PlatformLogo(platform: a.platform, size: 14)
                    Spacer()
                    Text("\(done.count)/\(a.list.count)").monospacedDigit().foregroundStyle(.secondary)
                }
                ProgressView(value: Double(done.count), total: Double(a.list.count))
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 6), count: 6), alignment: .leading, spacing: 6) {
                    ForEach(a.list.sorted { ($0.unlocked ?? .distantPast) > ($1.unlocked ?? .distantPast) }.prefix(40)) { ach in
                        CoverImage(game: Game(id: "ach_\(group.id)_\(ach.id)", platform: a.platform, externalId: "", title: ach.name, coverURL: ach.icon))
                            .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
                            .saturation(ach.unlocked == nil ? 0 : 1).opacity(ach.unlocked == nil ? 0.45 : 1)
                            .help("\(ach.name) — \(ach.detail)\(ach.unlocked.map { "\nDébloqué le \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")")
                    }
                }
            }
        } else if !model.achievementsLoaded && group.games.contains(where: { $0.platform == .steam || $0.platform == .xbox }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Succès").font(.headline); Spacer(); SkeletonBlock(width: 40) }
                SkeletonBlock(height: 4, radius: 2)
                HStack(spacing: 6) { ForEach(0..<6, id: \.self) { _ in SkeletonBlock(width: 40, height: 40, radius: 6) } }
            }
            .skeletonPulse()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                if showBanner, let bg = model.details?.background {
                    CoverImage(game: Game(id: "bg_\(group.id)", platform: group.primary.platform, externalId: "", title: "", coverURL: bg))
                        .frame(height: 150).clipped()
                        .overlay(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                } else {
                    Color(group.primary.platform.color).opacity(0.25).frame(height: 150)
                }
                HStack(alignment: .bottom, spacing: 12) {
                    CoverImage(game: lib.coverGame(group))
                        .frame(width: 80, height: 120).clipShape(RoundedRectangle(cornerRadius: 8)).shadow(radius: 6)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lib.title(group)).font(.title3.bold()).foregroundStyle(.white).lineLimit(3).shadow(radius: 3)
                        if let s = group.games.compactMap(\.system).first { Text(s).font(.caption).foregroundStyle(.white.opacity(0.85)) }
                    }
                }.padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack {
                Button { lib.toggleFavorite(group) } label: {
                    Label(lib.isFavorite(group) ? "Favori" : "Ajouter aux favoris", systemImage: lib.isFavorite(group) ? "star.fill" : "star")
                }
                Button { lib.toggleHidden(group) } label: { Label(lib.isHidden(group) ? "Masqué" : "Masquer", systemImage: "eye.slash") }
            }.controlSize(.small)
        }
    }

    private var playButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(group.games) { g in
                HStack {
                    PlatformLogo(platform: g.platform, size: 18)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(g.platform.name).font(.callout.weight(.medium))
                        Text(g.launchKind.label).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    switch g.launchKind {
                    case .installed: Button("Jouer") { lib.launch(g) }.buttonStyle(.borderedProminent)
                    case .installable: Button("Installer") { lib.launch(g) }
                    case .cloud: Button("Streaming") { lib.launch(g) }
                    case .none: if g.storeURL != nil { Button("Page") { lib.openStore(g) } }
                    }
                    Menu { GameActions(game: g) } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).frame(width: 24)
                }
            }
        }
    }

    private func stats(_ e: UserEntry) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            row(String(localized: "Temps de jeu"), format(lib.playtime(group)))
            if group.playtimeByPlatform.count > 1 {
                ForEach(group.playtimeByPlatform, id: \.0) { p, m in row("  · \(p.name)", format(m)) }
            }
            if let t = e.trackedMinutes, t > 0 { row(String(localized: "Mesuré par Ludothèque"), format(t)) }
            row(String(localized: "Dernière partie"), lib.lastPlayed(group)?.formatted(date: .long, time: .omitted) ?? String(localized: "Jamais"))
            if let n = e.launchCount { row(String(localized: "Lancements"), "\(n)") }
            if let a = e.added { row(String(localized: "Ajouté le"), a.formatted(date: .abbreviated, time: .omitted)) }
        }.font(.callout)
    }

    private func screenshots(_ d: GamesDB.Details) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(d.screenshots, id: \.self) { u in
                    CoverImage(game: Game(id: "shot_\(u.hashValue)", platform: .other, externalId: "", title: "", coverURL: u))
                        .frame(width: 200, height: 112).clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private func metadata(_ d: GamesDB.Details, screenshots: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                if let r = d.release { row(String(localized: "Sortie"), r.formatted(date: .long, time: .omitted)) }
                if !d.genres.isEmpty { row(String(localized: "Genres"), d.genres.joined(separator: ", ")) }
                if !d.developers.isEmpty { row(String(localized: "Développeur"), d.developers.joined(separator: ", ")) }
                if !d.publishers.isEmpty { row(String(localized: "Éditeur"), d.publishers.joined(separator: ", ")) }
                if !d.modes.isEmpty { row(String(localized: "Modes"), d.modes.joined(separator: ", ")) }
                if let s = d.score { row(String(localized: "Note critique"), "\(Int(s.rounded())) / 100") }
            }.font(.callout)
            if let s = d.summary { Text(s).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            if screenshots && !d.screenshots.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(d.screenshots, id: \.self) { u in
                            CoverImage(game: Game(id: "shot_\(u.hashValue)", platform: .other, externalId: "", title: "", coverURL: u))
                                .frame(width: 200, height: 112).clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary)
            Text(v).textSelection(.enabled)
        }
    }

    private func format(_ m: Int) -> String { m == 0 ? "—" : (m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min") }

    private func chooseCover() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let u = panel.url else { return }
        let dest = Paths.userCovers.appendingPathComponent("group-\(abs(group.key.hashValue)).\(u.pathExtension)")
        try? FileManager.default.removeItem(at: dest)
        if (try? FileManager.default.copyItem(at: u, to: dest)) != nil {
            lib.update(group.key) { $0.customCover = dest.absoluteString + "?v=\(Int(Date().timeIntervalSince1970))" }
        }
    }
}
