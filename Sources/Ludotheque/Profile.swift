// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Model

struct GamerTag: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var platform: Platform = .steam
    var name = ""
    var url = ""
}

/// "Ranked" panel entry (LoL, Valorant, Rocket League, Overwatch…).
struct RankedEntry: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var game = ""
    var rank = ""          // "Diamant II"
    var mode = ""          // "Solo/Duo", "3v3"…
    var peak = ""          // best rank ever
    var season = ""

    /// Badge colour from usual tier names (FR / EN).
    var color: Color {
        let r = rank.lowercased()
        let tiers: [(String, Color)] = [
            ("challenger", .yellow), ("prédateur", .red), ("predator", .red), ("radiant", .yellow), ("immortal", .pink),
            ("grand", .red), ("master", .purple), ("maître", .purple), ("champion", .purple), ("diamant", .cyan), ("diamond", .cyan),
            ("émeraude", .green), ("emerald", .green), ("ascendant", .green), ("platine", .teal), ("platinum", .teal),
            ("or", .yellow), ("gold", .yellow), ("argent", .gray), ("silver", .gray), ("bronze", .brown), ("fer", .secondary), ("iron", .secondary),
        ]
        for (k, c) in tiers where r.contains(k) { return c }
        return .accentColor
    }
}

/// "Jeux maîtrisés" panel entry.
struct MasteryEntry: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var game = ""
    var level = 3          // 1…5
    var main = ""          // main character / role / weapon / deck
    var note = ""

    static let levels = ["", String(localized: "Débutant"), String(localized: "Intermédiaire"), String(localized: "Confirmé"), String(localized: "Expert"), String(localized: "Maître")]
    var levelName: String { Self.levels[max(1, min(5, level))] }
}

enum ProfilePanel: String, Codable, CaseIterable, Identifiable {
    case stats, ranked, mastery, favorites, recent, tags
    var id: String { rawValue }
    var title: String {
        switch self {
        case .stats: String(localized: "Statistiques")
        case .ranked: String(localized: "Classé")
        case .mastery: String(localized: "Jeux maîtrisés")
        case .favorites: String(localized: "Vitrine de jeux")
        case .recent: String(localized: "Joués récemment")
        case .tags: String(localized: "Pseudos")
        }
    }
    var symbol: String {
        switch self {
        case .stats: "chart.bar.fill"
        case .ranked: "trophy.fill"
        case .mastery: "star.circle.fill"
        case .favorites: "rectangle.stack.fill"
        case .recent: "clock.fill"
        case .tags: "person.text.rectangle.fill"
        }
    }
}

struct Profile: Codable {
    var displayName = ""
    var tagline = ""
    var bio = ""
    var country = ""
    var avatarPath: String?
    var bannerPath: String?
    var theme = 0                      // index in ProfileTheme.all
    var memberSince = Date()
    var tags: [GamerTag] = []
    var ranked: [RankedEntry] = []
    var mastery: [MasteryEntry] = []
    var showcase: [String] = []        // group keys shown in the games showcase
    var panels: [ProfilePanel] = [.tags, .stats, .ranked, .mastery, .favorites, .recent]
    var hiddenPanels: Set<ProfilePanel> = []

    init() {}

    // Tolerant decoding: a field added in a later version never wipes the profile.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Profile()
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? d.displayName
        tagline = try c.decodeIfPresent(String.self, forKey: .tagline) ?? d.tagline
        bio = try c.decodeIfPresent(String.self, forKey: .bio) ?? d.bio
        country = try c.decodeIfPresent(String.self, forKey: .country) ?? d.country
        avatarPath = try c.decodeIfPresent(String.self, forKey: .avatarPath)
        bannerPath = try c.decodeIfPresent(String.self, forKey: .bannerPath)
        theme = try c.decodeIfPresent(Int.self, forKey: .theme) ?? d.theme
        memberSince = try c.decodeIfPresent(Date.self, forKey: .memberSince) ?? d.memberSince
        tags = try c.decodeIfPresent([GamerTag].self, forKey: .tags) ?? []
        ranked = try c.decodeIfPresent([RankedEntry].self, forKey: .ranked) ?? []
        mastery = try c.decodeIfPresent([MasteryEntry].self, forKey: .mastery) ?? []
        showcase = try c.decodeIfPresent([String].self, forKey: .showcase) ?? []
        panels = try c.decodeIfPresent([ProfilePanel].self, forKey: .panels) ?? d.panels
        hiddenPanels = try c.decodeIfPresent(Set<ProfilePanel>.self, forKey: .hiddenPanels) ?? []
    }
}

struct ProfileTheme {
    let name: String
    let colors: [Color]
    static let all: [ProfileTheme] = [
        ProfileTheme(name: String(localized: "Nuit"), colors: [Color(red: 0.11, green: 0.14, blue: 0.27), Color(red: 0.29, green: 0.16, blue: 0.45)]),
        ProfileTheme(name: String(localized: "Néon"), colors: [Color(red: 0.95, green: 0.2, blue: 0.55), Color(red: 0.25, green: 0.3, blue: 0.95)]),
        ProfileTheme(name: String(localized: "Forêt"), colors: [Color(red: 0.05, green: 0.3, blue: 0.2), Color(red: 0.4, green: 0.6, blue: 0.2)]),
        ProfileTheme(name: String(localized: "Lave"), colors: [Color(red: 0.5, green: 0.05, blue: 0.05), Color(red: 0.95, green: 0.45, blue: 0.1)]),
        ProfileTheme(name: String(localized: "Océan"), colors: [Color(red: 0.0, green: 0.25, blue: 0.45), Color(red: 0.0, green: 0.65, blue: 0.75)]),
        ProfileTheme(name: String(localized: "Or"), colors: [Color(red: 0.35, green: 0.25, blue: 0.05), Color(red: 0.85, green: 0.65, blue: 0.2)]),
        ProfileTheme(name: String(localized: "Graphite"), colors: [Color(white: 0.12), Color(white: 0.35)]),
    ]
    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
}

@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()
    @Published var profile: Profile = Store<Profile>.load("profile.json", Profile()) { didSet { scheduleSave() } }
    @Published var editing = false
    private var saveTask: Task<Void, Never>?

    private func scheduleSave() {
        saveTask?.cancel()
        let p = profile
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            Store<Profile>.save("profile.json", p)
        }
    }

    func reload() { profile = Store<Profile>.load("profile.json", Profile()) }

    var theme: ProfileTheme { ProfileTheme.all[min(max(0, profile.theme), ProfileTheme.all.count - 1)] }

    func toggleShowcase(_ key: String) {
        if let i = profile.showcase.firstIndex(of: key) { profile.showcase.remove(at: i) }
        else { profile.showcase.append(key) }
    }

    /// Copies a picked image into the support folder (survives the original being moved).
    func pickImage(banner: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let u = panel.url else { return }
        let dest = Paths.userCovers.appendingPathComponent("\(banner ? "banner" : "avatar")-\(Int(Date().timeIntervalSince1970)).\(u.pathExtension)")
        guard (try? FileManager.default.copyItem(at: u, to: dest)) != nil else { return }
        if banner { profile.bannerPath = dest.path } else { profile.avatarPath = dest.path }
    }
}

// MARK: - Derived stats (Steam-like level)

struct ProfileStats {
    let games: Int
    let installed: Int
    let hours: Int
    let completed: Int
    let platforms: Int
    let favoritePlatform: Platform?
    let level: Int
    let xp: Int
    let nextLevelXP: Int

    @MainActor
    init(_ lib: Library) {
        games = lib.groups.count
        installed = lib.count(Scope.installed)
        hours = lib.groups.map(lib.playtime).reduce(0, +) / 60
        completed = lib.groups.filter { [.beaten, .completed].contains(lib.statusOf($0)) }.count
        platforms = lib.platforms.count
        var perPlatform = [Platform: Int]()
        for g in lib.groups { for p in g.platforms { perPlatform[p, default: 0] += lib.playtime(g) } }
        favoritePlatform = perPlatform.max { $0.value < $1.value }?.key
        xp = games * 5 + hours * 2 + completed * 50 + platforms * 25
        level = Int((Double(xp) / 100).squareRoot())
        nextLevelXP = (level + 1) * (level + 1) * 100
    }
}

// MARK: - Sharing / export

struct ShareOptions: Equatable {
    var identity = true
    var tags = true
    var stats = true
    var ranked = true
    var mastery = true
    var showcase = true
    var recent = false
    var bio = true
}

enum ShareFormat: String, CaseIterable, Identifiable {
    case png = "PNG", jpeg = "JPEG", pdf = "PDF", csv = "CSV", json = "JSON", markdown = "Markdown"
    var id: String { rawValue }
    var type: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .pdf: .pdf
        case .csv: .commaSeparatedText
        case .json: .json
        case .markdown: UTType(filenameExtension: "md") ?? .plainText
        }
    }
    var isImage: Bool { [.png, .jpeg, .pdf].contains(self) }
}

@MainActor
enum ProfileExport {
    struct Content {
        let profile: Profile
        let stats: ProfileStats
        let showcase: [(String, NSImage?)]
        let recent: [(String, Int)]
        let avatar: NSImage?
        let banner: NSImage?
        let logos: [Platform: NSImage]
    }

    static func gather(_ lib: Library, _ store: ProfileStore, _ o: ShareOptions) async -> Content {
        let p = store.profile
        var showcase = [(String, NSImage?)]()
        if o.showcase {
            for key in p.showcase.prefix(6) {
                guard let g = lib.groups.first(where: { $0.key == key }) else { continue }
                showcase.append((lib.title(g), await CoverStore.shared.image(for: lib.coverGame(g))))
            }
        }
        let recent = lib.groups.filter { lib.lastPlayed($0) != nil }.sorted { lib.lastPlayed($0)! > lib.lastPlayed($1)! }
            .prefix(5).map { (lib.title($0), lib.playtime($0)) }
        for t in p.tags { LogoCache.shared.request(t.platform) }
        return Content(profile: p, stats: ProfileStats(lib), showcase: showcase, recent: Array(recent),
                       avatar: p.avatarPath.flatMap(NSImage.init(contentsOfFile:)),
                       banner: p.bannerPath.flatMap(NSImage.init(contentsOfFile:)), logos: LogoCache.shared.images)
    }

    static func export(_ c: Content, theme: ProfileTheme, options o: ShareOptions, format: ShareFormat) -> Data? {
        switch format {
        case .png, .jpeg, .pdf:
            let renderer = ImageRenderer(content: ProfileCard(content: c, theme: theme, options: o).frame(width: 900))
            renderer.scale = 2
            if format == .pdf {
                let data = NSMutableData()
                renderer.render { size, draw in
                    var box = CGRect(origin: .zero, size: size)
                    guard let consumer = CGDataConsumer(data: data as CFMutableData),
                          let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
                    ctx.beginPDFPage(nil)
                    draw(ctx)
                    ctx.endPDFPage()
                    ctx.closePDF()
                }
                return data as Data
            }
            guard let cg = renderer.cgImage else { return nil }
            let rep = NSBitmapImageRep(cgImage: cg)
            return rep.representation(using: format == .png ? .png : .jpeg, properties: [.compressionFactor: 0.9])
        case .csv:
            var rows = [[String(localized: "Section"), String(localized: "Clé"), String(localized: "Valeur"), String(localized: "Détail")]]
            let p = c.profile
            if o.identity { rows += [[String(localized: "Profil"), String(localized: "Nom"), p.displayName, p.tagline], [String(localized: "Profil"), String(localized: "Pays"), p.country, ""]] }
            if o.bio, !p.bio.isEmpty { rows.append([String(localized: "Profil"), String(localized: "Bio"), p.bio, ""]) }
            if o.tags { rows += p.tags.map { [String(localized: "Pseudo"), $0.platform.name, $0.name, $0.url] } }
            if o.stats {
                rows += [[String(localized: "Stats"), String(localized: "Niveau"), "\(c.stats.level)", "\(c.stats.xp) XP"], [String(localized: "Stats"), String(localized: "Jeux"), "\(c.stats.games)", ""],
                         [String(localized: "Stats"), String(localized: "Heures de jeu"), "\(c.stats.hours)", ""], [String(localized: "Stats"), String(localized: "Jeux terminés"), "\(c.stats.completed)", ""]]
            }
            if o.ranked { rows += p.ranked.map { [String(localized: "Classé"), $0.game, $0.rank, [$0.mode, $0.season, $0.peak.isEmpty ? "" : String(localized: "Pic : \($0.peak)")].filter { !$0.isEmpty }.joined(separator: " · ")] } }
            if o.mastery { rows += p.mastery.map { [String(localized: "Maîtrise"), $0.game, $0.levelName, [$0.main, $0.note].filter { !$0.isEmpty }.joined(separator: " · ")] } }
            if o.showcase { rows += c.showcase.map { [String(localized: "Vitrine"), $0.0, "", ""] } }
            if o.recent { rows += c.recent.map { [String(localized: "Récent"), $0.0, "\($0.1 / 60) h", ""] } }
            let esc: (String) -> String = CSV.escape
            return rows.map { $0.map(esc).joined(separator: ",") }.joined(separator: "\n").data(using: .utf8)
        case .json:
            var d = [String: Any]()
            let p = c.profile
            if o.identity { d["nom"] = p.displayName; d["devise"] = p.tagline; d["pays"] = p.country }
            if o.bio { d["bio"] = p.bio }
            if o.tags { d["pseudos"] = p.tags.map { ["plateforme": $0.platform.name, "pseudo": $0.name, "url": $0.url] } }
            if o.stats { d["stats"] = ["niveau": c.stats.level, "xp": c.stats.xp, "jeux": c.stats.games, "heures": c.stats.hours, "termines": c.stats.completed] }
            if o.ranked { d["classe"] = p.ranked.map { ["jeu": $0.game, "rang": $0.rank, "mode": $0.mode, "saison": $0.season, "pic": $0.peak] } }
            if o.mastery { d["maitrise"] = p.mastery.map { ["jeu": $0.game, "niveau": $0.levelName, "main": $0.main, "note": $0.note] } }
            if o.showcase { d["vitrine"] = c.showcase.map(\.0) }
            if o.recent { d["recents"] = c.recent.map { ["jeu": $0.0, "minutes": $0.1] } }
            return try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys])
        case .markdown:
            return markdown(c, o).data(using: .utf8)
        }
    }

    static func markdown(_ c: Content, _ o: ShareOptions) -> String {
        let p = c.profile
        var md = [String]()
        if o.identity { md.append("# \(p.displayName.isEmpty ? String(localized: "Mon profil") : p.displayName)"); if !p.tagline.isEmpty { md.append("*\(p.tagline)*") } }
        if o.bio, !p.bio.isEmpty { md.append(p.bio) }
        if o.stats { md.append(String(localized: "**Niveau \(c.stats.level)** · \(c.stats.games) jeux · \(c.stats.hours) h de jeu · \(c.stats.completed) terminés")) }
        if o.tags, !p.tags.isEmpty { md.append("## " + String(localized: "Pseudos")); md += p.tags.map { "- **\($0.platform.name)** : \($0.name)" } }
        if o.ranked, !p.ranked.isEmpty { md.append("## " + String(localized: "Classé")); md += p.ranked.map { "- **\($0.game)** — \($0.rank)\($0.mode.isEmpty ? "" : " (\($0.mode))")\($0.peak.isEmpty ? "" : " · " + String(localized: "pic \($0.peak)"))" } }
        if o.mastery, !p.mastery.isEmpty { md.append("## " + String(localized: "Jeux maîtrisés")); md += p.mastery.map { "- **\($0.game)** — \($0.levelName)\($0.main.isEmpty ? "" : " · \($0.main)")" } }
        if o.showcase, !c.showcase.isEmpty { md.append("## " + String(localized: "Vitrine")); md += c.showcase.map { "- \($0.0)" } }
        if o.recent, !c.recent.isEmpty { md.append("## " + String(localized: "Joués récemment")); md += c.recent.map { "- \($0.0) (\($0.1 / 60) h)" } }
        md.append(String(localized: "\n_Partagé depuis Ludothèque_"))
        return md.joined(separator: "\n\n")
    }
}

/// Static card rendered for image / PDF sharing (no async loading inside).
struct ProfileCard: View {
    let content: ProfileExport.Content
    let theme: ProfileTheme
    let options: ShareOptions

    var body: some View {
        let p = content.profile
        VStack(alignment: .leading, spacing: 18) {
            if options.identity {
                HStack(spacing: 18) {
                    avatar.frame(width: 110, height: 110).clipShape(RoundedRectangle(cornerRadius: 22)).shadow(radius: 8)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(p.displayName.isEmpty ? String(localized: "Joueur") : p.displayName).font(.system(size: 38, weight: .heavy))
                        if !p.tagline.isEmpty { Text(p.tagline).font(.title3).opacity(0.85) }
                        if options.stats {
                            HStack(spacing: 8) {
                                Text("Niveau \(content.stats.level)").font(.headline).padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(.white.opacity(0.2), in: Capsule())
                                if !p.country.isEmpty { Text(p.country).font(.headline) }
                            }
                        }
                    }
                    Spacer()
                }
            }
            if options.bio, !p.bio.isEmpty { Text(p.bio).font(.body).opacity(0.9) }
            if options.stats {
                HStack(spacing: 12) {
                    stat("\(content.stats.games)", String(localized: "jeux")); stat("\(content.stats.hours) h", String(localized: "de jeu"))
                    stat("\(content.stats.completed)", String(localized: "terminés")); stat("\(content.stats.platforms)", String(localized: "plateformes"))
                }
            }
            if options.tags, !p.tags.isEmpty {
                panel(String(localized: "Pseudos")) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                        ForEach(p.tags) { t in
                            HStack(spacing: 8) {
                                logo(t.platform).frame(width: 22, height: 22)
                                Text(t.name).font(.headline)
                                Text(t.platform.name).font(.caption).opacity(0.7)
                            }
                        }
                    }
                }
            }
            if options.ranked, !p.ranked.isEmpty {
                panel(String(localized: "Classé")) {
                    ForEach(p.ranked) { r in
                        HStack {
                            Image(systemName: "shield.fill").foregroundStyle(r.color).font(.title2)
                            VStack(alignment: .leading) {
                                Text(r.game).font(.headline)
                                Text([r.mode, r.season].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).opacity(0.7)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(r.rank).font(.headline).foregroundStyle(r.color)
                                if !r.peak.isEmpty { Text("Pic : \(r.peak)").font(.caption).opacity(0.7) }
                            }
                        }
                    }
                }
            }
            if options.mastery, !p.mastery.isEmpty {
                panel(String(localized: "Jeux maîtrisés")) {
                    ForEach(p.mastery) { m in
                        HStack {
                            Text(m.game).font(.headline)
                            if !m.main.isEmpty { Text("· \(m.main)").opacity(0.75) }
                            Spacer()
                            Text(String(repeating: "★", count: m.level) + String(repeating: "☆", count: 5 - m.level)).foregroundStyle(.yellow)
                            Text(m.levelName).font(.caption).opacity(0.8)
                        }
                    }
                }
            }
            if options.showcase, !content.showcase.isEmpty {
                panel(String(localized: "Vitrine")) {
                    HStack(spacing: 12) {
                        ForEach(Array(content.showcase.enumerated()), id: \.offset) { _, s in
                            VStack {
                                Group {
                                    if let img = s.1 { Image(nsImage: img).resizable().aspectRatio(contentMode: .fill) } else { Color.white.opacity(0.15) }
                                }
                                .frame(width: 110, height: 165).clipShape(RoundedRectangle(cornerRadius: 10))
                                Text(s.0).font(.caption).lineLimit(1).frame(width: 110)
                            }
                        }
                    }
                }
            }
            if options.recent, !content.recent.isEmpty {
                panel(String(localized: "Joués récemment")) {
                    ForEach(Array(content.recent.enumerated()), id: \.offset) { _, r in
                        HStack { Text(r.0); Spacer(); Text("\(r.1 / 60) h").opacity(0.7) }
                    }
                }
            }
            Text("Ludothèque").font(.caption.weight(.semibold)).opacity(0.6).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .foregroundStyle(.white)
        .padding(32)
        .background {
            ZStack {
                theme.gradient
                if let b = content.banner { Image(nsImage: b).resizable().aspectRatio(contentMode: .fill).opacity(0.35) }
            }
        }
        .clipped()
    }

    @ViewBuilder private var avatar: some View {
        if let a = content.avatar { Image(nsImage: a).resizable().aspectRatio(contentMode: .fill) }
        else {
            ZStack {
                Color.white.opacity(0.2)
                Text(String(content.profile.displayName.prefix(1)).uppercased()).font(.system(size: 50, weight: .bold))
            }
        }
    }

    @ViewBuilder private func logo(_ p: Platform) -> some View {
        if let img = content.logos[p] { Image(nsImage: img).resizable().clipShape(RoundedRectangle(cornerRadius: 5)) }
        else { Image(systemName: p.symbol).resizable().scaledToFit() }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading) {
            Text(v).font(.title.bold())
            Text(l).font(.caption).opacity(0.75)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func panel<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.caption.weight(.bold)).opacity(0.7)
            c()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
    }
}
