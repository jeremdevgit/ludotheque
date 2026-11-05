// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI

@MainActor
final class IntegrationsModel: ObservableObject {
    @Published var selection: Platform? = .steam { didSet { load() } }
    @Published var values: [String: String] = [:]
    @Published var revision = 0 // bump to refresh status after a sync

    init() { load() }

    func load() {
        guard let p = selection, let i = Integrations.of(p) else { values = [:]; return }
        let c = Creds(p)
        var v = [String: String]()
        for f in i.fields { v[f.key] = c[f.key] ?? f.prefill?() ?? "" }
        values = v
    }

    func save(_ i: Integration) {
        let c = Creds(i.platform)
        for f in i.fields { c[f.key] = values[f.key] }
    }
}

struct IntegrationsView: View {
    @Environment(Library.self) var lib
    @StateObject private var model = IntegrationsModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gestion des plateformes").font(.title2.bold())
                    Text("\(Integrations.all.filter(\.isConnected).count) compte(s) connecté(s) · \(lib.groups.count) jeux")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if let s = StatusCenter.shared.message { Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: 280, alignment: .trailing) }
                Button {
                    Task { await lib.searchGames(); model.revision += 1 }
                } label: {
                    Label("Rechercher les jeux", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(lib.scanning || !lib.syncing.isEmpty)
                .help("Relance la détection locale et la synchronisation de toutes les plateformes connectées")
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            Divider()
            content
        }
        .frame(minWidth: 860, minHeight: 600)
    }

    private var content: some View {
        HStack(spacing: 0) {
            List(selection: $model.selection) {
                Section("Connexion par compte") {
                    ForEach(Integrations.all.map(\.platform)) { p in row(p) }
                }
                Section("Autres plateformes") {
                    ForEach(Platform.allCases.filter { $0 != .other && Integrations.of($0) == nil }) { p in row(p) }
                }
            }
            .listStyle(.sidebar)
            .frame(width: 230)
            Divider()
            ScrollView {
                if let p = model.selection { detail(p).padding(24).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
    }

    private func row(_ p: Platform) -> some View {
        HStack {
            PlatformLogo(platform: p, size: 18)
            Text(p.name)
            Spacer()
            if lib.syncing.contains(p) { ProgressView().controlSize(.mini) }
            else if let i = Integrations.of(p), i.isConnected {
                Circle().fill(Integrations.lastError(p) == nil ? Color.green : Color.orange).frame(width: 7, height: 7)
            }
        }
        .tag(p)
        .id("\(p.rawValue)-\(model.revision)")
    }

    @ViewBuilder private func detail(_ p: Platform) -> some View {
        let integration = Integrations.of(p)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                PlatformLogo(platform: p, size: 36)
                VStack(alignment: .leading) {
                    Text(p.name).font(.title2.bold())
                    Text("\(lib.count(.platform(p))) jeux dans la bibliothèque").foregroundStyle(.secondary)
                }
            }

            GroupBox("Sources") {
                VStack(alignment: .leading, spacing: 8) {
                    if let l = Integrations.local(p) { source("internaldrive", "Détection locale", l, active: true) }
                    if Integrations.galaxy.contains(p) {
                        source("g.circle", "GOG Galaxy", "Connecte \(p.name) dans GOG Galaxy (Paramètres → Intégrations) : ses jeux sont importés automatiquement.",
                               active: Paths.exists(GalaxyScanner.dbPath))
                    }
                    if let i = integration { source("network", "API", i.summary, active: i.isConnected) }
                    source("square.and.pencil", "Saisie manuelle", "Ajoute n'importe quel jeu à la main (bouton + → Saisir un jeu).", active: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }

            if let i = integration { apiBox(i) }

            Button { lib.newManual(platform: p) } label: {
                Label("Ajouter un jeu \(p.name) manuellement…", systemImage: "plus")
            }
        }
    }

    private func source(_ icon: String, _ title: String, _ text: String, active: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(active ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func apiBox(_ i: Integration) -> some View {
        GroupBox("Connexion API") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(i.steps.enumerated()), id: \.offset) { n, s in
                    Text("\(n + 1). \(s)").font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    ForEach(i.links, id: \.1) { l in
                        Button {
                            let target = l.1 == "ludotheque:nintendo-login" ? Integrations.nintendoLoginURL : l.1
                            if let u = URL(string: target) { NSWorkspace.shared.open(u) }
                        } label: { Label(l.0, systemImage: "arrow.up.right.square") }
                        .buttonStyle(.link)
                    }
                }
                Divider()
                ForEach(i.fields, id: \.key) { f in
                    LabeledContent(f.label) {
                        let b = Binding(get: { model.values[f.key] ?? "" }, set: { model.values[f.key] = $0 })
                        if f.file {
                            HStack {
                                Text(b.wrappedValue.isEmpty ? f.placeholder : b.wrappedValue)
                                    .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                                Spacer()
                                Button("Choisir…") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseDirectories = true
                                    panel.canChooseFiles = true
                                    if panel.runModal() == .OK, let u = panel.url { b.wrappedValue = u.path }
                                }
                            }
                        } else if f.secret { SecureField(f.label, text: b, prompt: Text(f.placeholder)).labelsHidden() }
                        else { TextField(f.label, text: b, prompt: Text(f.placeholder)).labelsHidden() }
                    }
                }
                status(i).id(model.revision)
                HStack {
                    Button {
                        model.save(i)
                        Task {
                            await lib.runSync([i])
                            model.load()
                            model.revision += 1
                        }
                    } label: { Label("Enregistrer et synchroniser", systemImage: "arrow.triangle.2.circlepath") }
                        .buttonStyle(.borderedProminent)
                        .disabled(lib.syncing.contains(i.platform))
                    if i.isConnected {
                        Button("Déconnecter", role: .destructive) {
                            i.disconnect()
                            model.load()
                            model.revision += 1
                            Task { await lib.refresh(sync: false) }
                        }
                    }
                    Spacer()
                    Text("Stocké dans le Trousseau macOS").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
    }

    @ViewBuilder private func status(_ i: Integration) -> some View {
        if lib.syncing.contains(i.platform) {
            Label("Synchronisation en cours…", systemImage: "hourglass").foregroundStyle(.secondary)
        } else if let e = Integrations.lastError(i.platform) {
            Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        } else if let d = Integrations.lastSync(i.platform) {
            Label("Synchronisé \(d.formatted(.relative(presentation: .named))) — \(ApiStore.load(i.platform).count) jeux. Resynchronisation auto toutes les 6 h.",
                  systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Label("Non connecté", systemImage: "circle.dashed").foregroundStyle(.secondary)
        }
    }
}
