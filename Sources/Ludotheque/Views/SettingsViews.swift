// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI

// MARK: - Emulators

@MainActor
final class EmulatorsModel: ObservableObject {
    @Published var list: [Emulator] = Emulation.load()
    @Published var selection: String?

    func save() { Emulation.save(list) }

    func detect() -> Int {
        let found = Emulation.detect(existing: list)
        list += found
        save()
        if selection == nil { selection = list.first?.id }
        return found.count
    }

    func add(_ preset: EmulatorPreset?) {
        let e = Emulator(name: preset?.name ?? String(localized: "Nouvel émulateur"), appPath: "", system: preset?.system ?? "",
                         extensions: preset?.extensions ?? [], arguments: preset?.arguments ?? "{rom}")
        list.append(e)
        selection = e.id
        save()
    }

    func remove(_ id: String) {
        list.removeAll { $0.id == id }
        selection = list.first?.id
        save()
    }
}

struct EmulatorsView: View {
    @Environment(Library.self) var lib
    @StateObject private var model = EmulatorsModel()

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $model.selection) {
                    ForEach(model.list) { e in
                        HStack {
                            if e.appExists { Image(nsImage: NSWorkspace.shared.icon(forFile: e.appPath)).resizable().frame(width: 18, height: 18) }
                            else { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
                            Text(e.name)
                        }.tag(e.id)
                    }
                }
                Divider()
                HStack {
                    Menu {
                        Button("Vide") { model.add(nil) }
                        Divider()
                        ForEach(Emulation.presets, id: \.name) { p in Button(p.name) { model.add(p) } }
                    } label: { Image(systemName: "plus") }.menuStyle(.borderlessButton).frame(width: 30)
                    Button { if let s = model.selection { model.remove(s) } } label: { Image(systemName: "minus") }
                        .buttonStyle(.borderless).disabled(model.selection == nil)
                    Spacer()
                    Button("Détecter") {
                        let n = model.detect()
                        lib.flash(n == 0 ? String(localized: "Aucun nouvel émulateur trouvé") : String(localized: "\(n) émulateur(s) ajouté(s)"))
                    }.controlSize(.small)
                }.padding(6)
            }
            .frame(width: 220)
            Divider()
            if let i = model.list.firstIndex(where: { $0.id == model.selection }) {
                editor($model.list[i]).padding(20)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "arcade.stick.console").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Ajoute un émulateur pour importer tes ROM (Nintendo, PlayStation, Sega…).")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("Détecter les émulateurs installés") { _ = model.detect() }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            }
        }
    }

    private func editor(_ e: Binding<Emulator>) -> some View {
        Form {
            TextField("Nom", text: e.name)
            LabeledContent("Application") {
                HStack {
                    Text(e.wrappedValue.appPath.isEmpty ? String(localized: "Aucune") : e.wrappedValue.appPath).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Button("Choisir…") { if let p = pick(app: true) { e.wrappedValue.appPath = p } }
                }
            }
            Picker("Console", selection: e.system) {
                Text("Selon l'extension du fichier").tag("")
                ForEach(Emulation.systems.keys.sorted(), id: \.self) { k in Text(Emulation.systems[k]!.name).tag(k) }
            }
            LabeledContent("Dossier des ROM") {
                HStack {
                    Text(e.wrappedValue.romFolder.isEmpty ? String(localized: "Aucun") : e.wrappedValue.romFolder).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Button("Choisir…") { if let p = pick(app: false) { e.wrappedValue.romFolder = p } }
                }
            }
            TextField("Extensions", text: Binding(get: { e.wrappedValue.extensions.joined(separator: ", ") },
                                                  set: { e.wrappedValue.extensions = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty } }),
                      prompt: Text("nsp, xci"))
            TextField("Arguments", text: e.arguments, prompt: Text("{rom}"))
            Text("{rom} est remplacé par le chemin du jeu. « {rom} » seul ouvre simplement le fichier avec l'émulateur.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Enregistrer et importer les ROM") {
                    model.save()
                    Task { await lib.refresh(sync: false) }
                }.buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .onChange(of: e.wrappedValue) { _, _ in model.save() }
    }

    private func pick(app: Bool) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = !app
        panel.canChooseFiles = app
        if app { panel.allowedContentTypes = [.application]; panel.directoryURL = URL(fileURLWithPath: "/Applications") }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

struct SettingsView: View {
    @Environment(Library.self) var lib

    var body: some View {
        TabView {
            OptionsView().tabItem { Label("Options", systemImage: "gearshape") }
            EmulatorsView().tabItem { Label("Émulateurs (avancé)", systemImage: "arcade.stick.console") }
        }
        .frame(width: 780, height: 620)
    }
}
