# Plume

A fast mail client for the Linux desktop, built with Flutter and Material 3 Expressive. It supports Gmail and any IMAP/SMTP server, multiple accounts, real-time notifications and a system tray icon.

> [!NOTE]
> Plume is vibe-coded with AI assistance. Expect rapid iteration and occasional rough edges. Feedback, bug reports, and contributions are welcome.

## Features

- Unified inbox across accounts, with Gmail categories
- Gmail API or any IMAP/SMTP server, with automatic server discovery
- Local SQLite cache, optimistic actions that replay when back online, and offline reading
- Push notifications via IMAP IDLE, with Open, Archive and Mark as read actions
- Tray icon with unread count; closing the window keeps Plume running
- Remote images blocked by default; tracking pixels removed
- Compose with autocomplete, attachments, drafts, undo send and per-account signatures
- Instant local search, with server search on Enter
- Gmail-style keyboard shortcuts
- Follows the desktop's light/dark mode and accent colour

## Install

Requires Flutter 3.47+, `clang`, `cmake`, `ninja`, `pkgconf`, `gtk3` and `libsecret`.

```sh
tool/install.sh                                              # build and install to ~/.local
tool/install.sh --client ~/Downloads/client_secret_XXXX.json  # also install a Google OAuth client
```

Launch **Plume** from your app launcher, or run `plume`.

**Start on login:** GNOME, KDE, XFCE and Cinnamon use *Settings → Start on login*. On Hyprland, Sway and similar compositors, add `~/.local/bin/plume --background` to your startup commands.

## Adding accounts

**Other mail (IMAP/SMTP)**: enter your name, address and password. Plume discovers the server settings and verifies the login before saving. Most providers require an app password:

| Provider | Where to create one |
|---|---|
| Gmail | <https://myaccount.google.com/apppasswords> (requires 2-Step Verification) |
| iCloud | <https://account.apple.com> |
| Yahoo, AOL, Fastmail | Account security settings |

Outlook.com, Hotmail and Microsoft 365 are not supported.

**Google sign-in** uses the Gmail API and needs your own OAuth client:

1. In the [Google Cloud Console](https://console.cloud.google.com/), create a project and enable the **Gmail API**.
2. Under **Google Auth Platform**, set the audience to **External** and publish the app. Apps in *Testing* status have sign-ins expire every 7 days.
3. Add the scopes `https://mail.google.com/`, `openid`, `email` and `profile`.
4. Create a **Desktop app** client and download the JSON.
5. Select it in Plume (**Choose client file…**) or pass it to `tool/install.sh --client`.

Google will warn that the app is unverified, since the client is yours. Choose **Advanced → Go to Plume**. Unverified clients are limited to 100 users.

## Data locations

| Data | Location |
|---|---|
| Mail cache | `~/.local/share/plume/mail.sqlite` |
| Google client | `~/.config/plume/google-oauth-client.json` |
| Tokens and passwords | System keyring, or a private file if none is available |
| Autostart entry | `~/.config/autostart/org.atinus.plume.desktop` |

## Architecture

A Dart pub workspace. Provider and store interfaces are kept separate so new providers and platforms can be added.

| Package | Purpose |
|---|---|
| `app` | Flutter app (Riverpod) and GTK runner |
| `packages/plume_core` | Mail model, provider and store contracts, sync engine, operation queue, outbox |
| `packages/plume_gmail` | Gmail API provider with OAuth (PKCE) and incremental sync |
| `packages/plume_imap` | IMAP/SMTP provider, threading and server discovery |
| `packages/plume_mime` | MIME parsing and building |
| `packages/plume_store` | SQLite storage (drift), full-text search |
| `packages/plume_linux` | D-Bus integration: tray, notifications, portal, autostart |
| `packages/plume_design` | Material 3 Expressive components and theme |

## Development

```sh
export PATH=$HOME/development/flutter/bin:$PATH
cd app

flutter run -d linux --dart-define=PLUME_DEMO=true    # demo account, no Google client needed
flutter test                                          # app tests
(cd ../packages/plume_imap && dart test)              # package tests; same for the other packages
../packages/plume_imap/tool/integration.sh            # IMAP against Dovecot in rootless podman
```

Set `PLUME_ALLOW_MULTIPLE_INSTANCES=1` to run more than one instance during development.

## Known limitations

- Plain-text composing only; no rich-text editor yet
- Complex newsletter layouts may render differently than in a browser
- GNOME needs the AppIndicator extension to show the tray icon
- `mailto:` links don't open Plume
- Snooze and scheduled send are unavailable for Gmail
- IMAP accounts: restoring a conversation from Trash moves all of it to the Inbox
