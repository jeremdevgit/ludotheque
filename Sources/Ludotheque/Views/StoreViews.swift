// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI

// MARK: - Home (Steam / Xbox / PS5-style dashboard)

@MainActor
final class HomeModel: ObservableObject {
    @Published var backlog: [String] = []

    func pickBacklog(_ lib: Library) {
        guard backlog.isEmpty else { return }
        backlog = lib.groups.filter { g in
            g.games.contains { $0.launchKind == .installed || $0.launchKind == .installable } &&
            (lib.statusOf(g) == .planned || (lib.statusOf(g) == .none && lib.playtime(g) == 0))
        }.shuffled().prefix(8).map(\.id)
    }

}

struct HomeView: View {
    @Environment(Library.self) var lib
    @ObservedObject private var free = FreeGamesStore.shared
    @ObservedObject private var wish = WishlistStore.shared
    @ObservedObject private var log = SessionLog.shared
    @StateObject private var model = HomeModel()

    @AppStorage(UIKeys.homeOrder) private var homeOrder = ""
    @AppStorage(UIKeys.hiddenHome) private var hiddenHome = ""

    var body: some View {
        let recent = lib.groups.compactMap { g -> (GameGroup, Date)? in
            guard g.games.contains(where: { $0.launchKind != .none }), let d = lib.lastPlayed(g) else { return nil }
            return (g, d)
        }.sorted { $0.1 > $1.1 }.prefix(12).map(\.0)
        let order = orderedIds(homeOrder, all: HomeSection.allCases.map(\.rawValue)).compactMap(HomeSection.init(rawValue:))
        let hidden = IdSet(raw: hiddenHome)
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                ForEach(order.filter { !hidden.contains($0.rawValue) }) { sec in homeSection(sec, recent) }
            }
            .padding(24)
        }
        .task {
            model.pickBacklog(lib)

        }
    }

    @ViewBuilder private func homeSection(_ sec: HomeSection, _ recent: [GameGroup]) -> some View {
        switch sec {
        case .resume:
            if !recent.isEmpty { shelf("Reprendre", recent) }
        case .week:
            weekChart
        case .free:
            if !free.active.isEmpty {
                section("Gratuit en ce moment", action: ("Tout voir", { lib.scope = .freeGames })) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) { ForEach(free.active.prefix(10)) { GiveawayCard(item: $0, compact: true) } }
                    }
                }
            }
        case .deals:
            let deals = wish.items.filter(\.onSale)
            if !deals.isEmpty {
                section("En promo dans ta liste de souhaits", action: ("Liste de souhaits", { lib.scope = .wishlist })) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) { ForEach(deals) { WishCard(item: $0) } }
                    }
                }
            }
        case .backlog:
            // Picked once per visit (not reshuffled on every redraw).
            let picks = model.backlog.compactMap { k in lib.groups.first { $0.id == k } }
            if !picks.isEmpty { shelf("Ta pile de jeux — pourquoi pas ?", picks) }
        case .news:
            if !NewsStore.shared.items.isEmpty {
                section("Actualités de tes jeux") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(NewsStore.shared.items.prefix(8)) { NewsRow(item: $0) }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting).font(.largeTitle.bold())
                Text("\(lib.groups.count) jeux · \(lib.count(Scope.installed)) installés · \(lib.count(Scope.playable)) jouables sur ce Mac")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let d = lib.lastFullRefresh {
                Text("Actualisé \(d.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 6 ? "Bonne nuit" : h < 18 ? "Bonjour" : "Bonsoir"
    }

    private var weekChart: some View {
        let days = log.perDay(7)
        let maxV = max(30, days.map(\.1).max() ?? 0)
        return section("Cette semaine : \(format(log.thisWeekMinutes))") {
            if log.sessions.isEmpty {
                Text("Lance un jeu depuis Ludothèque : tes sessions apparaîtront ici.").font(.callout).foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(days, id: \.0) { day, mins in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4).fill(mins > 0 ? Color.accentColor.gradient : Color.secondary.opacity(0.2).gradient)
                            .frame(width: 28, height: max(4, 80 * CGFloat(mins) / CGFloat(maxV)))
                            .help(format(mins))
                        Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 100, alignment: .bottom)
        }
    }

    private func shelf(_ title: String, _ groups: [GameGroup]) -> some View {
        section(title) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(groups) { g in GroupTile(group: g).frame(width: 140) }
                }
                .padding(.vertical, 6).padding(.horizontal, 6)
            }
        }
    }

    private func section<C: View>(_ title: String, action: (String, () -> Void)? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
                if let action { Button(action.0, action: action.1).buttonStyle(.link) }
            }
            content()
        }
    }

    private func format(_ m: Int) -> String { m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min" }
}

struct NewsRow: View {
    let item: NewsItem
    var body: some View {
        Link(destination: URL(string: item.url) ?? URL(string: "https://store.steampowered.com")!) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.game).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                    Text(item.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                }
                Text(item.title).font(.callout.weight(.medium)).foregroundStyle(.primary)
                Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Free games

struct GiveawayCard: View {
    @ObservedObject private var store = FreeGamesStore.shared
    let item: Giveaway
    var compact = false

    var body: some View {
        let claimed = store.claimed.contains(item.id)
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(game: Game(id: "give_\(item.id)", platform: item.store, externalId: item.id, title: item.cleanTitle, coverURL: item.image))
                .aspectRatio(16 / 9, contentMode: .fill)
                .frame(width: compact ? 240 : nil, height: compact ? 135 : 170).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 4) { ForEach(item.allPlatforms.prefix(5), id: \.self) { PlatformLogo(platform: $0, size: 20) } }.padding(8)
                }
                .overlay(alignment: .topTrailing) {
                    if let k = item.kind, k != "Game" {
                        Text(k == "Early Access" ? "Bêta" : "Objet / DLC").font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(.purple, in: Capsule()).padding(8)
                    }
                }
                .opacity(claimed ? 0.5 : 1)
            Text(item.cleanTitle).font(.callout.weight(.semibold)).lineLimit(1)
            HStack(spacing: 6) {
                if let w = item.worth { Text(w).strikethrough().foregroundStyle(.secondary) }
                Text("Gratuit").foregroundStyle(.green).fontWeight(.semibold)
                Spacer()
                if let end = item.endDate { Text("jusqu'au \(end.formatted(.dateTime.day().month()))").foregroundStyle(.secondary) }
            }.font(.caption)
            if !compact, let d = item.description { Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
            HStack {
                Button(claimed ? "Récupéré ✓" : "Récupérer") {
                    if let u = URL(string: item.url) { NSWorkspace.shared.open(u) }
                    store.claimed.insert(item.id)
                }
                .buttonStyle(.borderedProminent).tint(claimed ? .gray : .green).controlSize(.small)
                if claimed { Button("Annuler") { store.claimed.remove(item.id) }.controlSize(.small) }
            }
        }
        .frame(width: compact ? 240 : nil)
    }
}

struct FreeGamesView: View {
    @Environment(\.stableWidth) private var stableWidth
    @ObservedObject private var store = FreeGamesStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Jeux gratuits à récupérer").font(.largeTitle.bold())
                        Text("Epic Games, Steam, GOG, Prime Gaming, itch.io… Une notification t'avertit des nouveautés.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.loading { ProgressView().controlSize(.small) }
                }
                if store.active.isEmpty && !store.loading {
                    ContentUnavailableView("Aucun jeu gratuit pour l'instant", systemImage: "gift", description: Text("Clique sur Actualiser pour vérifier."))
                }
                LazyVGrid(columns: stableColumns(stableWidth, min: 280, spacing: 18, padding: 48), spacing: 22) {
                    ForEach(store.active) { GiveawayCard(item: $0) }
                }
                Text("Données : GamerPower.com").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(24)
        }

    }
}

// MARK: - Wishlist

@MainActor
final class WishSearchModel: ObservableObject {
    @Published var query = ""
    @Published var results: [WishItem] = []
    @Published var searching = false
    @Published var message: String?

    func search() async {
        searching = true
        results = await WishlistStore.shared.search(query)
        searching = false
    }
}

struct WishCard: View {
    @ObservedObject private var store = WishlistStore.shared
    let item: WishItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            CoverImage(game: Game(id: "wish_\(item.id)", platform: .steam, externalId: item.id, title: item.title, coverURL: item.cover,
                                  altCoverURL: item.steamAppId.map { "https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/\($0)/header.jpg" }))
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if let d = item.steamDiscount, d > 0 {
                        Text("−\(d) %").font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.green, in: Capsule()).padding(6)
                    }
                }
            Text(item.title).font(.callout.weight(.medium)).lineLimit(1)
            if let p = item.steamPrice { Text(String(format: "%.2f € sur Steam", p)).font(.caption) }
            if let b = item.bestDeal {
                Text(String(format: "%.2f $", b) + (item.bestDealStore.map { " · \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 140)
        .contextMenu {
            if let u = item.bestDealURL.flatMap(URL.init) { Link("Voir la meilleure offre", destination: u) }
            if let a = item.steamAppId, let u = URL(string: "steam://store/\(a)") { Link("Ouvrir dans Steam", destination: u) }
            Button("Retirer", role: .destructive) { store.remove(item.id) }
        }
    }
}

struct WishlistView: View {
    @Environment(Library.self) var lib
    @ObservedObject private var store = WishlistStore.shared
    @StateObject private var search = WishSearchModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Liste de souhaits").font(.largeTitle.bold())
                    Text("Prix suivis sur Steam (€) et sur 30 boutiques (CheapShark, $). Alerte quand un jeu est en promo ou sous ton prix cible.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { search.message = await store.importSteam() }
                } label: { Label("Importer ma liste Steam", systemImage: "square.and.arrow.down") }
                Button { Task { await store.refresh() } } label: { Label("Actualiser les prix", systemImage: "arrow.clockwise") }
                    .disabled(store.refreshing)
            }
            .padding(20)
            HStack {
                TextField("Ajouter un jeu à ta liste…", text: $search.query).textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await search.search() } }
                Button("Rechercher") { Task { await search.search() } }.disabled(search.query.isEmpty)
                if search.searching || store.refreshing { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 20)
            if let m = search.message { Text(m).font(.caption).foregroundStyle(.secondary).padding(.top, 4) }
            if !search.results.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(search.results) { r in
                            Button {
                                store.add(r)
                                search.results = []
                                search.query = ""
                            } label: {
                                HStack {
                                    Image(systemName: store.contains(title: r.title) ? "checkmark.circle.fill" : "plus.circle.fill")
                                    Text(r.title).lineLimit(1)
                                    if let p = r.bestDeal { Text(String(format: "%.2f $", p)).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }.padding(.horizontal, 20).padding(.vertical, 8)
                }
            }
            Divider().padding(.top, 8)
            if store.items.isEmpty {
                ContentUnavailableView("Ta liste de souhaits est vide", systemImage: "heart",
                                       description: Text("Recherche un jeu ci-dessus ou importe ta liste Steam."))
            } else {
                Table(store.items) {
                    TableColumn("Jeu") { it in
                        HStack(spacing: 8) {
                            CoverImage(game: Game(id: "wish_\(it.id)", platform: .steam, externalId: it.id, title: it.title, coverURL: it.cover))
                                .frame(width: 22, height: 33).clipShape(RoundedRectangle(cornerRadius: 3))
                            Text(it.title).lineLimit(1)
                            if it.onSale { Text("PROMO").font(.caption2.bold()).foregroundStyle(.white).padding(.horizontal, 4).background(.green, in: Capsule()) }
                            if lib.groups.contains(where: { Integrations.norm($0.title) == Integrations.norm(it.title) }) {
                                Text("possédé").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }.width(min: 200, ideal: 280)
                    TableColumn("Steam") { it in
                        Text(it.steamPrice.map { String(format: "%.2f €", $0) + ((it.steamDiscount ?? 0) > 0 ? " (−\(it.steamDiscount!) %)" : "") } ?? "—")
                            .foregroundStyle((it.steamDiscount ?? 0) > 0 ? .green : .primary)
                    }.width(min: 90, ideal: 120)
                    TableColumn("Meilleure offre") { it in
                        if let u = it.bestDealURL.flatMap(URL.init), let p = it.bestDeal {
                            Link(String(format: "%.2f $", p) + (it.bestDealStore.map { " · \($0)" } ?? ""), destination: u)
                        } else { Text("—").foregroundStyle(.secondary) }
                    }.width(min: 120, ideal: 170)
                    TableColumn("Plus bas historique") { it in Text(it.lowestEver.map { String(format: "%.2f $", $0) } ?? "—").foregroundStyle(.secondary) }
                        .width(min: 90, ideal: 120)
                    TableColumn("Prix cible") { it in
                        TextField("—", value: Binding(get: { it.targetPrice }, set: { store.setTarget(it.id, $0) }), format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 70)
                    }.width(90)
                    TableColumn("") { it in
                        Button { store.remove(it.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }.width(30)
                }
            }
        }
    }
}

// MARK: - Free in-game items, DLC and betas

@MainActor
final class LootFilter: ObservableObject {
    @Published var platform: Platform?
    @Published var kind = "all"
}

struct FreeLootView: View {
    @Environment(\.stableWidth) private var stableWidth
    @ObservedObject private var store = FreeGamesStore.shared
    @StateObject private var filter = LootFilter()

    var body: some View {
        let all = store.activeLoot
        let platforms = Array(Set(all.flatMap(\.allPlatforms))).sorted { $0.name < $1.name }
        let list = all.filter { g in
            (filter.platform == nil || g.allPlatforms.contains(filter.platform!)) &&
            (filter.kind == "all" || (filter.kind == "beta") == (g.kind == "Early Access"))
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Objets gratuits à récupérer").font(.largeTitle.bold())
                        Text("DLC, skins, packs et objets en jeu, codes et bêtas — PC, consoles et mobile.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.loading { ProgressView().controlSize(.small) }
                    Button { Task { await store.refresh() } } label: { Label("Actualiser", systemImage: "arrow.clockwise") }.disabled(store.loading)
                }
                HStack {
                    Picker("Type", selection: $filter.kind) {
                        Text("Tout (\(all.count))").tag("all")
                        Text("Objets & DLC").tag("loot")
                        Text("Bêtas").tag("beta")
                    }.pickerStyle(.segmented).frame(width: 340)
                    Picker("Plateforme", selection: $filter.platform) {
                        Text("Toutes les plateformes").tag(Platform?.none)
                        ForEach(platforms) { Text($0.name).tag(Platform?.some($0)) }
                    }.frame(width: 240)
                    Spacer()
                    Text("\(list.filter { !store.claimed.contains($0.id) }.count) à récupérer").foregroundStyle(.secondary)
                }
                if list.isEmpty && !store.loading {
                    ContentUnavailableView("Rien pour l'instant", systemImage: "shippingbox", description: Text("Clique sur Actualiser pour vérifier."))
                }
                LazyVGrid(columns: stableColumns(stableWidth, min: 280, spacing: 18, padding: 48), spacing: 22) {
                    ForEach(list) { GiveawayCard(item: $0) }
                }
                Text("Données : GamerPower.com").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(24)
        }

    }
}
