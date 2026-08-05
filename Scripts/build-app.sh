#!/usr/bin/env bash
# Builds "Claude Usage.app" and installs it to ~/Applications.

# SwiftPM cannot emit a bundle, and a menu bar app needs one for LSUIElement and for
# SMAppService (open at login) to have something to register.
set -euo pipefail

root="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="${1:-release}"
destination="${CLAUDE_USAGE_DEST:-$HOME/Applications/Claude Usage.app}"

swift build -c "$config" --package-path "$root"
binary="$(swift build -c "$config" --package-path "$root" --show-bin-path)/ClaudeUsage"

# The bundle is assembled in a scratch directory rather than in the repo: this checkout
# lives under an iCloud-synced Desktop, and codesign refuses to sign anything carrying the
# com.apple.FinderInfo and fileprovider xattrs that syncing attaches.
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
app="$staging/Claude Usage.app"

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/ClaudeUsage"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"

# The keychain grants access per code signature. Signing means one "Allow" instead of one
# per launch — though the ad-hoc identity changes whenever the binary does, so a rebuild
# does ask again.
codesign --force --sign - --identifier com.vasfal.claude-usage "$app"
codesign --verify --strict "$app"

mkdir -p "$(dirname "$destination")"
rm -rf "$destination"
ditto "$app" "$destination"

echo "$destination"
