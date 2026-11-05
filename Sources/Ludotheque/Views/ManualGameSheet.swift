// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ManualForm: ObservableObject {
    @Published var game: ManualGame
    @Published var hits: [CoverSearch.Hit] = []
    @Published var searching = false

    init(_ g: ManualGame) { game = g }

    func search() async {
        searching = true
        hits = await CoverSearch.search(game.title)
        searching = false
    }

    func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let u = panel.url else { return }
        game.target = u.path
        if game.title.isEmpty { game.title = Bundle2.displayName(u) }
    }

    func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let u = panel.url else { return }
        // Copy so the cover survives the original being moved.
        let dest = Paths.userCovers.appendingPathComponent("\(game.id).\(u.pathExtension)")
        try? FileManager.default.removeItem(at: dest)
        if (try? FileManager.default.copyItem(at: u, to: dest)) != nil { game.coverURL = dest.absoluteString + "?v=\(Int(Date().timeIntervalSince1970))" }
    }
}

struct ManualGameSheet: View {
    @Environment(Library.self) var lib
    @StateObject private var form: ManualForm
    let isNew: Bool

    init(game: ManualGame, isNew: Bool) {
        _form = StateObject(wrappedValue: ManualForm(game))
        self.isNew = isNew
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Jeu") {
                    TextField("Titre", text: $form.game.title, prompt: Text("Nom du jeu"))
                    Picker("Plateforme", selection: $form.game.platform) {
                        ForEach(Platform.allCases.filter { $0 != .other }) { p in Text(p.name).tag(p) }
                    }
                    Stepper("Temps de jeu : \(form.game.playtimeHours) h", value: $form.game.playtimeHours, in: 0...10000, step: 1)
                }
                Section("Lancement") {
                    Picker("Mode", selection: $form.game.mode) {
                        ForEach(ManualGame.Mode.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                    switch form.game.mode {
                    case .none:
                        Toggle("Compatible Mac", isOn: $form.game.macNative)
                        Text("Le jeu est seulement répertorié (copie physique, console, autre PC…).").font(.caption).foregroundStyle(.secondary)
                    case .app:
                        HStack {
                            Text(form.game.target.isEmpty ? "Aucune application choisie" : form.game.target)
                                .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                            Spacer()
                            Button("Choisir…") { form.chooseApp() }
                        }
                    case .url:
                        TextField("URL", text: $form.game.target, prompt: Text("steam://rungameid/…, heroic://…, https://…"))
                        Toggle("Installé sur ce Mac", isOn: $form.game.installed)
                        Toggle("Compatible Mac", isOn: $form.game.macNative)
                    case .cloud:
                        TextField("Lien de streaming", text: $form.game.target,
                                  prompt: Text("https://play.geforcenow.com/…, https://www.xbox.com/play/…"))
                    }
                }
                Section("Jaquette") {
                    HStack(alignment: .top, spacing: 14) {
                        CoverImage(game: form.game.game())
                            .frame(width: 90, height: 135)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                Task { await form.search() }
                            } label: {
                                Label(form.searching ? "Recherche…" : "Chercher la jaquette en ligne", systemImage: "magnifyingglass")
                            }.disabled(form.game.title.isEmpty || form.searching)
                            Button { form.chooseImage() } label: { Label("Choisir une image…", systemImage: "photo") }
                            TextField("URL de l'image", text: $form.game.coverURL, prompt: Text("https://…"))
                        }
                    }
                    if !form.hits.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) {
                                ForEach(form.hits) { h in
                                    VStack(spacing: 4) {
                                        CoverImage(game: Game(id: "hit_\(h.id)", platform: .steam, externalId: h.id, title: h.name,
                                                              coverURL: h.cover, altCoverURL: h.alt))
                                            .frame(width: 70, height: 105)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: form.game.coverURL == h.cover ? 3 : 0))
                                        Text(h.name).font(.caption2).lineLimit(2).frame(width: 70)
                                    }
                                    .onTapGesture { form.game.coverURL = h.cover }
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                }
                Section("Autres") {
                    TextField("Page du jeu", text: $form.game.storeURL, prompt: Text("https://… (facultatif)"))
                }
            }
            .formStyle(.grouped)

            HStack {
                if !isNew {
                    Button("Supprimer", role: .destructive) { lib.deleteManual(form.game.id) }
                }
                Spacer()
                Button("Annuler") { lib.editing = nil }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Ajouter" : "Enregistrer") { lib.saveManual(form.game) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(form.game.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 560, height: 680)
    }
}
