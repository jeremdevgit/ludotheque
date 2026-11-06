// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation
import SwiftUI

/// Everything that can be refreshed, run only when the user asks (manual mode by default).
enum RefreshOp: String, CaseIterable, Identifiable {
    case library, platforms, freeGames, wishlist, keys, achievements, performance, genres, news, anticheat, dlcIndex

    var id: String { rawValue }
    var title: String {
        switch self {
        case .library: String(localized: "Bibliothèque locale")
        case .platforms: String(localized: "Plateformes connectées")
        case .freeGames: String(localized: "Jeux et objets gratuits")
        case .wishlist: String(localized: "Prix de la liste de souhaits")
        case .keys: String(localized: "Prix des clés suivies (DLCompare)")
        case .achievements: String(localized: "Succès")
        case .performance: String(localized: "Performances des jeux jouables")
        case .genres: String(localized: "Genres et années (statistiques)")
        case .news: String(localized: "Actualités des jeux")
        case .anticheat: String(localized: "Base anti-triche (jeux Windows)")
        case .dlcIndex: String(localized: "Catalogue DLCompare")
        }
    }
    var detail: String {
        switch self {
        case .library: String(localized: "Jeux installés et bibliothèques locales (Steam, Epic, GOG Galaxy, Battle.net, apps Mac, émulateurs…), titres et jaquettes.")
        case .platforms: String(localized: "Synchronise les comptes connectés dans Gestion des plateformes (Steam, Epic, GOG, Xbox, PlayStation…).")
        case .freeGames: String(localized: "Jeux, DLC et objets gratuits à récupérer (GamerPower).")
        case .wishlist: String(localized: "Prix Steam et meilleures offres (CheapShark) des jeux de ta liste de souhaits.")
        case .keys: String(localized: "Les 10 clés CD les moins chères des jeux que tu suis.")
        case .achievements: String(localized: "Steam, Xbox et PlayStation (comptes connectés). Peut être long.")
        case .performance: String(localized: "Configurations requises des jeux jouables pas encore analysés (150 par passage).")
        case .genres: String(localized: "Genres et années de sortie de tes 150 jeux les plus joués.")
        case .news: String(localized: "Annonces et notes de patch de tes jeux récents (Steam).")
        case .anticheat: String(localized: "Compatibilité anti-triche (AreWeAntiCheatYet), pour l'onglet Jeux Windows.")
        case .dlcIndex: String(localized: "Liste des jeux DLCompare, nécessaire à la recherche de prix (≈ 5 Mo).")
        }
    }
    var symbol: String {
        switch self {
        case .library: "internaldrive.fill"
        case .platforms: "person.crop.circle.badge.checkmark"
        case .freeGames: "gift.fill"
        case .wishlist: "heart.fill"
        case .keys: "tag.fill"
        case .achievements: "trophy.fill"
        case .performance: "gauge.with.dots.needle.67percent"
        case .genres: "chart.bar.xaxis"
        case .news: "newspaper.fill"
        case .anticheat: "shield.lefthalf.filled"
        case .dlcIndex: "list.bullet.rectangle"
        }
    }
    /// Included in "Tout actualiser" unless the user unticks it.
    var defaultInAll: Bool { ![.achievements, .genres, .dlcIndex].contains(self) }
}

@MainActor
final class RefreshCenter: ObservableObject {
    static let shared = RefreshCenter()
    @Published private(set) var running: Set<RefreshOp> = []
    @Published private(set) var lastRun: [RefreshOp: Date] = [:]
    @Published private(set) var lastMessage: [RefreshOp: String] = [:]

    private init() {
        for op in RefreshOp.allCases { lastRun[op] = UserDefaults.standard.object(forKey: "refresh.\(op.rawValue).date") as? Date }
    }

    func included(_ op: RefreshOp) -> Bool { UserDefaults.standard.object(forKey: "refresh.\(op.rawValue).inAll") as? Bool ?? op.defaultInAll }
    func setIncluded(_ op: RefreshOp, _ v: Bool) { UserDefaults.standard.set(v, forKey: "refresh.\(op.rawValue).inAll"); objectWillChange.send() }

    /// Runs one operation (no-op if it is already running).
    func run(_ op: RefreshOp, _ lib: Library) async {
        guard !running.contains(op) else { return }
        running.insert(op)
        defer {
            running.remove(op)
            lastRun[op] = Date()
            UserDefaults.standard.set(Date(), forKey: "refresh.\(op.rawValue).date")
        }
        var msg = String(localized: "Terminé")
        switch op {
        case .library:
            await lib.refresh(sync: false)
            msg = String(localized: "\(lib.groups.count) jeux")
        case .platforms:
            let connected = Integrations.all.filter(\.isConnected)
            if connected.isEmpty { msg = String(localized: "Aucun compte connecté") } else { await lib.runSync(connected); msg = String(localized: "\(connected.count) plateforme(s) synchronisée(s)") }
        case .freeGames:
            await FreeGamesStore.shared.refresh()
            msg = String(localized: "\(FreeGamesStore.shared.active.count) jeux · \(FreeGamesStore.shared.activeLoot.count) objets")
        case .wishlist:
            await WishlistStore.shared.refresh()
            msg = String(localized: "\(WishlistStore.shared.items.count) jeux suivis")
        case .keys:
            await DLCompareStore.shared.refreshTracked()
            msg = String(localized: "\(DLCompareStore.shared.tracked.count) jeux suivis")
        case .achievements:
            if AchievementHub.shared.connected.isEmpty { msg = String(localized: "Aucun compte connecté (Steam, Xbox, PlayStation)") }
            else { await AchievementHub.shared.refresh(lib, replace: false); msg = String(localized: "\(AchievementHub.shared.items.count) jeux") }
        case .performance:
            let missing = lib.groups.filter { g in g.games.contains { $0.launchKind == .installed || $0.launchKind == .installable } && PerfStore.shared.requirements(g) == nil }
            await PerfStore.shared.analyze(Array(missing.prefix(150)))
            msg = missing.isEmpty ? String(localized: "Tout est déjà analysé") : String(localized: "\(min(150, missing.count)) jeux analysés")
        case .genres:
            await StatsModel().fetchDetails(lib)
        case .news:
            await NewsStore.shared.refresh(lib)
            msg = String(localized: "\(NewsStore.shared.items.count) actualités")
        case .anticheat:
            await WindowsGaming.shared.loadAntiCheat(force: true)
            msg = String(localized: "\(WindowsGaming.shared.antiCheat.count) jeux référencés")
        case .dlcIndex:
            await DLCompareStore.shared.ensureIndex(force: true)
            msg = String(localized: "\(DLCompareStore.shared.indexCount) jeux")
        }
        lastMessage[op] = msg
    }

    /// "Tout actualiser": the selected operations, the cheap ones first.
    func runAll(_ lib: Library, only: [RefreshOp]? = nil) async {
        let ops = only ?? RefreshOp.allCases.filter(included)
        TaskCenter.shared.begin("refreshAll", String(localized: "Actualisation"))
        defer { TaskCenter.shared.end("refreshAll") }
        for (i, op) in ops.enumerated() {
            TaskCenter.shared.progress("refreshAll", i, ops.count, op.title)
            await run(op, lib)
        }
        lib.markFullRefresh()
        lib.flash(String(localized: "Actualisation terminée"))
    }
}

/// Cached news of recently played games (refreshed on demand).
@MainActor
final class NewsStore: ObservableObject {
    static let shared = NewsStore()
    @Published private(set) var items: [NewsItem] = []

    func refresh(_ lib: Library) async {
        let recent = lib.groups.filter { lib.lastPlayed($0) != nil && News.steamId($0) != nil }
            .sorted { lib.lastPlayed($0)! > lib.lastPlayed($1)! }.prefix(8)
        var out = [NewsItem]()
        for g in recent { out += await News.fetch(appId: News.steamId(g)!, game: lib.title(g), count: 2) }
        items = out.sorted { $0.date > $1.date }
    }
}

// MARK: - Top progress bar (always visible, fixed height: never shifts the content)

struct TopProgressBar: View {
    @Environment(Library.self) var lib
    @ObservedObject private var center = TaskCenter.shared
    @StateObject private var ui = TopBarState()

    var body: some View {
        HStack(spacing: 10) {
            if let job = center.jobs.first(where: { $0.total > 0 }) ?? center.jobs.first {
                ProgressView().controlSize(.mini).opacity(job.fraction == nil ? 1 : 0).frame(width: 12)
                Text(job.title).font(.caption.weight(.semibold)).lineLimit(1)
                if !job.detail.isEmpty { Text(job.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                if let f = job.fraction {
                    ProgressView(value: f).progressViewStyle(.linear).frame(maxWidth: 220)
                    Text("\(job.done)/\(job.total)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                } else {
                    Spacer(minLength: 0)
                }
                if center.jobs.count > 1 {
                    Button("+\(center.jobs.count - 1)") { ui.shown.toggle() }.buttonStyle(.borderless).font(.caption)
                        .popover(isPresented: $ui.shown) { TaskList().frame(width: 420) }
                }
                Spacer(minLength: 0)
                if center.isRunning(job.id) {
                    Button { center.cancel(job.id) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help("Arrêter")
                }
            } else {
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary).font(.caption)
                Text(lib.lastFullRefresh.map { "Prêt · actualisé \($0.formatted(.relative(presentation: .named)))" } ?? "Prêt · mode manuel")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            Button { lib.scope = .refresh } label: { Label("Actualisations", systemImage: "arrow.triangle.2.circlepath").font(.caption) }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

@MainActor
private final class TopBarState: ObservableObject { @Published var shown = false }

// MARK: - "Actualisations" tab

struct RefreshView: View {
    @Environment(Library.self) var lib
    @ObservedObject private var center = RefreshCenter.shared
    @ObservedObject private var tasks = TaskCenter.shared
    @AppStorage("refreshAtLaunch") private var atLaunch = false
    @AppStorage("refreshHours") private var hours = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Actualisations").font(.largeTitle.bold())
                        Text("Rien ne se lance tout seul : choisis ce que tu veux actualiser. La progression s'affiche dans la barre en haut.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    let n = RefreshOp.allCases.filter(center.included).count
                    Button { Task { await center.runAll(lib) } } label: {
                        Label("Tout actualiser (\(n))", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!center.running.isEmpty || n == 0)
                }

                VStack(spacing: 8) {
                    ForEach(RefreshOp.allCases) { op in row(op) }
                }

                GroupBox("Automatisation (facultatif)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Lancer « Tout actualiser » à l'ouverture de l'app", isOn: $atLaunch)
                        Picker("Répéter automatiquement", selection: $hours) {
                            Text("Jamais (manuel)").tag(0); Text("Toutes les 3 h").tag(3); Text("Toutes les 6 h").tag(6)
                            Text("Toutes les 12 h").tag(12); Text("Une fois par jour").tag(24)
                        }.frame(width: 320)
                    }
                    .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
    }

    private func row(_ op: RefreshOp) -> some View {
        let isRunning = center.running.contains(op)
        return HStack(spacing: 12) {
            Image(systemName: op.symbol).font(.title3).foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(op.title).font(.callout.weight(.semibold))
                Text(op.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if isRunning {
                        ProgressView().controlSize(.mini)
                        Text("En cours…").font(.caption2).foregroundStyle(.secondary)
                    } else if let d = center.lastRun[op] {
                        Text("Dernière fois \(d.formatted(.relative(presentation: .named)))\(center.lastMessage[op].map { " · \($0)" } ?? "")")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("Jamais lancé").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Toggle("Inclure", isOn: Binding(get: { center.included(op) }, set: { center.setIncluded(op, $0) }))
                .toggleStyle(.checkbox).help("Inclure dans « Tout actualiser »")
            Button(isRunning ? "En cours" : "Lancer") { Task { await center.run(op, lib) } }
                .disabled(isRunning).frame(width: 80)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - First-launch assistant

@MainActor
final class OnboardingModel: ObservableObject {
    @Published var step = 0
    @Published var selected: Set<RefreshOp> = Set(RefreshOp.allCases.filter(\.defaultInAll))
    @Published var running = false
}

struct OnboardingView: View {
    @Environment(Library.self) var lib
    @Environment(\.openWindow) private var openWindow
    @StateObject private var model = OnboardingModel()
    @ObservedObject private var tasks = TaskCenter.shared
    @AppStorage("onboardingDone") private var done = false
    @AppStorage("refreshAtLaunch") private var atLaunch = false
    let close: () -> Void

    private let steps = [String(localized: "Bienvenue"), String(localized: "Plateformes"), String(localized: "Comptes"), String(localized: "Actualisations"), String(localized: "Interface"), String(localized: "C'est parti")]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { i in
                    Capsule().fill(i <= model.step ? Color.accentColor : Color.secondary.opacity(0.25)).frame(height: 4)
                }
            }
            .padding(.horizontal, 24).padding(.top, 20)
            Group {
                switch model.step {
                case 0: welcome
                case 1: platforms
                case 2: accounts
                case 3: refreshChoice
                case 4: interface
                default: launch
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            Divider()
            HStack {
                if model.step > 0 && !model.running { Button("Retour") { model.step -= 1 } }
                Spacer()
                Button("Passer l'assistant") { finish() }.buttonStyle(.borderless).foregroundStyle(.secondary)
                if model.step < steps.count - 1 {
                    Button("Continuer") { model.step += 1 }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button(model.running ? "Actualisation…" : "Terminer") { finish() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.running)
                }
            }
            .padding(16)
        }
        .frame(width: 640, height: 520)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "gamecontroller.fill").font(.system(size: 44)).foregroundStyle(Color.accentColor)
            Text("Bienvenue dans Ludothèque").font(.largeTitle.bold())
            Text("Toute ta ludothèque au même endroit : Steam, Epic, GOG, Xbox, PlayStation, Nintendo, émulateurs, jeux Windows…")
                .font(.title3).foregroundStyle(.secondary)
            Text("Cet assistant prend une minute : il détecte tes plateformes, te propose de connecter tes comptes et de choisir ce qui doit s'actualiser. Tout reste sur ce Mac.")
        }
    }

    private var platforms: some View {
        let detected = Launchers.bundleIds.filter { Launchers.installed($0.value) }.map(\.key).sorted { $0.name < $1.name }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Plateformes détectées sur ce Mac").font(.title2.bold())
            if detected.isEmpty {
                Text("Aucun launcher détecté. Tu pourras ajouter tes jeux à la main ou connecter tes comptes.").foregroundStyle(.secondary)
            } else {
                FixedColumns(items: detected, columns: 3) { p in
                        HStack { PlatformLogo(platform: p, size: 22); Text(p.name); Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            }
            Text("Leurs jeux seront importés automatiquement lors de l'actualisation de la bibliothèque. GOG Galaxy apporte aussi les bibliothèques des comptes que tu y as liés (Xbox, PlayStation, Ubisoft, EA…).")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var accounts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connecter tes comptes (facultatif)").font(.title2.bold())
            Text("Connecte Steam, Epic, GOG, Xbox, PlayStation, Nintendo, itch.io ou Humble pour importer toute ta bibliothèque, y compris les jeux non installés, ainsi que tes succès.")
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Integrations.all.map(\.platform)) { p in PlatformLogo(platform: p, size: 26) }
            }
            Button { openWindow(id: "platforms") } label: { Label("Ouvrir la gestion des plateformes", systemImage: "person.crop.circle.badge.checkmark") }
                .controlSize(.large)
            Text("Tu peux aussi le faire plus tard depuis la barre d'outils.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var refreshChoice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Que veux-tu actualiser ?").font(.title2.bold())
            Text("Ces choix servent au bouton « Tout actualiser ». Tu pourras lancer chaque élément séparément dans l'onglet Actualisations.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(RefreshOp.allCases) { op in
                        Toggle(isOn: Binding(get: { model.selected.contains(op) },
                                             set: { if $0 { model.selected.insert(op) } else { model.selected.remove(op) } })) {
                            Label(op.title, systemImage: op.symbol)
                        }.toggleStyle(.checkbox)
                    }
                }
            }
            Toggle("Actualiser automatiquement à chaque ouverture", isOn: $atLaunch)
        }
    }

    private var interface: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ton interface").font(.title2.bold())
            HStack(spacing: 14) {
                choice(String(localized: "Complète"), String(localized: "Tous les onglets : bibliothèque, boutiques, succès, statistiques, émulateurs, jeux Windows…"), "square.grid.3x3.fill") {
                    for k in UIKeys.all where k.hasPrefix("ui.") { UserDefaults.standard.removeObject(forKey: k) }
                }
                choice(String(localized: "Essentielle"), String(localized: "Ta bibliothèque, les jeux jouables et le bouton Actualiser. Le reste se réactive dans Options → Interface."), "square.fill") {
                    UserDefaults.standard.set([SidebarItem.profile, .statistics, .achievements, .performance, .emulators, .windows, .search, .freeLoot,
                                               .installable, .cloud].map(\.rawValue).joined(separator: ","), forKey: UIKeys.hiddenSidebar)
                    UserDefaults.standard.set([SidebarSection.presets, .stores].map(\.rawValue).joined(separator: ","), forKey: UIKeys.hiddenSections)
                }
            }
        }
    }

    private func choice(_ title: String, _ text: String, _ icon: String, _ apply: @escaping () -> Void) -> some View {
        Button { apply(); model.step += 1 } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.title).foregroundStyle(Color.accentColor)
                Text(title).font(.headline)
                Text(text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }
            .padding(14).frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }

    private var launch: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Première actualisation").font(.title2.bold())
            Text("Lance maintenant les \(model.selected.count) actualisation(s) choisie(s), ou fais-le plus tard depuis l'onglet Actualisations.")
                .foregroundStyle(.secondary)
            if model.running, let job = tasks.jobs.first(where: { $0.total > 0 }) ?? tasks.jobs.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(job.title)\(job.detail.isEmpty ? "" : " — \(job.detail)")").font(.callout)
                    if let f = job.fraction { ProgressView(value: f) } else { ProgressView().progressViewStyle(.linear) }
                }
            } else if model.running {
                ProgressView().progressViewStyle(.linear)
            } else {
                Button {
                    for op in RefreshOp.allCases { RefreshCenter.shared.setIncluded(op, model.selected.contains(op)) }
                    model.running = true
                    Task {
                        await RefreshCenter.shared.runAll(lib)
                        model.running = false
                    }
                } label: { Label("Lancer l'actualisation", systemImage: "arrow.clockwise") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
    }

    private func finish() {
        for op in RefreshOp.allCases { RefreshCenter.shared.setIncluded(op, model.selected.contains(op)) }
        done = true
        close()
    }
}
