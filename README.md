# Liber

**Liber** est un client [Matrix](https://matrix.org) pour Android, habillé comme
WhatsApp : bandeau vert, onglets, discussions en bulles, badge de non-lus,
séparateurs de date et bouton d'envoi.

Il est écrit en **Dart/Flutter**, par-dessus le SDK Matrix
[`matrix`](https://pub.dev/packages/matrix), avec un chiffrement de bout en
bout fourni par [`vodozemac`](https://github.com/famedly/dart-vodozemac) (Rust).

> **Télécharger** : les APK signés sont publiés sur les
> [Releases](https://github.com/tear360/liber/releases).

## Fonctionnalités

- Connexion par mot de passe à **n'importe quel homeserver**
  (`matrix.org` par défaut, ou le vôtre), avec reprise automatique de session.
- Liste des conversations triée par activité, avec aperçu du dernier message,
  heure, badge de non-lus, cadenas des salons chiffrés et recherche.
- Écran de discussion : bulles vertes/blanches avec queue, séparateurs de date,
  noms d'expéditeurs colorés en groupe, accusés de réception (✓ / ✓✓),
  marquage lu, défilement vers le bas automatique.
- **Communautés** : liste des espaces Matrix et de leurs salons, l'équivalent
  des communautés WhatsApp.
- Nouvelle discussion directe à partir d'un identifiant Matrix (`@alice:org`).
- **Mise à jour automatique** : l'app interroge les GitHub Releases, télécharge
  l'APK plus récent et lance l'installateur système.
- Chiffrement de bout en bout via `vodozemac` (salons chiffrés lisibles).

## Mise à jour automatique

Le mécanisme tient en trois pièces :

1. [.github/workflows/build.yml](.github/workflows/build.yml) compile l'APK à
   chaque tag `v*` et le publie en **GitHub Release** avec un `versionName`
   dérivé du tag et un `versionCode` strictement croissant.
2. [lib/update/update_service.dart](lib/update/update_service.dart) interroge
   `GET /repos/tear360/liber/releases/latest`, compare la version du tag à
   `package_info_plus`, et télécharge l'asset `.apk` en suivant la progression.
3. L'APK est confié à l'installateur de Android via `open_filex`
   (permission `REQUEST_INSTALL_PACKAGES`).

Le repo est **public exprès** : Releases publiques accessibles sans
authentification, donc **aucun token GitHub embarqué dans l'APK**.

Une vérification a lieu au démarrage, puis toutes les 6 heures (limite de 60
requêtes/h pour les appels anonymes à l'API GitHub). La mise en cache est
désactivable et la recherche manuelle reste possible dans Paramètres.

## Construire depuis les sources

Prérequis : Flutter 3.47.6 (Dart 3.13.5), JDK 17, Android SDK 36.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

L'APK est produit dans `build/app/outputs/flutter-apk/app-release.apk`.

Sans `android/key.properties`, la sortie est signée avec la clé de **debug** :
utilisable en local, mais impossible à installer par-dessus d'une version
publiée. Pour une vraie signature :

```sh
keytool -genkeypair -v -keystore release.jks -alias liber \
  -keyalg RSA -keysize 2048 -validity 10000
```

puis dans `android/key.properties` :

```properties
storePassword=...
keyPassword=...
keyAlias=liber
storeFile=/chemin/absolu/vers/release.jks
```

Ce fichier est ignoré par git (`android/.gitignore`). En CI, il est reconstitué
à partir des secrets `ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS` et `ANDROID_KEY_PASSWORD`.

## Publier une version

```sh
# après avoir bumpé `version:` dans pubspec.yaml
git commit -am "Release v1.1.0"
git tag v1.1.0
git push origin main --tags
```

La branche compile l'APK en artefact ; le **tag** crée la Release, ce qui rend
la mise à jour disponible dans l'app.

## Structure

```
lib/
  main.dart                 point d'entrée et thème
  theme.dart                palette et composants à la WhatsApp
  matrix/matrix_service.dart  client Matrix, session, connexion
  update/update_service.dart  vérification, téléchargement, installation
  screens/                  splash, connexion, accueil, discussion,
                            liste, communautés, paramètres
  widgets/                  avatar, ligne de conversation, bulle de message
android/                    configuration Gradle et signature
.github/workflows/          build et publication des Releases
```

## Licence

[AGPL-3.0-or-later](LICENSE) — obligatoire, le SDK `matrix` étant sous AGPL.
