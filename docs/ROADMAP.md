# Roadmap Matrix de Liber

Analyse du dépôt et plan de développement vis-à-vis de la spécification complète
(sections 1 à 30). Dernière mise à jour : 9 octobre 2026 (v1.0.6).

Légende des états :

| État | Signification |
| --- | --- |
| ✅ terminée | Fonctionnelle, testée, visible dans l'app. |
| 🟡 partielle | Existe mais avec les limites listées. |
| ⬜ à faire | Absente de l'app. |
| 🚫 bloquée | Empêchée par le SDK, le protocole ou un service externe. |

---

# 1. Analyse du projet et de la stack

## Stack existante

| Élément | Choix | Version |
| --- | --- | --- |
| Framework | Flutter (Android uniquement aujourd'hui) | canal stable 3.47.6 en CI |
| Langage | Dart | sdk ^3.13.5 |
| SDK Matrix | `matrix` (Famedly, matrix-dart-sdk) | 13.0.0 |
| Chiffrement | `flutter_vodozemac` (Olm/Megolm, via le SDK) | 0.8.1 |
| Stockage local | `sqflite` (base `MatrixSdkDatabase`) | 2.4.4+1 |
| Thèmes | palette maison claire/sombre + `ThemeMode` | — |
| Mise à jour | GitHub Releases + `open_filex` + `permission_handler` | — |
| CI/CD | GitHub Actions : analyze → test → APK signé → release | — |

**Architecture actuelle** : `MatrixService` (singleton `ChangeNotifier`) détient le
seul `Client`, ouvre la base et expose l'état ; les écrans lisent `MatrixService.instance`
et les mises à jour temps réel viennent de `Client.onSync`, des `Timeline` et des
stream de l'écran. Aucune couche « use-case » : la logique métier vit soit dans
`MatrixService`, soit dans les écrans.

**Tests actuels** : `test/widget_test.dart` (parsing de version de l'updater),
`test/theme_test.dart` (palette claire/sombre, thème sombre, persistance du mode).
CI : `flutter analyze` (0 issue) + `flutter test` (6 tests) obligatoires.

**Fichiers** : 16 fichiers Dart sous `lib/` (10 écrans, 4 widgets, `theme.dart`,
`matrix_service.dart`, `update_service.dart`).

---

# 2. État des fonctionnalités par section

## 1. Authentification et gestion des comptes — 🟡 partielle

- ✅ Connexion serveur personnalisé + validation `checkHomeserver` (login, URL dérivée
  de l'identifiant `@user:domaine`).
- ✅ Identifiant + mot de passe, messages d'erreur traduits
  (`MatrixService.describeMatrixError`).
- ✅ Session restaurée au redémarrage, déconnexion propre, expiration gérée (SDK).
- ⬜ SSO / OAuth 2.0 / OIDC (le SDK expose `ssoLogin`, aucune UI).
- ⬜ Avatar en photo de profil (nom affiché modifiable ✅).
- ⬜ Ajout/suppression/comptes multiples → voir §22.
- Fichiers : `lib/screens/login_screen.dart`, `lib/matrix/matrix_service.dart`.

## 2. Interface principale — 🟡 partielle

- ✅ Navigation en barre inférieure (Discussions / Communautés / Appels / Compte),
  listes vides explicites, erreurs compréhensibles, avatars, compteurs d'non lus,
  spinner de synchro, transitions Material 3, préférence de thème persistée.
- 🟡 Barre latérale : remplacée par une barre inférieure ; aucune vue tablette/ordinateur.
- ⬜ Panneau d'informations du salon, recherche globale, préférences d'interface
  au-delà du thème, navigation clavier complète, audit d'accessibilité.

## 3. Messagerie — 🟡 partielle

- ✅ Envoi/réception temps réel, historique paginé, horodatages, états d'envoi
  (attente/envoyé/erreur), reprise après déconnexion sans doublon, contenus longs,
  messages système (membres, noms, sujets, chiffrement), défense contre les événements
  malformés (écran non plus noire).
- 🟡 « Entrée » : `onSubmitted` envoie, mais **aucun contrôle de la touche Entrée
  dans le champ multiligne** (pas de Shift+Entrée configurable).
- 🟡 Événements modifiés/supprimés : le SDK agrège les remplacements, l'app n'affiche
  pas encore l'indicateur « modifié » ni l'effacement des messages retirés.
- ✅ Appui long sur une bulle : **répondre** (citation + `m.in_reply_to`),
  **copier** le texte ou l'identifiant de l'événement, **modifier** ses messages
  (`m.replace`, libellé « modifié »), **supprimer** (redaction, avec confirmation).
- ⬜ Réactions, partage, mentions, aperçus d'URL, aperçus de médias reçus.

## 4. Threads — ⬜ à faire

Le SDK connaît la relation `m.thread` (`Event.thread`) mais n'a pas de séquence
d'envoi dédiée ; il faut composer `relates_to` côté app et filtrer le timeline.
Compatibilité avec les salons sans threads : éventements relationnels normaux.

## 5. Salons Matrix — 🟡 partielle

- ✅ Liste des salons, ouverture/quit (`room.leave`), invitations (accepter),
  création de DM (`startDirectChat`), messages d'erreur de permission.
- ⬜ Création de salon, join par identifiant/alias/lien, nom/sujet/avatar du salon,
  visibilité, liste des membres et niveaux, favoris/épinglés, archivés, lecture seule.
- Fichier : `lib/screens/chat_screen.dart`, `lib/screens/chats_tab.dart`.

## 6. Espaces Matrix — 🟡 partielle

- ✅ Liste des espaces, navigation vers leurs salons, invitations.
- ⬜ Hiérarchie sous-espaces, création, ajout/retrait de salons, espaces publics
  et découverte, permissions, organisation personnelle.

## 7. DMs et contacts — 🟡 partielle

- ✅ Liste des DMs, création d'un DM, invitations, appareils/état de vérification (§11).
- ⬜ Recherche d'utilisateurs, fiche de profil tiers, présence, épinglage,
  marquage non-lu, masquage, blocage.

## 8. Recherche — 🟡 partielle

- ✅ Recherche locale sur la liste des conversations (nom + aperçu).
- 🚫 Recherche serveur : l'endpoint `/search` n'est **pas exposé par matrix 13.0.0**
  → recherche locale sur l'historique synchronisé, avec limite affichée.
- ⬜ Recherche dans le salon, par auteur/période, navigation vers le résultat.

## 9. Médias et pièces jointes — 🟡 partielle

- ✅ Télémétrie des avatars via `getContentThumbnail`.
- ⬜ Envoi (images/vidéos/fichiers/audio), affichage des médias reçus (aujourd'hui
  un texte « 📷 Photo »), prévisualisation, galerie, lecteurs, progression,
  annulation, réessai, médias chiffrés (le SDK gère le chiffrement d'upload).

## 10. Chiffrement et sécurité — ✅ terminée (avec réserves)

- ✅ E2EE activée (`flutter_vodozemac`), envoi/réception chiffrés, clés gérées par
  le SDK, restauration par clé de récupération (SSSS + sauvegarde serveur),
  vérification de session, erreurs de déchiffrement affichées comme telles,
  aucun secret dans les journaux, aucun contournement du SDK.
- 🟡 Liste des appareils de l'utilisateur et des interlocuteurs : non exposée dans
  l'UI (l'état de vérification de *cet* appareil l'est).
- ⬜ Indicateurs visuels de vérification par message/appareil tiers.

## 11. Vérification simplifiée des appareils — ✅ terminée

Écran guidé (émojis SAS), entrées « profil/paramètres » et demandes entrantes,
confirmation explicite, état final, annulation, erreurs lisibles, état de confiance
mis à jour dans le SDK. Testée en build, **non testée en conditions réelles**
(pas d'appareil secondaire ici) → voir « tests manquants » ci-dessous.

## 12. Notifications — 🟡 partielle

- ✅ Compteurs et badge de navigation, état non-lu, notifications par pièce de code.
- 🚫 Push réseau : nécessite une passerelle Matrix (sygnal/ntfy) → service externe.
- ⬜ Notifications locales (nouveaux messages/mentions), permission Android 13+,
  réglages par compte/salon (SDK : `room.setPushRuleState` déjà disponible),
  anti-doublon à la reconnexion.

## 13. Presence et indicateurs de lecture — 🟡 partielle

- ✅ Marquage lu (`setReadMarker`).
- ⬜ Indicateur « en train d'écrire » (SDK `setTyping`), affichage des accusés de
  lecture, statut présence (SDK `syncPresence`), marquage manuel non-lu.

## 14. Appels audio et vidéo — ⬜ à faire (réel, pas simulé)

- Le SDK embarque `VoIP` : `CallSession` 1:1, `GroupCallSession` mesh, backend
  LiveKit (état + clés E2EE), `WebRTCDelegate` à implémenter avec `flutter_webrtc`.
- 🚫 Serveur LiveKit + service JWT requis pour le mode SFU ; Jitsi = service séparé.
- ⬜ Tout côté app : `WebRTCDelegate`, permission `RECORD_AUDIO` (+ `CAMERA`),
  écran d'appel (micro/caméra/hangup/états), sonnerie, bouton d'appel.
- ⬜ Interop à valider avec Element (l'implémentation suit MSC3401 avec des
  déviations documentées, ex. `room_id` obligatoire sur les événements to-device).

## 15. Sondages — ⬜ à faire (⚠ SDK sans support MSC3381)

Le SDK ne connaît pas les types d'événements de sondage : l'app doit composer les
événements `org.matrix.msc3381.*` elle-même (envoi, agrégations de votes,
affichage des événements reçus d'autres clients). Faisable, mais à traiter comme
un module protocolaire avec tests, pas comme un simple widget.

## 16. Partage de position — ⬜ à faire

Type `m.location` présent dans le SDK ; il manque la permission de géolocalisation,
le prévisualiseur et l'ouverture dans un service cartographique.

## 17. Emojis, stickers et réactions — 🟡 partielle

- 🟡 Envoi de texte ; sélecteur d'émojis absent.
- ⬜ Réactions (SDK : `room.sendReaction`), affichage agrégé, émojis surdimensionnés,
  stickers (`m.sticker` géré côté rendu), packs (`m.emoticons` — à vérifier côté SDK).

## 18. Personnalisation de l'apparence — 🟡 partielle

- ✅ Thème clair, thème sombre, suivi du système, persistance (nouveau dans 1.0.6).
- ⬜ Couleur d'accent, densité, zoom, taille du texte, format 12/24 h,
  disposition des bulles, avatars, animations, synchronisation des préférences.

## 19. Profils et cartes utilisateur — 🟡 partielle

- ✅ Profil affiché, nom modifiable, identifiant affiché.
- ⬜ Photo d'avatar, copie d'identifiant, fiche de profil tiers, présence,
  actions (MP, vérification, blocage), carte personnalisable.

## 20. Glossaires personnalisés — ⬜ à faire (spécificité Liber)

Purement applicatif : stockage local (base SQLite dédiée ou compte `account_data`),
infobulle au survol, échappement HTML, édition, et signaler clairement que la
synchronisation entre appareils n'existe pas tant que rien n'est partagé.

## 21. Paramètres et synchronisation — 🟡 partielle

- ✅ Écran de paramètres (`settings_screen.dart`) : sécurité, mises à jour,
  à propos — **accessible depuis le menu ⋮ des Discussions et des onglets**.
- ⬜ Sections messagerie/notifications/audio-vidéo/accessibilité,
  réinitialisation, export/import, préférences de compte via `account_data`.

## 22. Comptes multiples — ⬜ à faire (gros chantier)

Un seul `Client` et une seule base (`liber.db`) par processus. Nécessite : base et
dossier de données isolés par compte, séparation des clés de chiffrement, bascule
de compte sans redémarrage, compteurs par compte, déconnexion indépendante.

## 23. Synchronisation et performances — 🟡 partielle

- ✅ Sync temps réel, reprise après coup, écho local avant confirmation serveur
  (état `EventStatus`), incrémental via `onSync`.
- 🚫 Sliding Sync : **absent de matrix 13.0.0** → `/sync` classique uniquement.
- ⬜ Liste de messages en `ListView.builder` (aujourd'hui une liste construite en
  bloc → risque sur les longues conversations), file de réessai, annulation des
  requêtes, indicateur d'état de synchro plus fin.

## 24. Administration et modération — ⬜ à faire

SDK : `inviteUser`, `kick`, `ban`, `redact`, niveaux de puissance. Aucune UI
(membres, promotion, expulsion, bannissement, réglages du salon, alias).

## 25. Journal de débogage et rapports — ⬜ à faire

`Logs()` existe côté SDK ; il manque l'écran de journal, le copier-coller des
diagnostics (version client/SDK), le formulaire de signalement, la désactivation
de télémétrie et les garde-fous « pas de secrets ».

## 26. Commandes et raccourcis — 🟡 partielle

- 🟡 Le SDK sait interpréter les commandes slash (`sendTextEvent(parseCommands:)`),
  mais l'app les désactive et n'offre ni aide ni complétion.
- ⬜ Raccourcis clavier, aide intégrée, distinction locale/protocole, vérification
  des permissions avant actions sensibles.

## 27. Installation et déploiement — 🟡 partielle

- ✅ Build Android reproduisible (CI), mise à jour in-app, documentation de build
  implicite dans le workflow.
- ⬜ Web/PWA (Flutter Web possible, mais `flutter_webrtc` et le son diffèrent),
  desktop, configuration d'homeserver par défaut / couleurs / logo par variable
  d'environnement, guide d'installation.

## 28. Architecture et qualité du code — 🟡 partielle

- 🟡 Modulaire par écran, séparation service/UI correcte, types stricts,
  gestion centralisée des erreurs ; **pas de couche métier dédiée**, tests rares.
- ⬜ Tests d'intégration contre un homeserver de test, tests de chiffrement et de
  permissions, non-régression, documentation des modules.
- ✅ Aucun faux bouton : les fonctions absentes affichent un message explicite.
- ✅ Aucun secret en source ; licences des dépendances : audit à faire (voir §5).

## 29. Compatibilité et interopérabilité — 🟡 partielle

- ✅ Événements inconnus tolérés (rendu défensif), salons chiffrés/non chiffrés gérés.
- ⬜ Détection des capacités du serveur (search, appels, SSO…) et messages
  « fonctionnalité non proposée par ce serveur ».

## 30. Exigences de processus — ✅ appliquée

Analyse d'abord (ce document), pas de maquette présentée comme fonctionnelle,
pas de comportement inventé, erreurs serveur remontées, chiffrement préservé,
limitations documentées.

---

# 3. Plan de développement par phases

Chaque phase est un ensemble de modules cohérents, livrés par une release.

## P0 — Fiabilité (fait : 1.0.3 → 1.0.6)

- ✅ Build CI réparé (pin `permission_handler`), APK signé vérifié.
- ✅ Vérification de session + restauration par clé de récupération.
- ✅ Message « réessayer les clés » après vérification.
- ✅ Correctif écran noir, correctif erreur de profil, thème sombre.

## P1 — Messagerie complète (en cours)

1. ✅ **Actions sur les messages** : répondre (aperçu), copier, éditer, supprimer
   (redaction), menu long-appui — `chat_screen.dart`, `message_bubble.dart`.
2. ⬜ **Réactions** : barre de réactions rapides, affichage agrégé, ajout/retrait
   (`room.sendReaction`) — nouveau `reaction_bar.dart`.
3. ✅ **Affichage des édits et suppressions** (libellé « modifié », message
   retiré retiré du fil).
4. ⬜ **Touche Entrée configurable** (envoyer vs retour à la ligne).
5. ⬜ Tests : agrégation de réactions, édition/suppression côté serveur ;
   ✅ tests de rendu de la citation et du libellé « modifié » ajoutés.

## P2 — Salons, espaces et recherche

- Fiche salon (membres, avatar/nom/sujet, niveaux de puissance, lecture seule),
  créer/rejoindre par alias, gérer les invitations.
- Espace : hiérarchie, ajouter/retirer un salon.
- Recherche locale dans l'historique du salon avec limite affichée.

## P3 — Médias, notifications, contacts

- Envoi/réception de médias (upload chiffré géré par le SDK), progression, réessai.
- Notifications locales + permission Android 13+, réglage par salon (push rules).
- Indicateurs de frappe et de lecture, fiche de profil tiers, blocage.

## P4 — Fonctionnalités Matrix avancées

- Threads, sondages (événements MSC3381 composés à l'app), stickers/emojis,
  position géographique, glossaire local, paramètres branchés et enrichis,
  journal de débogage.

## P5 — Envergure

- Comptes multiples (isolation par compte), appels 1:1 (WebRTC réel) puis groupe
  (mesh, puis LiveKit si un service est fourni), SSO/OIDC, adaptation tablette/web,
  tests d'intégration contre un homeserver de test.

---

# 4. Dépendances à ajouter (audit de licence obligatoire avant ajout)

| Dépendance | Usage | Section |
| --- | --- | --- |
| `flutter_webrtc` | appels audio/vidéo réels | §14 |
| `image_picker` + `file_picker` | envoi de médias | §9 |
| `flutter_local_notifications` | notifications locales | §12 |
| `geolocator` (ou équivalent) | partage de position | §16 |
| `emoji_picker_flutter` (ou équivalent) | sélecteur d'émojis/réactions | §17 |
| `url_launcher` | ouverture de liens/positions | §3, §16 |

Licences actuelles : `matrix` est **AGPL-3.0** → la licence de Liber doit rester
compatible et la source publique (déjà le cas). À vérifier avant chaque ajout :
licence de chaque paquet (`dart pub deps --style=tail` + page pub.dev) et absence
de copyleft incompatible.

---

# 5. Services externes, configuration serveur et permissions

| Besoin | Nécessaire pour | Bloquant ? |
| --- | --- | --- |
| Serveur TURN/STUN (`/_matrix/client/v3/voip/turnServer`) | appels | Oui pour les appels réels |
| Passerelle de push Matrix (sygnal/ntfy) + config serveur | notifications réseau | Oui pour le push, non pour les notifications locales |
| Serveur LiveKit + service de JWT | appels de groupe SFU | Oui pour le mode groupe « MatrixRTC » |
| Serveur Jitsi (option) | intégration Jitsi | Oui si choisi |
| SSO/OIDC configuré sur le homeserver | connexion SSO | Oui côté serveur |
| Limite de taille du dépôt média | envoi de fichiers | Dépend du serveur |
| Comptes de test sur un homeserver de test | tests d'intégration | Oui pour les tests |
| Permissions Android : `RECORD_AUDIO`, `CAMERA`, `POST_NOTIFICATIONS`, `ACCESS_FINE_LOCATION` | §14, §12, §16 | Selon la fonction |

Aucune de ces ressources n'est nécessaire pour les phases P1–P2.

---

# 6. Tests manquants aujourd'hui

- Flux de vérification et de restauration par clé de récupération : **non testés
  en conditions réelles** (aucun second appareil ni homeserver de test ici).
- Aucun test d'intégration Synapse/Dendrite ; aucun test d'envoi/réception réel.
- Recommandation : conteneur Synapse + deux comptes dans la CI pour P1 et au-delà
  (rédigé, pas encore implémenté).
