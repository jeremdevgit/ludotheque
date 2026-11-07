# Historique des versions

## 1.2.1 — 2026-11-07 — Sécurité

- Refus explicite des URL non HTTPS ou contenant des identifiants avant les requêtes des intégrations. Éditeur documenté.

### English

- Reject non-HTTPS URLs and embedded URL credentials before integration requests. Document publisher identity.


## 1.2.0 — 2026-11-06

**English**

- **8 languages**: English, French, Spanish, German, Italian, Portuguese, Chinese and Japanese. Your Mac's language is picked automatically; *Options › General › Language* lets you switch (applies at the next launch, with a Relaunch button).
- Store descriptions and Xbox, PlayStation and GOG data are requested in the chosen language.
- Exports (HTML, profile CSV and Markdown) follow the chosen language.
- Building from source fixed (`Package.swift` manifest).

**Français**

- **8 langues** : français, anglais, espagnol, allemand, italien, portugais, chinois et japonais. La langue du Mac est choisie automatiquement ; *Options › Général › Langue* permet d'en changer (au prochain lancement, avec un bouton Relancer).
- Descriptions des boutiques et données Xbox, PlayStation et GOG demandées dans la langue choisie.
- Exports (HTML, CSV et Markdown du profil) dans la langue choisie.
- Compilation depuis les sources corrigée (manifeste `Package.swift`).

## 1.1.0 — 2026-11-05 — Publication open source

- Code publié sous licence GNU GPL v3 ou ultérieure.
- **Paquet d'installation `.pkg`** : l'ancienne version est fermée et retirée automatiquement avant l'installation ; bibliothèque, réglages et identifiants conservés. Empreintes SHA-256 publiées avec les installateurs.
- Crédit « jeremdevgit » (À propos, Options) et fenêtre **Mes logiciels** (menu Aide) avec le lien de téléchargement de chacun.
- Fluidité : grille AppKit par défaut, bibliothèque en Observation, jaquettes décodées en arrière-plan et cache mémoire plafonné, tableaux natifs (processeur au repos : 100 % → 1,5 % ; sélection d'un jeu : 100–400 ms → 15–60 ms).
- Assistant de premier démarrage, onglet Actualisations, mode manuel.
- Corrections : plantage au lancement (lecture des caractéristiques du Mac en arrière-plan), boucles de rafraîchissement, grille qui ne s'affichait plus au défilement, délai maximal de 12 s sur les jaquettes.

## 1.0.0

- Première version : bibliothèques Steam, Epic, GOG, Xbox, PlayStation, Nintendo, Battle.net et plus, émulateurs, mode TV, statistiques, succès, boutiques, jeux Windows.
