// SPDX-License-Identifier: GPL-3.0-or-later — Copyright (C) 2026 jeremdevgit — voir LICENSE
import SwiftUI

/// Logiciels de l'auteur (jeremdevgit), avec le lien de téléchargement officiel sur GitHub.
enum Author {
    static let name = "jeremdevgit"
    static let profile = URL(string: "https://github.com/jeremdevgit")!
    static let repo = URL(string: "https://github.com/jeremdevgit/ludotheque")!

    struct App: Identifiable {
        let name, platform, summary, symbol: String
        let tint: Color
        let url: URL
        var id: String { name }
    }

    static let apps: [App] = [
        App(name: "Boîte à outils", platform: "macOS et Windows",
            summary: "Entretien, nettoyage, réglages cachés, capteurs et diagnostic du Mac ou du PC.",
            symbol: "wrench.and.screwdriver.fill", tint: .blue,
            url: URL(string: "https://github.com/jeremdevgit/boite-a-outils/releases/latest")!),
        App(name: "Pomme", platform: "Windows",
            summary: "Lecteur de musique léger pour Apple Music et les fichiers audio locaux.",
            symbol: "music.note", tint: .pink,
            url: URL(string: "https://github.com/jeremdevgit/pomme/releases/latest")!),
        App(name: "rJb", platform: "Windows",
            summary: "L'éclairage RGB de tous les périphériques et composants dans une seule application.",
            symbol: "light.max", tint: .orange,
            url: URL(string: "https://github.com/jeremdevgit/rjb/releases/latest")!),
        App(name: "Suite Libre", platform: "Navigateur",
            summary: "Six outils sans compte : QR codes, flou d'images, photos, conversions, moyennes, mots de passe.",
            symbol: "lock.shield.fill", tint: .green,
            url: URL(string: "https://jeremdevgit.github.io/suite-libre/")!),
        App(name: "Batailles de France", platform: "Navigateur",
            summary: "Jeu de stratégie en temps réel sur les cartes de Lyon, Paris, Marseille, Bordeaux et Strasbourg.",
            symbol: "flag.2.crossed.fill", tint: .red,
            url: URL(string: "https://github.com/jeremdevgit/batailles-de-france/releases/latest")!),
    ]
}

/// Fenêtre « Mes logiciels » (menu Aide et Options → À propos).
struct MyAppsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mes logiciels").font(.title2.bold())
                Text("Ludothèque est créée par \(Author.name). Ses autres logiciels sont libres, gratuits et sans publicité.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Author.apps) { app in
                HStack(spacing: 12) {
                    Image(systemName: app.symbol)
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 8).fill(app.tint.gradient))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.headline) + Text("  ·  \(app.platform)").font(.caption).foregroundColor(.secondary)
                        Text(app.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Link("Télécharger", destination: app.url).buttonStyle(.borderedProminent)
                }
            }
            Divider()
            HStack {
                Link("Tous mes logiciels sur GitHub", destination: Author.profile)
                Spacer()
                Text("Chaque bouton ouvre la page officielle dans le navigateur.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .frame(width: 620)
    }
}
