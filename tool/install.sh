#!/usr/bin/env bash
# Builds Plume in release mode and installs it for the current user.
#
#   tool/install.sh                       # install to ~/.local
#   tool/install.sh --client file.json    # also install a Google OAuth client
#   PREFIX=/opt/plume tool/install.sh     # elsewhere
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
FLUTTER="${FLUTTER:-$(command -v flutter || echo "$HOME/development/flutter/bin/flutter")}"
CLIENT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --client) CLIENT="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

echo "› Building release bundle"
(cd "$ROOT/app" && "$FLUTTER" build linux --release)

BUNDLE="$ROOT/app/build/linux/x64/release/bundle"
APP_DIR="$PREFIX/lib/plume"
echo "› Installing to $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR" "$PREFIX/bin" "$PREFIX/share/applications" "$PREFIX/share/icons"
cp -r "$BUNDLE/." "$APP_DIR/"
ln -sf "$APP_DIR/plume" "$PREFIX/bin/plume"

# Point every Exec= line (the main entry and its actions) at the installed
# binary, quoted if the path has spaces.
EXEC="$PREFIX/bin/plume"
[[ "$EXEC" == *[[:space:]]* ]] && EXEC="\"$EXEC\""
DESKTOP_FILE="$PREFIX/share/applications/org.atinus.plume.desktop"
sed "s|^Exec=plume|Exec=$EXEC|" "$ROOT/app/linux/data/org.atinus.plume.desktop" > "$DESKTOP_FILE"
if command -v desktop-file-validate >/dev/null && ! desktop-file-validate "$DESKTOP_FILE"; then
  echo "! $DESKTOP_FILE has errors; desktops may ignore it" >&2
fi
cp -r "$ROOT/app/linux/data/icons/hicolor" "$PREFIX/share/icons/"
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t "$PREFIX/share/icons/hicolor" || true
# Refresh the caches desktops read MIME handlers from, so Plume is offered as
# the email app right away (KDE's cache is not rebuilt without kded, e.g. when
# using KDE's System Settings on Hyprland or sway).
command -v update-desktop-database >/dev/null && update-desktop-database -q "$PREFIX/share/applications" || true
for kbuildsycoca in kbuildsycoca6 kbuildsycoca5; do
  if command -v "$kbuildsycoca" >/dev/null; then
    "$kbuildsycoca" >/dev/null 2>&1 || true
    break
  fi
done

if [[ -n "$CLIENT" ]]; then
  CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/plume"
  mkdir -p "$CONFIG"
  install -m 600 "$CLIENT" "$CONFIG/google-oauth-client.json"
  echo "› Google OAuth client installed"
fi

echo "✓ Installed. Launch “Plume” from your app launcher, or run: plume"
echo "  To open email links in Plume: Settings → Default mail app, or your desktop's default applications settings"
echo "  Background start on login (Hyprland): add  exec-once = $PREFIX/bin/plume --background"
