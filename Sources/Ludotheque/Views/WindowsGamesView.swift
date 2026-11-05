// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI

@MainActor
final class WinViewModel: ObservableObject {
    @Published var routeFilter: String = "all"
    @Published var search = ""
    @Published var installTool: WinTool = .crossover
}

struct WindowsGamesView: View {
    @Environment(\.stableWidth) private var stableWidth
    @Environment(Library.self) var lib
    @ObservedObject private var win = WindowsGaming.shared
    @StateObject private var vm = WinViewModel()

    var body: some View {
        let games = win.windowsOnly(lib)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Jouer aux jeux Windows").font(.largeTitle.bold())
                    Text("Ludothèque vérifie ton Mac, choisit pour chaque jeu la méthode la plus simple et automatise l'installation. \(games.count) jeux de ta bibliothèque n'existent que sur Windows.")
                        .foregroundStyle(.secondary)
                }
                checklist
                tools
                launchers
                gameList(games)
            }
            .padding(24)
        }

    }

    // MARK: 1. System check

    private var checklist: some View {
        let mac = MacSpecs.current
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let anyTool = [WinTool.heroic, .crossover, .whisky].contains { $0.installed }
        return section("1. Ton Mac est-il prêt ?") {
            VStack(alignment: .leading, spacing: 8) {
                check(WindowsGaming.appleSilicon, "Puce Apple Silicon (\(mac.chip))", "Les jeux Windows passent par la traduction x86 → ARM.")
                HStack {
                    check(win.rosetta, "Rosetta 2 installé", "Indispensable pour Wine, CrossOver, Whisky et Heroic.")
                    if !win.rosetta {
                        Button("Installer Rosetta 2") { Task { await win.installRosetta() } }.buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
                check(os.majorVersion >= 14, "macOS \(os.majorVersion).\(os.minorVersion)", "macOS 14 ou plus requis pour le Game Porting Toolkit (DirectX 12 → Metal).")
                check(mac.memoryGB >= 16, "\(mac.memoryGB) Go de mémoire", mac.memoryGB >= 16 ? "Confortable." : "Suffisant pour les jeux légers ; les jeux récents demandent 16 Go.", warnOnly: true)
                check(WindowsGaming.freeDiskGB >= 50, "\(WindowsGaming.freeDiskGB) Go libres", "Prévois 20 à 100 Go par jeu récent.", warnOnly: true)
                check(anyTool, "Un outil de compatibilité installé", anyTool ? "Prêt à installer des jeux Windows." : "Installe Heroic (gratuit) ou CrossOver ci-dessous.")
                check(WinTool.geforceNow.installed, "GeForce NOW installé", "Solution de secours pour les jeux avec anti-triche.", warnOnly: true)
            }
            if let b = win.busy { ProgressView(b).controlSize(.small) }
        }
    }

    private func check(_ ok: Bool, _ title: String, _ detail: String, warnOnly: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : (warnOnly ? "exclamationmark.triangle.fill" : "xmark.circle.fill"))
                .foregroundStyle(ok ? .green : (warnOnly ? .orange : .red))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 2. Tools

    private var tools: some View {
        section("2. Outils recommandés") {
            LazyVGrid(columns: stableColumns(stableWidth, min: 320, spacing: 12, padding: 48), spacing: 12) {
                ForEach(WinTool.allCases) { t in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Group {
                                if let u = t.installedURL { Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable() }
                                else { Image(systemName: t == .xboxCloud || t == .geforceNow ? "cloud.fill" : "wineglass.fill").resizable().scaledToFit().padding(6).foregroundStyle(.secondary) }
                            }.frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(t.name).font(.headline)
                                    Text(t.free ? "Gratuit" : "Payant").font(.caption2.weight(.semibold)).padding(.horizontal, 5)
                                        .background((t.free ? Color.green : Color.orange).opacity(0.18), in: Capsule())
                                }
                                Text(t.installed ? (t == .xboxCloud ? "Dans le navigateur" : "Installé") : "Non installé").font(.caption).foregroundStyle(t.installed ? .green : .secondary)
                            }
                            Spacer()
                            Button(t.installed ? "Ouvrir" : "Obtenir") { win.open(t) }.controlSize(.small)
                        }
                        Text(t.summary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: 3. One-click launcher install

    private var launchers: some View {
        section("3. Installer un launcher Windows en un clic") {
            Text("Télécharge l'installateur officiel et l'ouvre directement dans CrossOver ou Whisky, qui créent la bouteille Windows. Pour Epic, GOG et Amazon, utilise plutôt Heroic (aucune bouteille à gérer).")
                .font(.callout).foregroundStyle(.secondary)
            let available = [WinTool.crossover, .whisky].filter(\.installed)
            if available.isEmpty {
                Label("Installe d'abord CrossOver ou Whisky (section 2).", systemImage: "info.circle").foregroundStyle(.orange)
            } else {
                Picker("Avec", selection: $vm.installTool) { ForEach(available) { Text($0.name).tag($0) } }
                    .frame(width: 260)
                    .onAppear { if !available.contains(vm.installTool) { vm.installTool = available[0] } }
                HStack {
                    ForEach(WinInstaller.allCases) { i in
                        Button {
                            Task { lib.flash(await win.install(i, with: vm.installTool)) }
                        } label: {
                            HStack(spacing: 5) { PlatformLogo(platform: i.platform, size: 16); Text(i.name) }
                        }
                        .disabled(TaskCenter.shared.isRunning("wininstall"))
                    }
                }
            }
        }
    }

    // MARK: 4. Per-game assistant

    private func gameList(_ games: [GameGroup]) -> some View {
        let routed = games.map { ($0, win.route($0)) }
        let list = routed.filter { g, r in
            (vm.search.isEmpty || lib.title(g).localizedCaseInsensitiveContains(vm.search)) &&
            (vm.routeFilter == "all" || vm.routeFilter == key(r))
        }.sorted { lib.playtime($0.0) > lib.playtime($1.0) }
        return section("4. Tes jeux Windows et comment y jouer") {
            HStack {
                Picker("Méthode", selection: $vm.routeFilter) {
                    Text("Toutes (\(routed.count))").tag("all")
                    Text("Heroic (\(routed.filter { key($0.1) == "heroic" }.count))").tag("heroic")
                    Text("CrossOver / Whisky (\(routed.filter { key($0.1) == "crossover" }.count))").tag("crossover")
                    Text("Cloud (\(routed.filter { key($0.1) == "cloud" }.count))").tag("cloud")
                }.frame(width: 320)
                TextField("Rechercher", text: $vm.search).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                Spacer()
                if win.antiCheat.isEmpty {
                    Button("Télécharger la base anti-triche") { Task { await RefreshCenter.shared.run(.anticheat, lib) } }.controlSize(.small)
                }
            }
            LazyVStack(spacing: 8) {
                ForEach(list.prefix(300), id: \.0.id) { g, r in row(g, r) }
            }
            if list.count > 300 { Text("300 premiers jeux affichés (tri par temps de jeu). Utilise la recherche.").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func key(_ r: WinRoute) -> String {
        switch r { case .heroic: "heroic"; case .crossover: "crossover"; default: "cloud" }
    }

    private func row(_ g: GameGroup, _ r: WinRoute) -> some View {
        let ac = win.antiCheat(for: g)
        return HStack(spacing: 12) {
            CoverImage(game: lib.coverGame(g)).frame(width: 34, height: 51).clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(lib.title(g)).font(.callout.weight(.semibold)).lineLimit(1)
                    ForEach(g.bestPerPlatform) { PlatformLogo(platform: $0.platform, size: 14) }
                }
                HStack(spacing: 8) {
                    Label(r.label, systemImage: r.symbol).foregroundStyle(r == .antiCheatCloud ? .orange : .accentColor)
                    if let ac, !ac.anticheats.isEmpty {
                        Text("Anti-triche : \(ac.anticheats.joined(separator: ", "))").foregroundStyle(ac.blocksMac ? .red : .secondary)
                    }
                    let v = PerfMath.verdict(PerfStore.shared.requirements(g), game: g.primary)
                    if v != .unknown { Label(v.label, systemImage: v.symbol).foregroundStyle(Color(v.color)) }
                }
                .font(.caption)
            }
            Spacer()
            actions(g, r)
            Menu {
                ForEach(WindowsGaming.compatLinks(lib.title(g)), id: \.0) { name, url in Link("Compatibilité : \(name)", destination: url) }
                GroupMenu(group: g)
            } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 28)
        }
        .padding(8)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private func actions(_ g: GameGroup, _ r: WinRoute) -> some View {
        switch r {
        case .heroic:
            if WinTool.heroic.installed {
                Button("Ouvrir dans Heroic") {
                    if let h = g.games.first(where: { $0.launchURL?.hasPrefix("heroic://") == true }) { lib.launch(h) } else { win.open(.heroic) }
                }.controlSize(.small)
            } else { Button("Installer Heroic") { win.open(.heroic) }.controlSize(.small) }
        case .crossover:
            let tool = [WinTool.crossover, .whisky].first(where: \.installed)
            Button(tool.map { "Ouvrir \($0.name)" } ?? "Obtenir CrossOver") { win.open(tool ?? .crossover) }.controlSize(.small)
                .help("Installe le launcher Windows de ce jeu (section 3), connecte-toi puis installe le jeu dans la bouteille.")
        case .antiCheatCloud, .cloud:
            if WinTool.geforceNow.installed { Button("GeForce NOW") { lib.openInGeForceNow(g.primary) }.controlSize(.small) }
            else { Button("Obtenir GeForce NOW") { win.open(.geforceNow) }.controlSize(.small) }
        case .xboxCloud:
            Button("Xbox Cloud") { if let x = g.games.first(where: { $0.platform == .xbox }) { lib.launch(x) } }.controlSize(.small)
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title2.bold())
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
