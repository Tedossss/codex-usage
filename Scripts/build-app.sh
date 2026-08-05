#!/usr/bin/env bash
# Builds Tideline.app and installs it to ~/Applications.
# SwiftPM cannot emit a bundle, and a menu bar app needs one for LSUIElement and for
# SMAppService (open at login) to have something to register.
set -euo pipefail

root="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="${1:-release}"
destination="${TIDELINE_DEST:-$HOME/Applications/Tideline.app}"

swift build -c "$config" --package-path "$root"
binary="$(swift build -c "$config" --package-path "$root" --show-bin-path)/Tideline"

# The bundle is assembled in a scratch directory rather than in the repo: this checkout
# lives under an iCloud-synced Desktop, and codesign refuses to sign anything carrying the
# com.apple.FinderInfo and fileprovider xattrs that syncing attaches.
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
app="$staging/Tideline.app"

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Tideline"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"

# The keychain grants access per code signature. Without one, macOS asks for the Claude
# Code credentials on every single launch. The ad-hoc identity still changes whenever the
# binary does, so a rebuild asks once more.
codesign --force --sign - --identifier com.vasfal.tideline "$app"
codesign --verify --strict "$app"

mkdir -p "$(dirname "$destination")"
rm -rf "$destination"
ditto "$app" "$destination"

echo "$destination"
