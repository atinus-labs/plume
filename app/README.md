# Plume app

See the [project README](../README.md) for setup, development, and installation.

## App icon

`assets/branding/plume.png` is the original transparent artwork. The Flutter
logo, Linux window icon, and tray renderer all use this asset. The tray overlays
the unread badge without recoloring the artwork.

After replacing the source image, regenerate the Linux hicolor and Android
launcher sizes from this directory:

```sh
PLUME_ICON=1 flutter test test/screens/icon_test.dart
```

The same command writes tray previews, with and without unread badges, to
`build/screens/`. Commit the generated platform icons with the source asset.

`../tool/install.sh` installs the Linux launcher icons and refreshes the desktop
icon cache. Notifications and autostart use the same desktop icon name.
