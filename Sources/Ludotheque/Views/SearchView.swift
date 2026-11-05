// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI

@MainActor
final class SearchModel: ObservableObject {
    @Published var query = ""
    @Published var results: [DLCGame] = []
    @Published var selected: DLCGame?
    @Published var message: String?

    func run() {
        results = DLCompareStore.shared.search(query)
        if results.isEmpty { message = "Aucun jeu trouvé sur DLCompare pour « \(query) »." } else { message = nil }
    }
}

/// "Recherche": CD-key prices from DLCompare (top 10 cheapest), with followed games refreshed automatically.
struct SearchView: View {
    @Environment(Library.self) var lib
    @ObservedObject private var store = DLCompareStore.shared
    @StateObject private var model = SearchModel()

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 300)
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await store.ensureIndex(force: false, cachedOnly: true) }
    }

    /// The DLCompare catalogue is downloaded on the first search only (manual mode).
    private func search() {
        Task {
            if store.indexCount == 0 { await store.ensureIndex(force: false) }
            model.run()
        }
    }

    // MARK: Left column: search + followed games

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recherche de prix").font(.title2.bold())
                Text("Clés CD uniquement, via DLCompare.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("Nom du jeu", text: $model.query).textFieldStyle(.roundedBorder).onSubmit { search() }
                    Button { search() } label: { Image(systemName: "magnifyingglass") }.disabled(model.query.isEmpty || store.loadingIndex)
                }
                if store.loadingIndex { ProgressView("Chargement du catalogue DLCompare…").controlSize(.small).font(.caption) }
                else if store.indexCount > 0 { Text("\(store.indexCount) jeux au catalogue").font(.caption2).foregroundStyle(.secondary) }
                if let m = model.message { Text(m).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(14)
            List(selection: Binding(get: { model.selected?.id }, set: { id in
                model.selected = (model.results + store.tracked.map(\.game)).first { $0.id == id }
            })) {
                if !model.results.isEmpty {
                    Section("Résultats") {
                        ForEach(model.results) { g in Text(store.realTitle(g)).lineLimit(1).tag(g.id) }
                    }
                }
                Section {
                    if store.tracked.isEmpty { Text("Suis un jeu pour voir son meilleur prix ici et être alerté des baisses.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(store.tracked) { t in
                        HStack {
                            Text(t.game.title).lineLimit(1)
                            Spacer()
                            if let b = t.best { Text(String(format: "%.2f €", b)).monospacedDigit().foregroundStyle(.green) }
                        }
                        .tag(t.id)
                        .contextMenu { Button("Ne plus suivre", role: .destructive) { store.toggleTrack(t.game) } }
                    }
                } header: {
                    HStack {
                        Text("Jeux suivis")
                        Spacer()
                        if store.refreshing { ProgressView().controlSize(.mini) }
                    }
                }
            }
            .listStyle(.sidebar)
            VStack(alignment: .leading, spacing: 6) {
                Button { Task { await store.refreshTracked() } } label: { Label("Actualiser les prix suivis", systemImage: "arrow.clockwise") }
                    .disabled(store.refreshing || store.tracked.isEmpty)
                Button { Task { let n = await store.trackWishlist(); lib.flash("\(n) jeux de la liste de souhaits suivis") } } label: {
                    Label("Suivre ma liste de souhaits", systemImage: "heart")
                }.disabled(WishlistStore.shared.items.isEmpty)
            }
            .buttonStyle(.borderless).font(.callout).padding(12)
        }
    }

    // MARK: Right column: top 10 offers

    @ViewBuilder private var detail: some View {
        if let g = model.selected {
            let offers = store.offers[g.id]
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.realTitle(g)).font(.title.bold())
                        Text("Les 10 clés CD les moins chères — hors comptes, boîtes physiques et DLC").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { store.toggleTrack(g) } label: {
                        Label(store.isTracked(g) ? "Suivi" : "Suivre le prix", systemImage: store.isTracked(g) ? "bell.fill" : "bell")
                    }
                    Button { Task { await store.loadOffers(g) } } label: { Label("Actualiser", systemImage: "arrow.clockwise") }
                        .disabled(store.loading.contains(g.id))
                    Link(destination: URL(string: g.pageURL)!) { Label("DLCompare", systemImage: "safari") }
                }
                if store.loading.contains(g.id) && offers == nil {
                    SkeletonRows().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let offers, offers.isEmpty {
                    ContentUnavailableView("Aucune clé disponible", systemImage: "key.slash", description: Text("Aucune offre de clé CD en ce moment pour ce jeu."))
                } else if let offers {
                    Table(offers) {
                        TableColumn("#") { o in Text("\((offers.firstIndex(of: o) ?? 0) + 1)").foregroundStyle(.secondary).monospacedDigit() }.width(24)
                        TableColumn("Boutique") { o in
                            HStack(spacing: 4) {
                                Text(o.shop).fontWeight(.medium)
                                if o.trusted { Image(systemName: "checkmark.seal.fill").foregroundStyle(.yellow).help("Partenaire Gold DLCompare") }
                            }
                        }.width(min: 110, ideal: 140)
                        TableColumn("Activation") { o in Text(o.platform) }.width(min: 70, ideal: 90)
                        TableColumn("Région") { o in Text(o.region).foregroundStyle(["europe", "global", "france"].contains { o.region.lowercased().contains($0) } ? Color.primary : Color.orange) }
                            .width(min: 70, ideal: 90)
                        TableColumn("Prix") { o in
                            HStack(spacing: 4) {
                                Text(String(format: "%.2f €", o.price)).fontWeight(.bold).foregroundStyle(offers.first == o ? .green : .primary)
                                if let c = o.crossed, c > o.price { Text(String(format: "%.2f", c)).strikethrough().font(.caption).foregroundStyle(.secondary) }
                            }.monospacedDigit()
                        }.width(min: 90, ideal: 110)
                        TableColumn("Avec frais") { o in
                            Text([o.card.map { String(format: "CB %.2f", $0) }, o.paypal.map { String(format: "PayPal %.2f", $0) }].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }.width(min: 120, ideal: 170)
                        TableColumn("Code promo") { o in
                            if let code = o.code {
                                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string); lib.flash("Code \(code) copié") } label: {
                                    Label(code, systemImage: "doc.on.doc").font(.caption.monospaced())
                                }.buttonStyle(.borderless).help("Copier le code")
                            }
                        }.width(min: 90, ideal: 120)
                        TableColumn("") { o in
                            Button("Acheter") { if let u = URL(string: o.url) { NSWorkspace.shared.open(u) } }.controlSize(.small).buttonStyle(.borderedProminent)
                        }.width(70)
                    }
                    Text("Certaines boutiques sont des places de marché : vérifie la région et la plateforme d'activation avant l'achat. Prix DLCompare, actualisés à chaque « Tout actualiser » pour les jeux suivis.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            // Unstructured: keeps loading if the user switches tab meanwhile.
            .onAppear { if store.offers[g.id] == nil { Task { await store.loadOffers(g) } } }
            .onChange(of: g.id) { _, _ in if store.offers[g.id] == nil { Task { await store.loadOffers(g) } } }
        } else {
            ContentUnavailableView("Cherche un jeu", systemImage: "tag",
                                   description: Text("Compare les prix des clés CD sur des dizaines de boutiques et suis tes jeux pour être alerté des baisses de prix."))
        }
    }
}
