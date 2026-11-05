// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI

enum AchSort: String, CaseIterable, Identifiable {
    case inProgress = "En cours", percent = "% complété", nearly = "Presque terminés", perfect = "Parfaits (100 %)"
    case recent = "Récemment débloqués", count = "Nombre de succès", rare = "Succès les plus rares"
    var id: String { rawValue }
}

@MainActor
final class AchViewModel: ObservableObject {
    @Published var sort: AchSort = .inProgress
    @Published var platform: Platform?
    @Published var search = ""
}

struct AchievementsView: View {
    @Environment(\.stableWidth) private var stableWidth
    @Environment(Library.self) var lib
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var hub = AchievementHub.shared
    @StateObject private var vm = AchViewModel()

    var body: some View {
        let all = hub.items.filter { vm.platform == nil || $0.platform == vm.platform }
        let list = sorted(all.filter { vm.search.isEmpty || $0.title.localizedCaseInsensitiveContains(vm.search) })
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if hub.connected.isEmpty {
                    ContentUnavailableView {
                        Label("Connecte un compte", systemImage: "trophy")
                    } description: {
                        Text("Les succès viennent de Steam (clé API), Xbox (OpenXBL) et PlayStation (NPSSO).")
                    } actions: {
                        Button("Gestion des plateformes") { openWindow(id: "platforms") }.buttonStyle(.borderedProminent)
                    }
                } else if hub.items.isEmpty {
                    ContentUnavailableView("Aucun succès chargé", systemImage: "trophy", description: Text("Clique sur « Actualiser les succès »."))
                } else {
                    summary(all)
                    recentStrip(all)
                    controls
                    VStack(spacing: 8) { ForEach(list) { row($0) } }
                }
            }
            .padding(24)
        }

    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Succès").font(.largeTitle.bold())
                HStack(spacing: 6) {
                    ForEach(hub.connected, id: \.self) { PlatformLogo(platform: $0, size: 16) }
                    if let d = hub.updatedAt { Text("Actualisé \(d.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary) }
                }
                if let e = hub.lastError { Label(e, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            }
            Spacer()
            if let p = hub.progress {
                ProgressView(value: Double(p.0), total: Double(max(1, p.1))).frame(width: 140)
                Text("\(p.0)/\(p.1)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Button { Task { await hub.refresh(lib) } } label: { Label("Actualiser les succès", systemImage: "arrow.clockwise") }
                .disabled(hub.progress != nil || hub.connected.isEmpty)
        }
    }

    private func summary(_ all: [AchSummary]) -> some View {
        let unlocked = all.map(\.unlocked).reduce(0, +), total = all.map(\.total).reduce(0, +)
        let started = all.filter { $0.unlocked > 0 }
        let avg = started.isEmpty ? 0 : started.map(\.percent).reduce(0, +) / Double(started.count)
        let gs = all.compactMap(\.gamerscore).reduce(0, +)
        let plat = all.filter { $0.platinum == true }.count
        return LazyVGrid(columns: stableColumns(stableWidth, min: 150, spacing: 12, padding: 48), spacing: 12) {
            tile("\(unlocked)", "succès débloqués sur \(total)", "trophy.fill", .yellow)
            tile("\(all.filter(\.perfect).count)", "jeux à 100 %", "crown.fill", .orange)
            tile("\(all.filter(\.inProgress).count)", "jeux en cours", "hourglass", .blue)
            tile("\(Int(avg * 100)) %", "complétion moyenne (jeux commencés)", "chart.pie.fill", .green)
            if gs > 0 { tile("\(gs)", "Gamerscore", "g.circle.fill", Color(Platform.xbox.color)) }
            if all.contains(where: { $0.platform == .psn }) { tile("\(plat)", "trophées platine", "rosette", .cyan) }
        }
    }

    @ViewBuilder private func recentStrip(_ all: [AchSummary]) -> some View {
        let recent = all.flatMap { s in s.recent.map { (s, $0) } }.filter { $0.1.date != nil }.sorted { $0.1.date! > $1.1.date! }.prefix(12)
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Derniers succès débloqués").font(.title3.bold())
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(recent.enumerated()), id: \.offset) { _, pair in achCard(pair.0, pair.1) }
                    }
                }
            }
        }
    }

    private func achCard(_ s: AchSummary, _ a: RecentAch) -> some View {
        HStack(spacing: 10) {
            CoverImage(game: Game(id: "ach_\(s.id)_\(a.name)", platform: s.platform, externalId: "", title: a.name, coverURL: a.icon))
                .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(a.name).font(.callout.weight(.semibold)).lineLimit(1)
                Text(s.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    if let r = a.rarity { rarityBadge(r) }
                    if let d = a.date { Text(d.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }
        .padding(10).frame(width: 260, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .help(a.detail)
    }

    private var controls: some View {
        HStack {
            Picker("Trier", selection: $vm.sort) { ForEach(AchSort.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 260)
            Picker("Plateforme", selection: $vm.platform) {
                Text("Toutes").tag(Platform?.none)
                ForEach(hub.connected, id: \.self) { Text($0.name).tag(Platform?.some($0)) }
            }.frame(width: 200)
            TextField("Filtrer les jeux", text: $vm.search).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
            Spacer()
        }
    }

    private func sorted(_ list: [AchSummary]) -> [AchSummary] {
        switch vm.sort {
        case .inProgress: return list.filter(\.inProgress).sorted { ($0.lastUnlock ?? .distantPast) > ($1.lastUnlock ?? .distantPast) }
        case .percent: return list.filter { $0.unlocked > 0 }.sorted { ($0.percent, $0.unlocked) > ($1.percent, $1.unlocked) }
        case .nearly: return list.filter { $0.inProgress && $0.percent >= 0.7 }.sorted { $0.percent > $1.percent }
        case .perfect: return list.filter(\.perfect).sorted { ($0.lastUnlock ?? .distantPast) > ($1.lastUnlock ?? .distantPast) }
        case .recent: return list.filter { $0.lastUnlock != nil }.sorted { $0.lastUnlock! > $1.lastUnlock! }
        case .count: return list.sorted { $0.unlocked > $1.unlocked }
        case .rare: return list.filter { $0.rarest?.rarity != nil }.sorted { $0.rarest!.rarity! < $1.rarest!.rarity! }
        }
    }

    private func row(_ s: AchSummary) -> some View {
        HStack(spacing: 12) {
            CoverImage(game: Game(id: "achg_\(s.id)", platform: s.platform, externalId: s.gameId, title: s.title, coverURL: s.icon))
                .frame(width: 40, height: s.platform == .steam ? 60 : 40).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    PlatformLogo(platform: s.platform, size: 14)
                    Text(s.title).font(.callout.weight(.semibold)).lineLimit(1)
                    if s.perfect { Image(systemName: "crown.fill").foregroundStyle(.orange).help("100 %") }
                    if s.platinum == true { Image(systemName: "rosette").foregroundStyle(.cyan).help("Platine") }
                }
                ProgressView(value: s.percent).tint(s.perfect ? .orange : .accentColor)
                HStack(spacing: 10) {
                    Text("\(s.unlocked)/\(s.total)").monospacedDigit()
                    if let g = s.gamerscore, let t = s.gamerscoreTotal { Text("\(g)/\(t) G").monospacedDigit() }
                    if let r = s.rarest, let p = r.rarity { HStack(spacing: 4) { Text("Plus rare : \(r.name)").lineLimit(1); rarityBadge(p) } }
                    Spacer()
                    if let d = s.lastUnlock { Text(d.formatted(date: .abbreviated, time: .omitted)) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Text("\(Int(s.percent * 100)) %").font(.title3.bold()).monospacedDigit().frame(width: 60, alignment: .trailing)
        }
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            if let g = lib.groups.first(where: { grp in grp.games.contains { $0.externalId == s.gameId } || Integrations.norm(lib.title(grp)) == Integrations.norm(s.title) }) {
                lib.selected = g.id
            }
        }
    }

    private func rarityBadge(_ p: Double) -> some View {
        let (label, color): (String, Color) = p < 5 ? ("Ultra rare", .purple) : p < 15 ? ("Rare", .blue) : p < 40 ? ("Peu commun", .green) : ("Commun", .gray)
        return Text("\(label) · \(String(format: "%.1f", p)) %").font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 1).background(color.opacity(0.15), in: Capsule())
    }

    private func tile(_ v: String, _ l: String, _ icon: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).foregroundStyle(c)
            Text(v).font(.title2.bold()).monospacedDigit()
            Text(l).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}
