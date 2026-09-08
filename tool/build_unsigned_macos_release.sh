#!/bin/zsh

set -euo pipefail

MENO_ROOT="${0:A:h:h}"
MENO_DIST="$MENO_ROOT/dist"
MENO_APP="$MENO_ROOT/build/macos/Build/Products/Release/Meno.app"
MENO_DMG="$MENO_DIST/Meno.dmg"
MENO_STAGE="$(mktemp -d /private/tmp/meno-release.XXXXXX)"

cleanup() {
  case "$MENO_STAGE" in
    /private/tmp/meno-release.*) rm -rf -- "$MENO_STAGE" ;;
  esac
}
trap cleanup EXIT

cd "$MENO_ROOT"
mkdir -p "$MENO_DIST"

flutter pub get
flutter analyze
flutter test
flutter build macos --release

if [[ ! -d "$MENO_APP" ]]; then
  print -u2 "Release app was not created at $MENO_APP"
  exit 1
fi

ditto "$MENO_APP" "$MENO_STAGE/Meno.app"
ln -s /Applications "$MENO_STAGE/Applications"

hdiutil create \
  -volname "Meno" \
  -srcfolder "$MENO_STAGE" \
  -ov \
  -format UDZO \
  "$MENO_DMG"

hdiutil verify "$MENO_DMG"
codesign --verify --deep --strict --verbose=2 "$MENO_APP"

(
  cd "$MENO_DIST"
  shasum -a 256 Meno.dmg > Meno.dmg.sha256
)

MENO_VERSION="$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' \
  "$MENO_APP/Contents/Info.plist")"
MENO_SHA="$(awk '{print $1}' "$MENO_DIST/Meno.dmg.sha256")"

{
  print "# Meno $MENO_VERSION — Early Preview"
  print
  print "Meno is a private, local-first journal for macOS. This early preview"
  print "includes the full-page journal, daily binder, mood check-ins, optional"
  print "on-device organization, and optional Quiet Time workspace."
  print
  print "## Install"
  print
  print "1. Download and open Meno.dmg."
  print "2. Drag Meno into Applications."
  print "3. Try to open Meno once."
  print "4. Because this preview is unsigned, open System Settings → Privacy &"
  print "   Security, select Open Anyway, and confirm with Open."
  print
  print "Only use the security override when you downloaded Meno from this"
  print "repository."
  print
  print "## SHA-256"
  print
  print "    $MENO_SHA  Meno.dmg"
} > "$MENO_DIST/RELEASE_NOTES.md"

print
print "Unsigned Meno preview created:"
print "  App:      $MENO_APP"
print "  DMG:      $MENO_DMG"
print "  Checksum: $MENO_DIST/Meno.dmg.sha256"
print "  Notes:    $MENO_DIST/RELEASE_NOTES.md"
print
print "This preview is not notarized. Test the downloaded DMG on another Mac"
print "before sharing it beyond trusted preview users."
