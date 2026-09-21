# MoriXterm

> A focused remote workspace for terminals, servers and files.

MoriXterm is a Qt 6 desktop client for developers, sysadmins and operators who want local shells, SSH, RDP and file operations in one fast workspace. It combines a real terminal, saved connection profiles, a two-pane transfer client and a security-first session manager without requiring a browser or a cloud account.

[Website](website/index.html) · [Latest release](https://github.com/mortenaho/morixterm/releases/latest) · [Security policy](SECURITY.md)

## What it supports

| Protocol | Best for | Included capabilities |
| --- | --- | --- |
| Local shell | Local development and administration | Native shell, terminal themes, zoom and clipboard |
| SSH | Linux/Unix servers and network devices | Real PTY on Linux, host-key verification, key files, password vault and compatibility profiles |
| RDP | Windows desktops and GUI applications | System FreeRDP client (`sdl-freerdp` / `xfreerdp`) launched from MoriXterm |
| SFTP | Secure file operations over SSH | Two-pane browser, multi-select, queued transfers and progress |
| FTP / FTPS | Legacy and managed file services | Passive mode, optional TLS, concurrent transfers and overwrite control |

## Feature guide

### A terminal that stays out of the way

- Local shell and SSH sessions live in tabs.
- ANSI palettes: MoriXterm, Dracula, Nord, Solarized Dark, Monokai and Light.
- Persistent font-size settings and Ctrl/Cmd + mouse-wheel zoom.
- Theme-aware, coloured `user@host:path` prompts for local and remote shells.
- Copy, paste, select-all and clear actions from the terminal context menu.
- Sidebar widths can be resized by dragging; session folders can be reorganized by drag and drop.

### SSH built for real work

- Modern defaults are used unless a profile explicitly asks for compatibility.
- Per-session Modern, Compatible and Legacy security profiles.
- Per-session private-key path and non-default port support.
- Dedicated `known_hosts` storage with first-use acceptance and changed-key warnings.
- Host-key replacement is an explicit action, never a silent downgrade.
- Remembered passwords use the operating-system credential vault. On Linux, install `libsecret`; on Windows, the Credential Manager backend is used.
- Linux uses a real PTY. Windows uses ConPTY for interactive SSH prompts and terminal resizing (Windows 10 1809 or newer). Windows releases bundle OpenSSH, so the installer and portable ZIP do not depend on a separate PATH installation. On Windows, type the SSH password at the terminal prompt; saved-password auto-fill is not yet available.

### RDP with FreeRDP

MoriXterm launches the system **FreeRDP** client (`sdl-freerdp3` / `xfreerdp3` / `xfreerdp`) in its own window:

- Width, height, fullscreen and 100–300% display zoom from **Settings → Remote Desktop**.
- NLA, bidirectional clipboard (text + files) and shared-folder drive redirection via FreeRDP.
- On Wayland, prefer `freerdp-sdl` (`sdl-freerdp3`) for reliable clipboard; otherwise install `freerdp3-x11` / `freerdp-x11`.

### File management and transfers

- Local and SSH file manager panels with context menus.
- Upload, download, new folder, rename, delete, copy, cut and paste.
- Permissions and owner/group editors for Unix targets.
- ZIP create and extract actions with progress feedback.
- SFTP/FTP two-pane workspace with local and remote multi-selection.
- Concurrent transfer queue, cancellation, overwrite policy and real curl progress.
- Context menus remain inside the viewport and scroll when there are more actions than available space.

### Profiles, organization and protection

- Unified create/edit form for SSH, RDP, SFTP and FTP profiles.
- SQLite profile database with session folders and recent-session metadata.
- Application password, startup lock, idle auto-lock and one-click lock from the sidebar.
- Locking hides the UI while active SSH, RDP and transfer processes continue running.
- Settings are grouped into compact Security, Terminal and Storage tabs.

## Installation

### Windows

Download either the installer or the portable archive from the [latest release](https://github.com/mortenaho/morixterm/releases/latest).

- **Installer:** run the `MoriXterm-<version>-Windows-x64-Setup.exe` asset.
- **Portable:** extract the `MoriXterm-<version>-Windows-x64-Portable.zip` asset and launch `morixtrem.exe`. The archive includes the Qt runtime and bundled OpenSSH client.
- **RDP on Windows:** install FreeRDP 3 with `wfreerdp.exe` in `PATH`, or place `wfreerdp.exe` beside `morixtrem.exe` (or in a `freerdp` subfolder). Current Windows packages do not bundle FreeRDP.

### Ubuntu / Debian

Download the `.deb` package and install it with:

```bash
sudo apt install ./morixterm_*_amd64.deb
```

### AppImage

```bash
chmod +x ./MoriXterm-v*-Linux-x86_64.AppImage
./MoriXterm-v*-Linux-x86_64.AppImage
```

For Linux SSH password injection and credential storage, install `sshpass` and `libsecret-tools`. For RDP, install `freerdp-sdl` (recommended on Wayland) or `freerdp3-x11`.

## Build from source

```bash
./scripts/install-ubuntu.sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
./build/bin/morixtrem
```

Useful verification commands:

```bash
python3 scripts/check-qml-duplicate-properties.py qml
python3 scripts/smoke-session-migration.py
```

### Technology

MoriXterm is built with C++20, Qt 6, QML, SQLite, OpenSSH, FreeRDP and curl. The UI is native Qt Quick; no Electron runtime or hosted service is required.

## Data and security

Profiles are stored in `morixtrem.db` under the platform application-data directory. Passwords are not stored in SQLite. Saved credentials go through the operating-system credential provider. SSH host keys are kept in MoriXterm's dedicated known-hosts file, and legacy algorithms are opt-in per session.

Read the full [SECURITY.md](SECURITY.md) before deploying MoriXterm in production.

## Releases

Run **Actions → Build and Release → Run workflow** on `main`. The workflow chooses the next numbered tag (`v3`, `v4`, `v5`, …), builds the Linux AppImage and DEB plus the Windows installer and portable ZIP from the same commit, and then creates the tag and GitHub Release. The package versions and the version shown in the app come from that tag. The legacy Flutter workflow only uploads CI artifacts and does not publish GitHub Releases.

The workflow needs `contents: write` permission to push the tag and publish the release. A failed build does not consume a version; if publishing fails after the tag is pushed, inspect that tag before starting another release.

## License and project information

- Application: MoriXterm
- Maintainer: mortenaho
- Repository: https://github.com/mortenaho/morixterm
- Release downloads: https://github.com/mortenaho/morixterm/releases
