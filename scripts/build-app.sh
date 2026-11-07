#!/bin/zsh
# Builds a distributable Ludothèque: universal .app (Apple Silicon + Intel), a .dmg and a .pkg installer
# (the .pkg removes any previous version before installing).
#
# Nothing personal is embedded: user data lives in ~/Library/Application Support/Ludotheque,
# credentials in the Keychain, caches in ~/Library/Caches/Ludotheque — all created at first launch.
#
# Optional environment variables:
#   VERSION=1.2.1                         version number
#   BUNDLE_ID=app.ludotheque.Ludotheque   bundle identifier
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"   otherwise ad-hoc signature
#   NOTARY_PROFILE=profile                notarytool keychain profile (requires SIGN_IDENTITY)
#   SIGN_INSTALLER_IDENTITY="Developer ID Installer: Name (TEAMID)"   signs the .pkg
set -e
cd "${0:A:h}/.."

VERSION=${VERSION:-1.2.1}
BUNDLE_ID=${BUNDLE_ID:-app.ludotheque.Ludotheque}
NAME="Ludothèque"
DIST=dist
APP="$DIST/$NAME.app"

echo "▶ Compilation universelle (arm64 + x86_64)…"
# -file-prefix-map keeps the build machine's paths out of the binary.
swift build -c release --arch arm64 --arch x86_64 -Xswiftc -file-prefix-map -Xswiftc "$PWD=."
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Ludotheque"

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Ludotheque"
# Debug info stripped, function names kept (lets us profile a slow session).
strip -S "$APP/Contents/MacOS/Ludotheque"

if [[ ! -f Resources/AppIcon.icns ]]; then
  swift scripts/make-icon.swift "$DIST/AppIcon.iconset"
  iconutil -c icns "$DIST/AppIcon.iconset" -o Resources/AppIcon.icns
  rm -rf "$DIST/AppIcon.iconset"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# Translations: one .lproj folder per language (the French text is the key; English is the fallback).
cp -R Resources/*.lproj "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>Ludotheque</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>fr</string><string>en</string><string>es</string><string>de</string><string>it</string><string>pt</string><string>zh-Hans</string><string>ja</string></array>
  <key>NSHumanReadableCopyright</key><string>© 2026 jeremdevgit — GPL-3.0-or-later</string>
</dict></plist>
PLIST

# Safety net: refuse to ship if the build machine's home path leaked into the binary.
if strings -a "$APP/Contents/MacOS/Ludotheque" | grep -q "$HOME"; then
  echo "✗ Le binaire contient un chemin personnel ($HOME) — abandon." >&2; exit 1
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "▶ Signature Developer ID…"
  codesign --force --options runtime --timestamp -s "$SIGN_IDENTITY" "$APP"
else
  codesign --force -s - "$APP"
fi

echo "▶ Création de l'image disque…"
STAGE="$DIST/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/Ludotheque-$VERSION.dmg"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force -s "$SIGN_IDENTITY" "$DMG"
  if [[ -n "$NOTARY_PROFILE" ]]; then
    echo "▶ Notarisation…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  fi
fi

echo "▶ Paquet d'installation…"
PKGROOT="$DIST/pkgroot"
mkdir -p "$PKGROOT/Applications"
cp -R "$APP" "$PKGROOT/Applications/"
# Always install into /Applications (otherwise macOS may "update" a copy found elsewhere).
pkgbuild --analyze --root "$PKGROOT" "$DIST/component.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool false "$DIST/component.plist"
PKG="$DIST/Ludotheque-$VERSION.pkg"
pkgbuild --root "$PKGROOT" --ownership recommended --scripts scripts/pkg --component-plist "$DIST/component.plist" \
         --identifier "$BUNDLE_ID" --version "$VERSION" --install-location / "$PKG" >/dev/null
rm -rf "$PKGROOT" "$DIST/component.plist"
if [[ -n "$SIGN_INSTALLER_IDENTITY" ]]; then
  productsign --sign "$SIGN_INSTALLER_IDENTITY" "$PKG" "$PKG.signed" && mv "$PKG.signed" "$PKG"
fi
(cd "$DIST" && shasum -a 256 "Ludotheque-$VERSION.dmg" "Ludotheque-$VERSION.pkg" > SHA256SUMS.txt)

echo "✓ $PWD/$APP ($(du -sh "$APP" | cut -f1))"
echo "✓ $PWD/$DMG ($(du -sh "$DMG" | cut -f1))"
echo "✓ $PWD/$PKG ($(du -sh "$PKG" | cut -f1))"
