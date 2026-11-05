// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI

@MainActor
final class PerfViewModel: ObservableObject {
    @Published var verdictFilter: Verdict?
    /// Natural height of the header, measured once it is laid out (kept between visits: no jump).
    @Published var headerHeight: CGFloat = PerfViewModel.lastHeaderHeight { didSet { PerfViewModel.lastHeaderHeight = headerHeight } }
    nonisolated(unsafe) static var lastHeaderHeight: CGFloat = 300
}

/// Resolution + frame-rate pickers for a target, stored in UserDefaults.
struct TargetPicker: View {
    let title: String
    @AppStorage var height: Int
    @AppStorage var fps: Int

    init(_ title: String, key: String, height: Int, fps: Int) {
        self.title = title
        _height = AppStorage(wrappedValue: height, key + "H")
        _fps = AppStorage(wrappedValue: fps, key + "F")
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Picker(title, selection: $height) {
                ForEach(PerfTarget.heights, id: \.self) { Text($0 == 2160 ? "4K" : "\($0)p").tag($0) }
            }.labelsHidden().frame(width: 76)
            Picker(title, selection: $fps) {
                ForEach(PerfTarget.rates, id: \.self) { Text("\($0) fps").tag($0) }
            }.labelsHidden().frame(width: 80)
        }
    }
}

struct PerformanceView: View {
    @Environment(Library.self) var lib
    @ObservedObject private var perf = PerfStore.shared
    @StateObject private var vm = PerfViewModel()
    private let mac = MacSpecs.current

    var body: some View {
        let groups = lib.visibleGroups
        // Verdicts are computed for every game only when a verdict filter needs them; otherwise each
        // visible row computes its own.
        let rows = vm.verdictFilter.map { f in groups.filter { PerfMath.verdict(perf.requirements($0), game: $0.primary) == f } } ?? groups
        GeometryReader { geo in
        VStack(spacing: 0) {
            // Header never takes more than ~half the height: it scrolls on small windows, the table keeps its room.
            // The header scrolls on small windows and never takes more than ~half the height. Its
            // height is measured once instead of laying it out twice (ViewThatFits: +130 ms per visit).
            ScrollView {
                header(groups).onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                    if abs(h - vm.headerHeight) > 0.5 { vm.headerHeight = h }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(vm.headerHeight, geo.size.height * 0.55))
            NativeGameTable(lib: lib, groups: rows, columns: columns, autosaveName: "perfTable",
                            extraMenu: { g in [TileMenu.item("Rechercher à nouveau") { Task { await PerfStore.shared.searchAgain([g]) } }] },
                            onOpen: { g in Library.shared.launch(g.primary) })
        }
        }
    }

    private var columns: [GameTableColumn] {
        let perf = perf, lib = lib, mac = mac
        return [
            GameTableColumn(id: "title", title: "Jeu", width: 280, minWidth: 220) { g in
                GameCell(text: lib.title(g), secondary: g.primary.macNative == true ? "Natif Mac" : "Via traduction (CrossOver / GPTK)",
                         cover: lib.coverGame(g))
            },
            GameTableColumn(id: "min", title: "Minimum (\(PerfTarget.minimum.label))", width: 150, minWidth: 120) { g in
                Self.verdictCell(g, perf: perf, need: 1)
            },
            GameTableColumn(id: "rec", title: "Recommandé (\(PerfTarget.recommended.label))", width: 160, minWidth: 120) { g in
                Self.verdictCell(g, perf: perf, need: 2)
            },
            GameTableColumn(id: "gpu", title: "Carte graphique recommandée", width: 260, minWidth: 160) { g in
                let q = perf.requirements(g)
                return GameCell(text: q?.recGPU ?? q?.minGPU ?? "—", color: .secondaryLabelColor, tooltip: q?.recGPU)
            },
            GameTableColumn(id: "ram", title: "RAM", width: 60, minWidth: 50, maxWidth: 90) { g in
                let q = perf.requirements(g)
                return GameCell(text: q?.recRAM.map { "\($0) Go" } ?? q?.minRAM.map { "\($0) Go" } ?? "—",
                                color: (q?.recRAM ?? q?.minRAM ?? 0) > mac.memoryGB ? .systemRed : .secondaryLabelColor)
            },
            GameTableColumn(id: "source", title: "Source", width: 110, minWidth: 80) { g in
                let q = perf.requirements(g)
                return GameCell(text: q?.source ?? "—", color: .secondaryLabelColor,
                                tooltip: q?.fetchedAt.map { "Recherché le \($0.formatted())" })
            },
        ]
    }

    @ViewBuilder private func header(_ groups: [GameGroup]) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 0).onAppear { details.load() }
            macCard.padding(16)
            HStack(spacing: 18) {
                TargetPicker("Minimum", key: "perfMin", height: 1080, fps: 60)
                TargetPicker("Recommandé", key: "perfRec", height: 1440, fps: 144)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
            HStack {
                Picker("Verdict", selection: $vm.verdictFilter) {
                    Text("Tous").tag(Verdict?.none)
                    ForEach([Verdict.smooth1440, .smooth1080, .low, .insufficient, .unknown], id: \.self) { v in
                        Label(v.label, systemImage: v.symbol).tag(Verdict?.some(v))
                    }
                }.frame(width: 280)
                Spacer()
                if let p = perf.progress {
                    ProgressView(value: Double(p.done), total: Double(p.total)).frame(width: 160)
                    Text("\(p.done)/\(p.total)").monospacedDigit().foregroundStyle(.secondary)
                } else {
                    let missing = groups.filter { perf.requirements($0) == nil }.count
                    if missing > 0 {
                        Button { Task { await perf.analyze(groups) } } label: {
                            Label("Rechercher sur internet (\(missing) jeux)", systemImage: "magnifyingglass")
                        }.buttonStyle(.borderedProminent)
                    }
                    Button {
                        if groups.count > 25 {
                            let a = NSAlert()
                            a.messageText = "Rechercher à nouveau \(groups.count) jeux ?"
                            a.informativeText = "Les résultats de cette vue seront effacés puis recherchés à nouveau (environ \(max(1, groups.count / 120)) min). Astuce : filtre la vue pour cibler quelques jeux."
                            a.addButton(withTitle: "Rechercher"); a.addButton(withTitle: "Annuler")
                            guard a.runModal() == .alertFirstButtonReturn else { return }
                        }
                        Task { await perf.searchAgain(groups) }
                    } label: {
                        Label("Rechercher à nouveau", systemImage: "arrow.clockwise")
                    }
                    .help("Efface les résultats de cette vue et relance la recherche (PCGamingWiki, Steam, GOG)")
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
    }

    private func ghz(_ mhz: Int) -> String { String(format: "%.2f GHz", Double(mhz) / 1000) }

    /// need 1 = minimum target, 2 = recommended target.
    @MainActor private static func verdictCell(_ g: GameGroup, perf: PerfStore, need: Int) -> GameCell {
        let req = perf.requirements(g)
        let verdict = PerfMath.verdict(req, game: g.primary)
        if verdict == .unknown { return GameCell(text: req == nil ? "Non analysé" : "Inconnu", color: .secondaryLabelColor) }
        let ok = need == 1 ? verdict >= .smooth1080 : verdict >= .smooth1440
        let shown: Verdict = ok ? (need == 1 ? .smooth1080 : .smooth1440) : (verdict == .insufficient ? .insufficient : (need == 1 ? verdict : .low))
        let color = ok ? Verdict.smooth1080.color : shown.color
        return GameCell(text: ok ? "Oui" : (shown == .insufficient ? "Non" : "Réglages bas"), color: color,
                        symbol: ok ? "checkmark.circle.fill" : shown.symbol)
    }

    @AppStorage("perfShowDetails") private var showDetails = true
    @ObservedObject private var details = MacDetailsStore.shared

    private var macCard: some View {
        let d = details.details ?? MacSpecs.Details()
        let left: [(String, String)] = [
            ("Modèle", d.model + (d.fanless ? " · sans ventilateur" : "")),
            ("Processeur", "\(mac.performanceCores) perf.\(d.pCoreMHz.map { " @ \(ghz($0))" } ?? "") + \(mac.efficiencyCores) effic.\(d.eCoreMHz.map { " @ \(ghz($0))" } ?? "")"),
            ("Cache L2", d.l2P.map { "\($0 >> 20) Mo perf.\(d.l2E.map { " · \($0 >> 20) Mo effic." } ?? "")" } ?? "—"),
            ("Mémoire", "\(mac.memoryGB) Go \(d.memoryType)\(d.memorySpeed.map { "-\($0)" } ?? "")\(d.bandwidth.map { String(format: " · %.0f Go/s", $0) } ?? "")"),
            ("Stockage", "\(d.ssd == true ? "SSD" : d.ssd == false ? "HDD" : "Disque")\(d.storageTotalGB.map { " · \($0) Go" } ?? "")\(d.storageFreeGB.map { " (\($0) libres)" } ?? "")"),
        ]
        let right: [(String, String)] = [
            ("GPU", "\(mac.gpuCores.map { "\($0) cœurs" } ?? mac.gpuName)\(d.gpuMHz.map { " @ \($0) MHz" } ?? "")\(d.tflops.map { String(format: " · %.1f TFLOPS", $0) } ?? "")"),
            ("Graphismes", "\(d.metal3 ? "Metal 3 · MetalFX" : "Metal 2")\(d.raytracing ? " · ray tracing matériel" : "")"),
            ("Mémoire GPU", d.maxWorkingSetGB.map { String(format: "%.1f Go utilisables", $0) } ?? "—"),
            ("Écran", "\(mac.screenWidth) × \(mac.screenHeight) · \(mac.refreshRate) Hz"),
            ("Température", d.thermal.isEmpty ? "—" : d.thermal),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "laptopcomputer").font(.system(size: 28)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mac.chip).font(.title2.bold())
                    Text("\(mac.memoryGB) Go · \(mac.gpuCores.map { "GPU \($0) cœurs" } ?? mac.gpuName) · \(mac.equivalent)").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(mac.gpuIndex)").font(.system(size: 30, weight: .bold)).monospacedDigit()
                    Text("indice GPU (GTX 1060 = 100)").font(.caption2).foregroundStyle(.secondary)
                }
                Button { withAnimation { showDetails.toggle() } } label: {
                    Image(systemName: showDetails ? "chevron.up.circle" : "chevron.down.circle").font(.title2)
                }.buttonStyle(.borderless).help(showDetails ? "Masquer les détails" : "Afficher les détails du Mac")
            }
            if showDetails {
                HStack(alignment: .top, spacing: 30) {
                    specGrid(left)
                    specGrid(right)
                }
                Text("Estimation : config recommandée ≈ 1080p 60 ; \(PerfTarget.recommended.label) demande ≈ ×\(String(format: "%.1f", PerfTarget.recommended.factor)). Jeux Windows : −40 % (traduction).\(mac.refreshRate < PerfTarget.recommended.fps ? " Ton écran est limité à \(mac.refreshRate) Hz." : "")\(d.fanless ? " Mac sans ventilateur : les performances baissent après quelques minutes de jeu intensif." : "")")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func specGrid(_ rows: [(String, String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
            ForEach(rows, id: \.0) { k, v in
                GridRow {
                    Text(k).foregroundStyle(.secondary)
                    Text(v).lineLimit(1).truncationMode(.tail).help(v)
                }
            }
        }
        .font(.callout).textSelection(.enabled)
    }
}

/// Compact verdict shown in the details panel.
struct PerfBadge: View {
    @ObservedObject private var perf = PerfStore.shared
    let group: GameGroup

    var body: some View {
        let r = perf.requirements(group)
        let v = PerfMath.verdict(r, game: group.primary)
        HStack {
            Label(v == .unknown && r == nil ? "Performances non analysées" : v.label, systemImage: v.symbol)
                .foregroundStyle(Color(v.color))
            Spacer()
            Button(r == nil ? "Rechercher" : "Rechercher à nouveau") { Task { await perf.searchAgain([group]) } }
                .controlSize(.small)
        }
        .font(.callout)
        .help(r?.recGPU.map { "Recommandé : \($0)" } ?? "")
    }
}
