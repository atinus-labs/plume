#!/usr/bin/env bash
# The part of build.sh that runs inside Ubuntu 22.04.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  ca-certificates clang cmake curl file git libgtk-3-dev liblzma-dev \
  libsecret-1-dev libstdc++-12-dev libwebkit2gtk-4.1-dev ninja-build \
  pkg-config unzip xz-utils >/dev/null
git config --global --add safe.directory '*'
export PATH="$FLUTTER_ROOT/bin:$PATH"

cd app
flutter --suppress-analytics pub get
flutter --suppress-analytics build linux --release

data=linux/data
app=/tmp/Plume.AppDir
mkdir -p "$app/usr/bin" "$app/usr/share/applications" "$app/usr/share/icons"
cp -r build/linux/x64/release/bundle/. "$app/usr/bin/"
install -m 755 ../tool/appimage/AppRun "$app/AppRun"
cp "$data/org.atinus.plume.desktop" "$app/"
cp "$data/org.atinus.plume.desktop" "$app/usr/share/applications/"
cp -r "$data/icons/hicolor" "$app/usr/share/icons/"
cp "$data/icons/hicolor/256x256/apps/org.atinus.plume.png" "$app/"
ln -s org.atinus.plume.png "$app/.DirIcon"

curl -fsSL -o /tmp/appimagetool \
  https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x /tmp/appimagetool
# No FUSE in a container, so the tool runs from an extracted copy.
ARCH=x86_64 /tmp/appimagetool --appimage-extract-and-run "$app" "/work/out/Plume-$VERSION-x86_64.AppImage"
