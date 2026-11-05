// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI

@MainActor
final class UninstallModel: ObservableObject {
    @Published var plan: Uninstaller.Plan?
    @Published var full = false
    @Published var selected: Set<String> = []
    @Published var working = false

    func load(_ g: Game) async {
        var p = await Task.detached { Uninstaller.plan(for: g) }.value
        p.items = await Task.detached { p.items.map { var i = $0; i.size = Uninstaller.size(i.url); return i } }.value
        plan = p
        applyMode()
    }

    /// "Keep configuration" = the game and its caches; "complete" = everything found.
    func applyMode() {
        guard let p = plan else { return }
        selected = Set(p.items.filter { !$0.uncertain && (full || $0.kind != .config) }.map(\.id))
    }
}

struct UninstallSheet: View {
    @Environment(Library.self) var lib
    let game: Game
    @StateObject private var model = UninstallModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                CoverImage(game: game).frame(width: 48, height: 72).clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading) {
                    Text("Désinstaller \(game.title)").font(.title2.bold())
                    HStack(spacing: 4) { PlatformLogo(platform: game.platform, size: 14); Text(game.platform.name) }.font(.callout).foregroundStyle(.secondary)
                }
            }

            Picker("", selection: $model.full) {
                Text("Garder la configuration").tag(false)
                Text("Désinstaller complètement").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden()
            .onChange(of: model.full) { _, _ in model.applyMode() }
            Text(model.full
                 ? "Le jeu et tous ses fichiers associés (sauvegardes locales, réglages, caches) seront supprimés."
                 : "Le jeu est supprimé, mais tes sauvegardes et réglages sont conservés pour une réinstallation future.")
                .font(.callout).foregroundStyle(.secondary)

            if let plan = model.plan {
                if case .launcher(let name, _) = plan.method {
                    Label("Le jeu lui-même sera désinstallé par \(name), pour que le launcher reste à jour.", systemImage: "arrow.up.forward.app")
                        .font(.callout).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                if plan.items.isEmpty {
                    Text("Aucun fichier associé trouvé sur ce Mac.").foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach([Uninstaller.Kind.game, .config, .cache], id: \.self) { kind in
                            let items = plan.items.filter { $0.kind == kind }
                            if !items.isEmpty {
                                Section(kind.rawValue) {
                                    ForEach(items) { i in
                                        Toggle(isOn: Binding(get: { model.selected.contains(i.id) },
                                                             set: { if $0 { model.selected.insert(i.id) } else { model.selected.remove(i.id) } })) {
                                            HStack {
                                                Text(i.url.path.replacingOccurrences(of: Paths.home.path, with: "~"))
                                                    .font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                                                if i.uncertain {
                                                    Text("à vérifier").font(.caption2.bold()).foregroundStyle(.orange)
                                                        .help("Trouvé seulement grâce au nom du jeu : vérifie qu'il lui appartient avant de cocher.")
                                                }
                                                Spacer()
                                                Text(ByteCountFormatter.string(fromByteCount: i.size, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        .contextMenu { Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([i.url]) } }
                                    }
                                }
                            }
                        }
                    }
                    .frame(minHeight: 180)
                    let total = plan.items.filter { model.selected.contains($0.id) }.map(\.size).reduce(0, +)
                    Text("\(model.selected.count) élément(s) · \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)) libérés — tout est placé dans la Corbeille (récupérable).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ProgressView("Recherche des fichiers du jeu…").frame(maxWidth: .infinity, minHeight: 120)
            }

            HStack {
                Spacer()
                Button("Annuler") { lib.uninstalling = nil }.keyboardShortcut(.cancelAction)
                Button(model.full ? "Tout désinstaller" : "Désinstaller", role: .destructive) { run() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.plan == nil || model.working || (model.selected.isEmpty && !isLauncher))
            }
        }
        .padding(20)
        .frame(width: 620, height: 520)
        .task { await model.load(game) }
    }

    private var isLauncher: Bool {
        if case .launcher = model.plan?.method { return true }
        return false
    }

    private func run() {
        guard let plan = model.plan else { return }
        model.working = true
        if case .launcher(_, let url) = plan.method { NSWorkspace.shared.open(url) }
        let failed = Uninstaller.trash(plan.items.filter { model.selected.contains($0.id) })
        lib.uninstalling = nil
        lib.flash(failed.isEmpty ? "\(game.title) désinstallé — fichiers placés dans la Corbeille" : "\(failed.count) élément(s) n'ont pas pu être supprimés")
        Task { try? await Task.sleep(for: .seconds(2)); await lib.refresh(sync: false) }
    }
}
