#!/bin/sh
# Builds dist/Ponder.app: the Swift panel app plus the ponder-feed helper beside it in
# Contents/MacOS (where the app looks for it), signed with your Developer ID (hardened runtime
# and a secure timestamp, as notarization requires).
#
#   scripts/bundle.sh                    this machine's architecture
#   scripts/bundle.sh --universal        Apple Silicon + Intel in one bundle (what ships)
#   scripts/bundle.sh --universal --dmg  also dist/Ponder.dmg
#   scripts/bundle.sh --dmg-only         wrap the dist/Ponder.app already there, untouched
#
# --dmg-only is for the release workflow, which notarizes and staples the app between the two
# steps so the app inside the disk image carries its own ticket.
#
# PONDER_SIGN_IDENTITY picks the certificate; without it the first "Developer ID Application"
# in the keychain is used, and with none at all the app is signed ad hoc (runs here only).
# The version comes from the VERSION file.
set -eu

universal=false
dmg=false
build=true
for arg in "$@"; do
  case "$arg" in
    --universal) universal=true ;;
    --dmg) dmg=true ;;
    --dmg-only) dmg=true build=false ;;
    *) echo "usage: bundle.sh [--universal] [--dmg | --dmg-only]" >&2; exit 2 ;;
  esac
done

root=$(cd "$(dirname "$0")/.." && pwd)
dist="$root/dist"
app="$dist/Ponder.app"
bundle_id="com.helloform.ponder"
version=$(tr -d '[:space:]' < "$root/VERSION")

cd "$root"
identity=${PONDER_SIGN_IDENTITY:-$(security find-identity -v -p codesigning |
  sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -n1)}

sign() {  # sign <path> [identifier]
  if [ -n "$identity" ]; then
    codesign --force --options runtime --timestamp ${2:+--identifier "$2"} --sign "$identity" "$1"
  else
    codesign --force ${2:+--identifier "$2"} --sign - "$1"
  fi
}

if $build; then
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

  if $universal; then
    for target in aarch64-apple-darwin x86_64-apple-darwin; do
      echo "Building ponder-feed for ${target}…"
      (cd feed && cargo build --release --locked --target "$target")
    done
    lipo -create -output "$app/Contents/MacOS/ponder-feed" \
      feed/target/aarch64-apple-darwin/release/ponder-feed \
      feed/target/x86_64-apple-darwin/release/ponder-feed
    swift_args="-c release --arch arm64 --arch x86_64"
  else
    echo "Building ponder-feed…"
    (cd feed && cargo build --release --locked)
    cp feed/target/release/ponder-feed "$app/Contents/MacOS/ponder-feed"
    swift_args="-c release"
  fi
  echo "Building Ponder…"
  # shellcheck disable=SC2086
  swift build $swift_args
  # shellcheck disable=SC2086
  cp "$(swift build $swift_args --show-bin-path)/Ponder" "$app/Contents/MacOS/Ponder"

  # LSUIElement: a menu-bar app, with no Dock icon from the first moment of launch.
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Ponder</string>
  <key>CFBundleDisplayName</key><string>Ponder</string>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleExecutable</key><string>Ponder</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

  if [ -n "$identity" ]; then
    echo "Signing as ${identity}…"
  else
    echo "No Developer ID certificate found: signing ad hoc (cannot be notarized)." >&2
  fi
  # The helper is signed on its own first: codesign does not sign loose binaries in MacOS/.
  sign "$app/Contents/MacOS/ponder-feed" "$bundle_id.feed"
  sign "$app"
  codesign --verify --deep --strict --verbose=2 "$app"
  echo "Done: $app ($(du -sh "$app" | cut -f1))"
else
  test -d "$app" || { echo "no $app to wrap: build it first" >&2; exit 1; }
fi

if $dmg; then
  out="$dist/Ponder.dmg"
  staging=$(mktemp -d)
  trap 'rm -rf "$staging"' EXIT
  cp -R "$app" "$staging/Ponder.app"
  ln -s /Applications "$staging/Applications"
  rm -f "$out"
  hdiutil create -volname Ponder -srcfolder "$staging" -fs HFS+ -format UDZO -quiet "$out"
  if [ -n "$identity" ]; then
    codesign --force --timestamp --sign "$identity" "$out"
  fi
  echo "Done: $out ($(du -sh "$out" | cut -f1))"
fi
