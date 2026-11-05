// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI

@MainActor
final class EmulatorHubModel: ObservableObject {
    @Published var configured: [Emulator] = Emulation.load()
    @Published var installed: [String: URL] = [:]   // preset name → app

    func reload() {
        configured = Emulation.load()
        var map = [String: URL]()
        for p in Emulation.presets { if let u = p.installedURL { map[p.name] = u } }
        installed = map
    }

    func profile(_ p: EmulatorPreset) -> Emulator? {
        let app = installed[p.name]?.path
        return configured.first { e in e.name == p.name || (app != nil && e.appPath == app) }
    }

    /// Adds the emulator to Ludothèque (asks for the app if not found, then the games folder).
    func add(_ p: EmulatorPreset) -> Bool {
        var app = installed[p.name]
        if app == nil {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.application]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.message = "Où se trouve \(p.name) ? (télécharge-le d'abord depuis son site officiel)"
            guard panel.runModal() == .OK, let u = panel.url else { return false }
            app = u
        }
        var e = Emulator(name: p.name, appPath: app!.path, system: p.system, extensions: p.extensions, arguments: p.arguments)
        e.romFolder = pickFolder(for: p.name) ?? ""
        configured.append(e)
        Emulation.save(configured)
        return true
    }

    func remove(_ p: EmulatorPreset) {
        guard let e = profile(p) else { return }
        configured.removeAll { $0.id == e.id }
        Emulation.save(configured)
    }

    func changeFolder(_ p: EmulatorPreset) {
        guard let e = profile(p), let f = pickFolder(for: p.name), let i = configured.firstIndex(where: { $0.id == e.id }) else { return }
        configured[i].romFolder = f
        Emulation.save(configured)
    }

    private func pickFolder(for name: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Dossier contenant tes jeux pour \(name) (facultatif — tu pourras le choisir plus tard)"
        panel.prompt = "Choisir"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

struct EmulatorHubView: View {
    @Environment(\.stableWidth) private var stableWidth
    @Environment(Library.self) var lib
    @StateObject private var model = EmulatorHubModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Émulateurs recommandés").font(.largeTitle.bold())
                    Text("Télécharge les émulateurs depuis leur site officiel, puis active ceux que tu veux utiliser : leurs jeux apparaissent dans ta bibliothèque et se lancent directement depuis Ludothèque, avec suivi du temps de jeu.")
                        .foregroundStyle(.secondary)
                    Label("BIOS, firmwares, clés et jeux doivent provenir de tes propres consoles et disques. Ludothèque n'en fournit ni n'en télécharge aucun.",
                          systemImage: "checkmark.shield")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(EmulatorPreset.Family.allCases, id: \.self) { family in
                    let items = Emulation.presets.filter { $0.family == family }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(family.rawValue).font(.title2.bold())
                            LazyVGrid(columns: stableColumns(stableWidth, min: 340, spacing: 14, padding: 48), spacing: 14) {
                                ForEach(items, id: \.name) { card($0) }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .onAppear { model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.reload() }
    }

    private func card(_ p: EmulatorPreset) -> some View {
        let app = model.installed[p.name]
        let profile = model.profile(p)
        let count = profile.map { e in lib.games.filter { $0.launchURL?.hasPrefix("emu:\(e.id)|") == true }.count } ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let app { Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable() }
                    else { Image(systemName: p.family == .ios ? "iphone" : "arcade.stick.console").resizable().scaledToFit().padding(8).foregroundStyle(.secondary) }
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(p.name).font(.headline)
                        status(p, app: app)
                    }
                    Text(p.consoles).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if p.addable && p.availableOnMac {
                    Toggle("Ajouter à Ludothèque", isOn: Binding(
                        get: { profile != nil },
                        set: { on in
                            if on { if model.add(p) { Task { await lib.refresh(sync: false) } } }
                            else { model.remove(p); Task { await lib.refresh(sync: false) } }
                        }))
                    .toggleStyle(.switch).labelsHidden()
                    .help(profile == nil ? "Ajouter cet émulateur à Ludothèque" : "Retirer cet émulateur de Ludothèque")
                }
            }
            Text(p.summary).font(.callout).fixedSize(horizontal: false, vertical: true)
            if let needs = p.needs {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle").foregroundStyle(.orange)
                    Text(needs).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let l = p.needsLink, let u = URL(string: l) { Link("Lien", destination: u).font(.caption) }
                }
            }
            if let profile {
                HStack(spacing: 6) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(profile.romFolder.isEmpty ? "Aucun dossier de jeux" : profile.romFolder)
                        .font(.caption).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(count) jeu\(count > 1 ? "x" : "")").font(.caption.weight(.semibold))
                    Button("Dossier…") { model.changeFolder(p); Task { await lib.refresh(sync: false) } }.controlSize(.small)
                }
            }
            HStack {
                if let u = URL(string: p.website) { Link(destination: u) { Label("Site officiel", systemImage: "safari") } }
                if p.availableOnMac, let u = URL(string: p.download) {
                    Link(destination: u) { Label(app == nil ? "Télécharger" : "Mettre à jour", systemImage: "arrow.down.circle") }
                }
                Spacer()
                if let app {
                    Button("Ouvrir") { NSWorkspace.shared.openApplication(at: app, configuration: .init()) }.controlSize(.small)
                }
            }
            .font(.callout)
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(profile != nil ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1.5))
        .opacity(p.availableOnMac ? 1 : 0.6)
    }

    @ViewBuilder private func status(_ p: EmulatorPreset, app: URL?) -> some View {
        if !p.availableOnMac {
            badge("Pas sur Mac", .red)
        } else if app != nil {
            badge("Installé", .green)
        } else {
            badge("Non installé", .secondary)
        }
    }

    private func badge(_ t: String, _ c: Color) -> some View {
        Text(t).font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2)
            .background(c.opacity(0.18), in: Capsule()).foregroundStyle(c)
    }
}
