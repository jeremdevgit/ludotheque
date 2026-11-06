// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI

enum Accent: String, CaseIterable, Identifiable {
    case blue, purple, pink, red, orange, yellow, green, teal, graphite
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .graphite: .gray
        }
    }
}

@MainActor
final class TransferModel: ObservableObject {
    @Published var format: DataTransfer.Format = .csv
    @Published var selection: DataTransfer.Selection = .all
    @Published var preview: DataTransfer.Preview?
    @Published var createMissing = true
    @Published var message: String?
}

struct OptionsView: View {
    @Environment(Library.self) var lib
    @StateObject private var transfer = TransferModel()
    @AppStorage("appearance") private var appearance = 0
    @AppStorage("accent") private var accent = Accent.blue.rawValue
    @AppStorage("tileWidth") private var tileWidth = 150.0
    @AppStorage("viewMode") private var viewMode = "grid"
    @AppStorage("startScope") private var startScope = "home"
    @AppStorage("refreshAtLaunch") private var refreshAtLaunch = false
    @AppStorage("refreshHours") private var refreshHours = 0
    @AppStorage("autoSyncAPIs") private var autoSync = true
    @AppStorage("groupDuplicates") private var groupDuplicates = true
    @AppStorage("playableOnlyInAll") private var playableOnlyInAll = false
    @AppStorage("hideNonGames") private var hideNonGames = true
    @AppStorage("defaultSort") private var defaultSort = SortOrder.title.rawValue
    @AppStorage("afterLaunch") private var afterLaunch = 0
    @AppStorage("trackPlaytime") private var trackPlaytime = true
    @AppStorage("notifications") private var notifications = true
    @AppStorage("menuBarExtra") private var menuBarExtra = true
    @AppStorage("hiddenSidebarPlatforms") private var hiddenPlatforms = ""
    @AppStorage("showAllPlatforms") private var showAllPlatforms = false

    @AppStorage("optionsTab") private var tab = "general"

    var body: some View {
        VStack(spacing: 0) {
            // One tab at a time: a single long form built ~100 native controls at once (0.7 s per visit).
            Picker("", selection: $tab) {
                Label("Général", systemImage: "gearshape").tag("general")
                Label("Bibliothèque", systemImage: "books.vertical").tag("library")
                Label("Données", systemImage: "externaldrive").tag("data")
                Label("Interface", systemImage: "paintbrush").tag("interface")
                Label("Jaquettes", systemImage: "square.grid.2x2").tag("tiles")
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 660).padding(.vertical, 10)
            switch tab {
            case "interface": CustomizationView(part: .interface)
            case "tiles": CustomizationView(part: .tiles)
            case "library": libraryTab
            case "data": dataTab
            default: general
            }
        }
    }

    private var general: some View {
        Form {
            Section("Apparence") {
                Picker("Thème", selection: $appearance) { Text("Système").tag(0); Text("Clair").tag(1); Text("Sombre").tag(2) }
                    .pickerStyle(.segmented)
                LanguePicker()
                LabeledContent("Couleur d'accent") {
                    HStack(spacing: 8) {
                        ForEach(Accent.allCases) { a in
                            Circle().fill(a.color).frame(width: 20, height: 20)
                                .overlay(Circle().stroke(Color.primary, lineWidth: accent == a.rawValue ? 2 : 0).padding(-3))
                                .onTapGesture { accent = a.rawValue }
                        }
                    }
                }
                LabeledContent("Taille des jaquettes") { Slider(value: $tileWidth, in: 110...240).frame(width: 220) }
                Picker("Affichage par défaut", selection: $viewMode) { Text("Grille").tag("grid"); Text("Liste").tag("list") }
            }

            Section("Démarrage et actualisation") {
                Picker("Vue à l'ouverture", selection: $startScope) {
                    Text("Accueil").tag("home"); Text("Tous les jeux").tag("all"); Text("Jouables").tag("playable")
                    Text("Installés").tag("installed"); Text("Récents").tag("recent"); Text("Favoris").tag("favorites")
                }
                Toggle("Tout actualiser au lancement", isOn: $refreshAtLaunch)
                Picker("Actualisation automatique", selection: $refreshHours) {
                    Text("Jamais").tag(0); Text("Toutes les heures").tag(1); Text("Toutes les 3 h").tag(3)
                    Text("Toutes les 6 h").tag(6); Text("Toutes les 12 h").tag(12); Text("Une fois par jour").tag(24)
                }
                Toggle("Synchroniser les plateformes connectées", isOn: $autoSync)
            }

            Section("Lancement des jeux") {
                Picker("Après le lancement d'un jeu", selection: $afterLaunch) {
                    Text("Ne rien faire").tag(0); Text("Réduire Ludothèque").tag(1); Text("Masquer Ludothèque").tag(2)
                }
                Toggle("Compteur de temps de jeu (mesure les sessions lancées depuis Ludothèque)", isOn: $trackPlaytime)
            }

            Section("Notifications et barre des menus") {
                Toggle("Notifications (jeux gratuits, promos de la liste de souhaits)", isOn: $notifications)
                    .onChange(of: notifications) { _, on in if on { Notifier.requestAuthorization() } }
                Toggle("Icône dans la barre des menus (lancement rapide)", isOn: $menuBarExtra)
            }

            Section("Raccourcis clavier") {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                    ForEach([("⌘R", String(localized: "Tout actualiser")), ("⌘N", String(localized: "Saisir un jeu")), ("⌘J", String(localized: "Jeu au hasard")), ("⌘1 … ⌘7", String(localized: "Vues de la bibliothèque")),
                             ("⌘0", String(localized: "Réinitialiser les filtres")), ("⇧⌘P", String(localized: "Gestion des plateformes")), ("⇧⌘T", String(localized: "Mode TV")),
                             ("⇧⌘I", String(localized: "Statistiques")), ("⌘,", String(localized: "Options"))], id: \.0) { k, v in
                        GridRow { Text(k).font(.system(.callout, design: .monospaced)); Text(v).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var libraryTab: some View {
        Form {
            Section("Bibliothèque") {
                Toggle("Regrouper le même jeu possédé sur plusieurs plateformes", isOn: $groupDuplicates)
                    .onChange(of: groupDuplicates) { _, _ in lib.reloadGrouping() }
                Toggle("« Tous les jeux » : n'afficher que les jeux jouables sur ce Mac", isOn: $playableOnlyInAll)
                Toggle("Masquer serveurs de test, éditeurs, bandes-son, démos et bêtas", isOn: $hideNonGames)
                    .onChange(of: hideNonGames) { _, _ in Task { await lib.refresh(sync: false) } }
                Toggle("Afficher les jeux masqués", isOn: Bindable(lib).showHidden)
                Picker("Tri par défaut", selection: $defaultSort) { ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0.rawValue) } }
                    .onChange(of: defaultSort) { _, v in lib.sort = SortOrder(rawValue: v) ?? .title }
            }

            Section("Barre latérale") {
                Text("Sections, éléments, ordre et taille de la barre latérale : onglet « Interface » ci-dessus.").font(.caption).foregroundStyle(.secondary)
                Group {
                    Toggle("Afficher aussi les plateformes sans jeu", isOn: $showAllPlatforms)
                    HStack {
                        Text("Plateformes affichées").font(.callout.weight(.medium))
                        Spacer()
                        Button("Tout afficher") { hiddenPlatforms = "" }.controlSize(.small)
                        Button("Tout masquer") {
                            hiddenPlatforms = Platform.allCases.filter { $0 != .other }.map(\.rawValue).joined(separator: ",")
                        }.controlSize(.small)
                    }
                    FixedColumns(items: Platform.allCases.filter { $0 != .other }, columns: 3) { p in
                            Toggle(isOn: Binding(get: { !SidebarPrefs.hidden(hiddenPlatforms).contains(p) },
                                                 set: { SidebarPrefs.setHidden(p, !$0); hiddenPlatforms = UserDefaults.standard.string(forKey: SidebarPrefs.key) ?? "" })) {
                                HStack(spacing: 6) {
                                    PlatformLogo(platform: p, size: 16)
                                    Text(p.name).lineLimit(1)
                                    let n = lib.count(.platform(p))
                                    if n > 0 { Text("\(n)").font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                            .toggleStyle(.checkbox)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var dataTab: some View {
        Form {
            Section("Importer / exporter mes jeux") {
                HStack {
                    Picker("Exporter", selection: $transfer.selection) { ForEach(DataTransfer.Selection.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("au format", selection: $transfer.format) { ForEach(DataTransfer.Format.allCases) { Text($0.rawValue).tag($0) } }
                        .frame(width: 180)
                    Button("Exporter…") { exportGames() }
                }
                HStack {
                    Button("Importer un fichier (CSV, JSON)…") { importGames() }
                    Text("Compatible avec les exports de Ludothèque, Playnite, Backloggd, HowLongToBeat ou un tableur (colonnes Titre, Plateforme, Statut, Note, Temps de jeu, Tags…).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let p = transfer.preview {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(p.rows.count) jeux lus : \(p.matched) déjà dans ta bibliothèque, \(p.new) nouveaux.").font(.callout.weight(.medium))
                        Toggle("Ajouter les \(p.new) jeux absents comme jeux manuels", isOn: $transfer.createMissing)
                        HStack {
                            Button("Importer") {
                                transfer.message = DataTransfer.apply(p, createMissing: transfer.createMissing, lib: lib)
                                transfer.preview = nil
                            }.buttonStyle(.borderedProminent)
                            Button("Annuler") { transfer.preview = nil }
                        }
                    }
                    .padding(8).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                if let m = transfer.message { Label(m, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }

            Section("Sauvegarde et maintenance") {
                HStack {
                    Button("Sauvegarder toutes mes données…") { lib.backup() }
                    Button("Restaurer une sauvegarde…") { lib.restore() }
                }
                Text("Statuts, notes, tags, temps mesuré, jeux manuels, vues, émulateurs, profil. Les identifiants des plateformes restent dans le Trousseau.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Ouvrir le dossier des données") { NSWorkspace.shared.open(Paths.support) }
                    Button("Vider le cache des images") {
                        try? FileManager.default.removeItem(at: Paths.caches)
                        _ = Paths.dir(Paths.caches)
                        lib.flash(String(localized: "Cache des images vidé"))
                    }
                    Button("Retélécharger les métadonnées") {
                        for f in ["gamesdb-cache.json", "gamesdb-details.json", "requirements.json"] {
                            try? FileManager.default.removeItem(at: Paths.support.appendingPathComponent(f))
                        }
                        Task { await lib.refreshAll(manual: true) }
                    }
                }
            }

            Section("Vitesse de l'app sur ce Mac") {
                let p = PerfMonitor.shared.summary()
                LabeledContent("Démarrage", value: p.launches == 0 ? String(localized: "pas encore mesuré")
                               : String(localized: "\(p.lastLaunchMs) ms la dernière fois · médiane \(p.medianLaunchMs) ms (\(p.launches) lancements)"))
                LabeledContent("Blocages de l'interface (7 jours)", value: p.hangs7d == 0 ? "aucun"
                               : String(localized: "\(p.hangs7d) · le plus long \(p.worstHangMs) ms"))
                Text("Mesuré et gardé sur ce Mac uniquement, rien n'est envoyé. Un blocage = l'interface ne répond plus pendant plus de 250 ms.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Ouvrir le journal") { NSWorkspace.shared.activateFileViewerSelecting([PerfMonitor.shared.logURL]) }
                    Button("Effacer les mesures") { PerfMonitor.shared.clear(); lib.flash(String(localized: "Mesures effacées")) }
                }
            }

            Section("Confidentialité") {
                Text("Tout reste sur ce Mac. Ludothèque contacte uniquement les plateformes que tu connectes et des services publics de métadonnées (GOG GamesDB, PCGamingWiki, Steam, CheapShark, GamerPower, libretro, icônes Google).")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("À propos") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
                LabeledContent("Jeux", value: "\(lib.groups.count)")
                LabeledContent("Créé par") { Link(Author.name, destination: Author.profile) }
                LabeledContent("Licence", value: String(localized: "GPL-3.0-or-later (logiciel libre)"))
            }

            Section("Mes autres logiciels") {
                ForEach(Author.apps) { app in
                    LabeledContent {
                        Link("Télécharger", destination: app.url)
                    } label: {
                        Text(app.name)
                        Text("\(app.platform) — \(app.summary)")
                    }
                }
                Link("Tous mes logiciels sur GitHub", destination: Author.profile)
            }
        }
        .formStyle(.grouped)
    }

    private func exportGames() {
        guard let d = DataTransfer.export(lib, transfer.selection, transfer.format) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [transfer.format.type]
        panel.nameFieldStringValue = "Ma ludothèque"
        guard panel.runModal() == .OK, let u = panel.url else { return }
        try? d.write(to: u)
        transfer.message = String(localized: "Export enregistré (\(transfer.format.rawValue))")
    }

    private func importGames() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .json, .plainText]
        guard panel.runModal() == .OK, let u = panel.url else { return }
        transfer.message = nil
        if let p = DataTransfer.read(u, lib), !p.rows.isEmpty { transfer.preview = p }
        else { transfer.message = String(localized: "Aucun jeu reconnu dans ce fichier (il faut au moins une colonne Titre / Title / Name).") }
    }
}
