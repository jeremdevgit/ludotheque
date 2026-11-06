// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI

@MainActor
final class StatsModel: ObservableObject {
    @Published var genres: [(String, Int, Int)] = []      // name, games, minutes
    @Published var years: [(Int, Int)] = []
    @Published var analysed = 0
    @Published var fetching: (Int, Int)?

    func load(_ lib: Library) async {
        let groups = lib.groups
        let details = await GamesDB.shared.cachedDetails(groups.map(\.games))
        var g = [String: (Int, Int)](), y = [Int: Int]()
        var n = 0
        for (grp, d) in zip(groups, details) {
            guard let d else { continue }
            n += 1
            for genre in d.genres { let cur = g[genre] ?? (0, 0); g[genre] = (cur.0 + 1, cur.1 + lib.playtime(grp)) }
            if let r = d.release { y[Calendar.current.component(.year, from: r), default: 0] += 1 }
        }
        analysed = n
        genres = g.map { ($0.key, $0.value.0, $0.value.1) }.sorted { ($0.2, $0.1) > ($1.2, $1.1) }
        years = y.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// Downloads genres / release dates for the most played games (on demand).
    /// Runs as a background job, so it continues if the user leaves the tab.
    func fetchDetails(_ lib: Library) async {
        let todo = Array(lib.groups.sorted { lib.playtime($0) > lib.playtime($1) }.prefix(150))
        await TaskCenter.shared.runAndWait("genres", String(localized: "Genres et années de sortie")) {
            for (i, g) in todo.enumerated() where !Task.isCancelled {
                TaskCenter.shared.progress("genres", i, todo.count, lib.title(g))
                _ = await GamesDB.shared.details(for: g.games)
            }
        }
        await load(lib)
    }
}

struct StatsView: View {
    @Environment(\.stableWidth) private var stableWidth
    @Environment(Library.self) var lib
    @ObservedObject private var log = SessionLog.shared
    @ObservedObject private var wish = WishlistStore.shared
    @ObservedObject private var perf = PerfStore.shared
    @StateObject private var model = StatsModel()

    var body: some View {
        let groups = lib.groups
        let played = groups.filter { lib.playtime($0) > 0 }
        let total = played.map(lib.playtime).reduce(0, +)
        let sessions = log.sessions
        ScrollView {
            // Lazy: each block is computed and laid out only when it scrolls into view
            // (the page used to compute every chart before showing anything).
            LazyVStack(alignment: .leading, spacing: 26) {
                header(groups, played, total, sessions)
                keyFigures(groups, played, total, sessions)
                Deferred { facts(groups, played, total, sessions) }
                Deferred { platformsRow(groups, played, total, sessions) }
                Deferred { topPlayed(groups, played, total, sessions) }
                Deferred { activityRow(groups, played, total, sessions) }
                Deferred { habitsRow(groups, played, total, sessions) }
                Deferred { progressRow(groups, played, total, sessions) }
                Deferred { genresRow(groups, played, total, sessions) }
                Deferred { ratingsRow(groups, played, total, sessions) }
                Deferred { perfRow(groups, played, total, sessions) }
            }
            .padding(24)
        }
        .task { await model.load(lib) }
    }

    @ViewBuilder private func header(_ groups: [GameGroup], _ played: [GameGroup], _ total: Int, _ sessions: [Session]) -> some View {
                Text("Statistiques").font(.largeTitle.bold())
    }

    @ViewBuilder private func keyFigures(_ groups: [GameGroup], _ played: [GameGroup], _ total: Int, _ sessions: [Session]) -> some View {
                // Key figures
                LazyVGrid(columns: stableColumns(stableWidth, min: 150, spacing: 12, padding: 48), spacing: 12) {
                    tile("\(groups.count)", String(localized: "jeux dans la bibliothèque"), "square.grid.2x2.fill")
                    tile(hours(total), String(localized: "de jeu au total"), "clock.fill")
                    tile("\(played.count)", String(localized: "jeux lancés (\(pct(played.count, groups.count)))"), "play.fill")
                    tile(hours(played.isEmpty ? 0 : total / played.count), String(localized: "en moyenne par jeu joué"), "divide")
                    tile("\(lib.count(Scope.installed))", String(localized: "installés"), "internaldrive.fill")
                    tile("\(lib.count(Scope.playable))", String(localized: "jouables sur ce Mac"), "laptopcomputer")
                    tile("\(completed(groups))", String(localized: "terminés (\(pct(completed(groups), groups.count)))"), "flag.checkered")
                    tile("\(lib.platforms.count)", String(localized: "plateformes"), "square.stack.3d.up.fill")
                    tile(hours(log.thisWeekMinutes), String(localized: "cette semaine"), "calendar")
                    tile(hours(monthMinutes(sessions)), String(localized: "ce mois-ci"), "calendar.circle")
                    tile("\(sessions.count)", String(localized: "sessions mesurées"), "timer")
                    tile(String(localized: "\(streak(sessions)) j"), String(localized: "série de jours joués"), "flame.fill")
                }
    }

    @ViewBuilder private func facts(_ groups: [GameGroup], _ played: [GameGroup], _ total: Int, _ sessions: [Session]) -> some View {
                funFacts(groups, sessions)
    }

    @ViewBuilder private func platformsRow(_ groups: [GameGroup], _ played: [GameGroup], _ total: Int, _ sessions: [Session]) -> some View {
                HStack(alignment: .top, spacing: 20) {
                    card(String(localized: "Temps de jeu par plateforme")) {
                        let rows = lib.platforms.map { p in (p, groups.filter { $0.platforms.contains(p) }.map(lib.playtime).reduce(0, +)) }
                            .filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
                        if rows.isEmpty { none() }
                        bars(rows.map { ($0.0.name, $0.1, hours($0.1)) }, logos: rows.map(\.0))
                    }
                    card(String(localized: "Jeux par plateforme")) {
                        let rows = lib.platforms.map { ($0, lib.count(.platform($0))) }.sorted { $0.1 > $1.1 }
                        bars(rows.map { ($0.0.name, $0.1, "\($0.1)") }, logos: rows.map(\.0))
                    }
                }
    }

    @ViewBuilder private func topPlayed(_ groups: [GameGroup], _ played: [GameGroup], _ total: Int, _ sessions: [Session]) -> some View {
                card(String(localized: "Les plus joués")) {
                    let top = played.sorted { lib.playtime($0) > lib.playtime($1) }.prefix(15)
                    if top.isEmpty { none() }
                    let maxV = max(1, top.first.map(lib.playtime) ?? 1)
                    ForEach(Array(top.enumerated()), id: \.element.id) { i, g in
                        HStack(spacing: 10) {
                            Text("\(i + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 20)
                            CoverImage(game: lib.coverGame(g)).frame(width: 24, height: 36).clipShape(RoundedRectangle(cornerRadius: 3))
                            Text(lib.title(g)).lineLimit(1).frame(width: 240, alignment: .leading)
                            HStack(spacing: 3) { ForEach(g.bestPerPlatform) { PlatformLogo(platform: $0.platform, size: 14) } }.frame(width: 60, alignment: .leading)
                            bar(Double(lib.playtime(g)) / Double(maxV))
                            Text(hours(lib.playtime(g))).monospacedDigit().foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                        }
                    }
                }
    }

    @ViewBuilder private func activityRow(_ groups: [GameGroup], _ played: [GameGroup], _ total: Int, _ sessions: [Session]) -> some View {
                HStack(alignment: .top, spacing: 20) {
                    card(String(localized: "Activité — 30 derniers jours")) {
                        columns(log.perDay(30).map { ($0.0.formatted(.dateTime.day()), $0.1) }, height: 110, labelEvery: 5)
                        if sessions.isEmpty { Text("Les sessions lancées depuis Ludothèque sont mesurées automatiquement.").font(.caption).foregroundStyle(.secondary) }
                    }
                    card("12 derniers mois") {
                        columns(perMonth(sessions), height: 110, labelEvery: 1)
                    }
                }
    }

    @ViewBuilder private func habitsRow(_ groups: [GameGroup], _ played: [GameGroup], _ total: Int, _ sessions: [Session]) -> some View {
                HStack(alignment: .top, spacing: 20) {
                    card(String(localized: "Jours de jeu préférés")) {
                        columns(perWeekday(sessions), height: 90, labelEvery: 1)
                    }
                    card(String(localized: "Heures de jeu préférées")) {
                        columns(perHour(sessions), height: 90, labelEvery: 4)
                    }
                }
    }

    @ViewBuilder private func progressRow(_ groups: [GameGroup], _ played: [GameGroup], _ total: Int, _ sessions: [Session]) -> some View {
                HStack(alignment: .top, spacing: 20) {
                    card(String(localized: "Progression")) {
                        bars(Completion.allCases.map { c in (c.label, groups.filter { lib.statusOf($0) == c }.count, "\(groups.filter { lib.statusOf($0) == c }.count)") },
                             icons: Completion.allCases.map { ($0.symbol, $0.color) })
                    }
                    card(String(localized: "Disponibilité")) {
                        bars(LaunchKind.allCases.map { ($0.label, lib.count($0), "\(lib.count($0))") },
                             icons: LaunchKind.allCases.map { ($0.symbol, Color.accentColor) })
                    }
                }
    }

    @ViewBuilder private func genresRow(_ groups: [GameGroup], _ played: [GameGroup], _ total: Int, _ sessions: [Session]) -> some View {
                HStack(alignment: .top, spacing: 20) {
                    card(String(localized: "Genres (temps de jeu)")) {
                        if model.genres.isEmpty {
                            Text("Genres inconnus pour l'instant.").foregroundStyle(.secondary)
                        }
                        bars(model.genres.prefix(12).map { ($0.0, $0.2, $0.2 > 0 ? hours($0.2) : String(localized: "\($0.1) jeux")) })
                        analyseButton
                    }
                    card(String(localized: "Années de sortie")) {
                        if model.years.isEmpty { Text("Années inconnues pour l'instant.").foregroundStyle(.secondary) }
                        columns(model.years.map { ("\($0.0 % 100)", $0.1) }, height: 110, labelEvery: max(1, model.years.count / 8))
                        if let first = model.years.first, let last = model.years.last {
                            Text("De \(first.0) à \(last.0) · \(model.analysed) jeux analysés").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
    }

    @ViewBuilder private func ratingsRow(_ groups: [GameGroup], _ played: [GameGroup], _ total: Int, _ sessions: [Session]) -> some View {
                HStack(alignment: .top, spacing: 20) {
                    card(String(localized: "Mes notes")) {
                        bars((1...5).reversed().map { n in (String(repeating: "★", count: n), groups.filter { lib.entry($0.key).rating == n }.count, "\(groups.filter { lib.entry($0.key).rating == n }.count)") })
                        let tags = Dictionary(grouping: lib.user.values.flatMap { $0.tags ?? [] }, by: { $0 }).mapValues(\.count).sorted { $0.value > $1.value }.prefix(8)
                        if !tags.isEmpty {
                            Text(String(localized: "Tags : ") + tags.map { "\($0.key) (\($0.value))" }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    card(String(localized: "Évolution de la bibliothèque")) {
                        columns(addedPerMonth(), height: 90, labelEvery: 2)
                        Text("Jeux ajoutés à Ludothèque par mois").font(.caption).foregroundStyle(.secondary)
                    }
                }
    }

    @ViewBuilder private func perfRow(_ groups: [GameGroup], _ played: [GameGroup], _ total: Int, _ sessions: [Session]) -> some View {
                HStack(alignment: .top, spacing: 20) {
                    card(String(localized: "Performances sur ce Mac")) {
                        let verdicts = groups.map { PerfMath.verdict(perf.requirements($0), game: $0.primary) }
                        let notAnalysed = groups.filter { perf.requirements($0) == nil }.count
                        let unknown = verdicts.filter { $0 == .unknown }.count - notAnalysed
                        let kinds: [Verdict] = [.smooth1440, .smooth1080, .low, .insufficient]
                        bars(kinds.map { v in (v.label, verdicts.filter { $0 == v }.count, "\(verdicts.filter { $0 == v }.count)") }
                             + [(String(localized: "Sans configuration connue"), unknown, "\(unknown)"), (String(localized: "Pas encore analysés"), notAnalysed, "\(notAnalysed)")],
                             icons: kinds.map { ($0.symbol, Color($0.color)) } + [("questionmark.circle", .secondary), ("clock", .secondary)])
                        Text("\(groups.count) jeux au total. Les jeux uniquement console ou cloud n'ont pas de configuration PC.").font(.caption).foregroundStyle(.secondary)
                        if notAnalysed > 0 {
                            if TaskCenter.shared.isRunning("perf") { Text("Analyse en cours (barre en haut)…").font(.caption).foregroundStyle(.secondary) }
                            else { Button("Analyser les \(notAnalysed) jeux restants") { Task { await perf.analyze(groups.filter { perf.requirements($0) == nil }) } }.controlSize(.small) }
                        }
                    }
                    card(String(localized: "Liste de souhaits")) {
                        let onSale = wish.items.filter(\.onSale).count
                        let value = wish.items.compactMap { $0.steamPrice }.reduce(0, +)
                        Grid(alignment: .leading, verticalSpacing: 6) {
                            GridRow { Text("Jeux suivis").foregroundStyle(.secondary); Text("\(wish.items.count)") }
                            GridRow { Text("En promo").foregroundStyle(.secondary); Text("\(onSale)") }
                            GridRow { Text("Valeur (prix Steam)").foregroundStyle(.secondary); Text(String(format: "%.2f €", value)) }
                            GridRow { Text("Jeux gratuits récupérés").foregroundStyle(.secondary); Text("\(FreeGamesStore.shared.claimed.count)") }
                        }
                    }
                }

    }

    @ViewBuilder private var analyseButton: some View {
        if TaskCenter.shared.isRunning("genres") {
            Text("Analyse en cours (voir la barre en haut)…").font(.caption).foregroundStyle(.secondary)
        } else {
            Button("Analyser les genres et années de mes jeux les plus joués") { Task { await model.fetchDetails(lib) } }.controlSize(.small)
        }
    }

    // MARK: Fun facts

    private func funFacts(_ groups: [GameGroup], _ sessions: [Session]) -> some View {
        var facts = [(String, String)]()
        if let top = groups.max(by: { lib.playtime($0) < lib.playtime($1) }), lib.playtime(top) > 0 {
            facts.append(("crown.fill", String(localized: "Jeu le plus joué : \(lib.title(top)) (\(hours(lib.playtime(top))))")))
        }
        if let longest = sessions.max(by: { $0.minutes < $1.minutes }) {
            facts.append(("stopwatch.fill", String(localized: "Plus longue session : \(hours(longest.minutes)) sur \(longest.title)")))
        }
        let total = groups.map(lib.playtime).reduce(0, +)
        if total > 0 { facts.append(("sun.max.fill", String(localized: "Soit \(String(format: "%.1f", Double(total) / 1440)) jours de jeu cumulés"))) }
        let never = groups.filter { lib.playtime($0) == 0 && $0.primary.launchKind != .none }.count
        if never > 0 { facts.append(("tray.full.fill", String(localized: "\(never) jeux jouables jamais lancés : ta pile de jeux"))) }
        let multi = groups.filter { $0.platforms.count > 1 }.count
        if multi > 0 { facts.append(("square.on.square", String(localized: "\(multi) jeux possédés sur plusieurs plateformes"))) }
        return card(String(localized: "Le saviez-vous ?")) {
            ForEach(facts, id: \.1) { f in Label(f.1, systemImage: f.0) }
        }
    }

    // MARK: Data helpers

    private func completed(_ g: [GameGroup]) -> Int { g.filter { [.beaten, .completed].contains(lib.statusOf($0)) }.count }

    private func monthMinutes(_ s: [Session]) -> Int {
        let cal = Calendar.current
        return s.filter { cal.isDate($0.start, equalTo: Date(), toGranularity: .month) }.map(\.minutes).reduce(0, +)
    }

    private func streak(_ s: [Session]) -> Int {
        let cal = Calendar.current
        let days = Set(s.map { cal.startOfDay(for: $0.start) })
        var d = cal.startOfDay(for: Date())
        if !days.contains(d) { d = cal.date(byAdding: .day, value: -1, to: d)! }
        var n = 0
        while days.contains(d) { n += 1; d = cal.date(byAdding: .day, value: -1, to: d)! }
        return n
    }

    /// Minutes per weekday, Monday first.
    private func perWeekday(_ s: [Session]) -> [(String, Int)] {
        let names = Calendar.current.shortWeekdaySymbols
        var byDay = [Int](repeating: 0, count: 7)
        for x in s { byDay[Calendar.current.component(.weekday, from: x.start) - 1] += x.minutes }
        return (Array(1..<7) + [0]).map { (names[$0], byDay[$0]) }
    }

    private func perHour(_ s: [Session]) -> [(String, Int)] {
        var byHour = [Int](repeating: 0, count: 24)
        for x in s { byHour[Calendar.current.component(.hour, from: x.start)] += x.minutes }
        return (0..<24).map { ("\($0)h", byHour[$0]) }
    }

    private func perMonth(_ s: [Session]) -> [(String, Int)] {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        return (0..<12).reversed().map { off in
            let m = cal.date(byAdding: .month, value: -off, to: start)!
            let mins = s.filter { cal.isDate($0.start, equalTo: m, toGranularity: .month) }.map(\.minutes).reduce(0, +)
            return (m.formatted(.dateTime.month(.narrow)), mins)
        }
    }

    private func addedPerMonth() -> [(String, Int)] {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        let dates = lib.groups.compactMap { lib.entry($0.key).added }
        return (0..<12).reversed().map { off in
            let m = cal.date(byAdding: .month, value: -off, to: start)!
            return (m.formatted(.dateTime.month(.narrow)), dates.filter { cal.isDate($0, equalTo: m, toGranularity: .month) }.count)
        }
    }

    private func hours(_ m: Int) -> String { m >= 60 ? "\(m / 60) h\(m % 60 > 0 && m < 600 ? " \(m % 60)" : "")" : "\(m) min" }
    private func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "0 %" : "\(a * 100 / b) %" }

    // MARK: Building blocks

    private func tile(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).foregroundStyle(Color.accentColor)
            Text(value).font(.title2.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private func card<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
    }

    private func none() -> some View { Text("Pas encore de données.").foregroundStyle(.secondary) }

    private func bar(_ ratio: Double) -> some View {
        GeometryReader { geo in
            Capsule().fill(Color.accentColor.gradient).frame(width: max(3, geo.size.width * ratio))
        }.frame(height: 10)
    }

    private func bars(_ rows: [(String, Int, String)], logos: [Platform] = [], icons: [(String, Color)] = []) -> some View {
        let maxV = max(1, rows.map(\.1).max() ?? 1)
        return VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                HStack(spacing: 8) {
                    if i < logos.count { PlatformLogo(platform: logos[i], size: 16) }
                    else if i < icons.count { Image(systemName: icons[i].0).foregroundStyle(icons[i].1).frame(width: 16) }
                    Text(r.0).lineLimit(1).frame(width: 150, alignment: .leading)
                    bar(Double(r.1) / Double(maxV))
                    Text(r.2).monospacedDigit().foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
                }
            }
        }
    }

    private func columns(_ data: [(String, Int)], height: CGFloat, labelEvery: Int) -> some View {
        let maxV = max(1, data.map(\.1).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(data.enumerated()), id: \.offset) { i, d in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3).fill(d.1 > 0 ? Color.accentColor.gradient : Color.secondary.opacity(0.15).gradient)
                        .frame(height: max(3, height * CGFloat(d.1) / CGFloat(maxV)))
                        .help("\(d.0) : \(d.1 >= 60 ? "\(d.1 / 60) h \(d.1 % 60) min" : "\(d.1)")")
                    Text(i % labelEvery == 0 ? d.0 : " ").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height + 16, alignment: .bottom)
    }
}

/// Runs its content builder only when SwiftUI evaluates this view, i.e. when a lazy stack shows it.
struct Deferred<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View { content() }
}
