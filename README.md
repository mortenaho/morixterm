# MoriXterm 3

> Version 3 fixes FreeRDP password delivery for GUI launches, redesigns the top command bar/session tabs, and adds Ctrl+mouse-wheel terminal zoom.

MoriXterm is a Qt 6 / QML remote workspace for local terminal, SSH, RDP and remote file management.

## Highlights

- Compact charcoal desktop theme with restrained green status accents
- Unified SSH/RDP create + edit form
- Secure saved credentials using the OS credential vault
- SSH security profiles: Modern, Compatible and explicit Legacy mode
- SSH tabs backed by a real PTY on Linux/Unix
- RDP through FreeRDP with clipboard, auto-reconnect and certificate controls
- Right-side file manager for the active local/SSH session
- Upload, download, rename, create folder, copy/cut/paste, chmod and chown
- Polished terminal and file-manager context menus
- Selectable terminal themes: MoriXterm, Dracula, Nord, Solarized Dark, Monokai and Light, with persistent font sizing
- Visual permissions editor and owner/group dialog
- Session folders with drag-and-drop organization
- SQLite profile database
- App password, startup lock and idle auto-lock without stopping active sessions
- GitHub Actions release workflow for AppImage, DEB and Windows EXE installer

## Build on Ubuntu

```bash
./scripts/install-ubuntu.sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
./build/bin/morixtrem
```

For remembered SSH passwords install `sshpass` and `libsecret-tools`. MoriXterm passes the SSH password to `sshpass -d` over an anonymous pipe; it does not place the password in process arguments or environment variables.

For RDP install FreeRDP (`xfreerdp3` / `xfreerdp` on Linux, or `wfreerdp` on Windows).

## Session database

Profiles are stored in `morixtrem.db` under the platform application-data directory. Passwords are not stored in the database. Folder membership, protocol options, SSH compatibility profile, RDP display settings and recent-use metadata are stored there.

## Session organization

Use **Folder** in the sidebar to create groups such as `Test`, `Production` or `Customers`. Drag a saved SSH/RDP session onto a folder to move it there. Deleting a folder keeps its sessions and moves them back to the ungrouped level.

## Release builds

Push a tag such as:

```bash
git tag v3
git push origin v3
```

`.github/workflows/release.yml` builds Linux AppImage + DEB and a Windows Inno Setup EXE, uploads the artifacts, and publishes a GitHub Release for the tag.

## Security

See [SECURITY.md](SECURITY.md). Legacy SSH algorithms are never enabled globally and must be selected per session.

## About

- App: MoriXterm
- Developer: mortenaho
- Stack: C++20, Qt 6, QML, SQLite, OpenSSH, FreeRDP
- Repository: https://github.com/mortenaho/morixterm

## 0.7 UI / branding notes

The UI uses consistent popup padding, a simplified Home page, a redesigned lock screen, Enter-to-submit on primary forms, and the MoriXterm brand assets for the About dialog and application/taskbar icon.


## File archives

The File Manager can create ZIP archives from files or folders and extract ZIP files into a new folder. For SSH sessions the operation runs on the remote host, which must have `zip` and `unzip` installed.


## FTP / SFTP workspace

FTP and SFTP profiles open a two-pane file client instead of a terminal. The left pane browses local files and folders and the right pane follows the active remote directory. Multi-selection supports Ctrl/Shift, multiple files and folders can be queued for concurrent upload, duplicate targets are overwritten when the Overwrite option is enabled, and the transfer drawer exposes per-job and overall progress with cancellation. FTP supports passive mode and optional TLS; SFTP supports password or private-key authentication.

## Transfer and archive progress

FTP/SFTP transfers report real curl progress. ZIP/Unzip operations report file-entry progress. Operations whose backend does not expose byte-level progress use an indeterminate progress state rather than presenting a fake percentage.
