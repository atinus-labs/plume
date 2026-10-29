#!/usr/bin/env bash
# Builds Plume as an AppImage inside Ubuntu 22.04, so it runs on any distro
# with glibc 2.35 or newer (an AppImage only runs where glibc is at least as
# new as where it was built). Builds the working tree, uncommitted changes
# included; untracked files that git ignores are left out.
#
#   tool/appimage/build.sh        → build/appimage/Plume-<version>-x86_64.AppImage
#
# Needs podman (or docker, via ENGINE=docker) and the Flutter SDK; set
# FLUTTER_ROOT if `flutter` isn't on PATH.
#
# GTK, WebKitGTK (webkit2gtk-4.1) and libsecret are not bundled: they come
# from the system, as for any GTK app.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
engine=${ENGINE:-podman}
flutter_bin=$(command -v flutter || echo "$HOME/development/flutter/bin/flutter")
flutter_root=${FLUTTER_ROOT:-$(cd "$(dirname "$(readlink -f "$flutter_bin")")/.." && pwd)}
pub_cache=${PUB_CACHE:-$HOME/.pub-cache}
version=$(sed -n 's/^version: *\([^+]*\).*/\1/p' "$root/app/pubspec.yaml")

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/src" "$work/out" "$pub_cache"
# A clean copy, so the container's build never trips over the host's.
git -C "$root" ls-files -z --cached --others --exclude-standard |
  (cd "$root" && tar --null -T - -c) | tar -x -C "$work/src"

"$engine" run --rm \
  -v "$flutter_root:$flutter_root" \
  -v "$pub_cache:/pub-cache" -e PUB_CACHE=/pub-cache \
  -v "$work:/work" -w /work/src \
  -e VERSION="$version" -e FLUTTER_ROOT="$flutter_root" \
  docker.io/library/ubuntu:22.04 \
  bash tool/appimage/inside.sh

mkdir -p "$root/build/appimage"
mv "$work"/out/*.AppImage "$root/build/appimage/"
ls -lh "$root"/build/appimage/*.AppImage
