# MoriXterm

[![Build desktop packages](https://github.com/mortenaho/morixterm/actions/workflows/desktop-build.yml/badge.svg)](https://github.com/mortenaho/morixterm/actions/workflows/desktop-build.yml)

MoriXterm is a cross-platform remote terminal and connection manager built with Electron, React, TypeScript, xterm.js, and SQLite. It brings SSH shells, RDP launchers, local terminals, and remote file management into one desktop workspace.

## Highlights

- Interactive SSH terminals with resize, keepalive, reconnect, search, Unicode, links, WebGL fallback, and persistent tabs.
- Compatibility negotiation for modern and legacy SSH servers, including older cipher, key-exchange, host-key, and MAC algorithms when required.
- SSH host-key TOFU verification with persisted fingerprints and a changed-key man-in-the-middle warning.
- Remote file manager over the authenticated SSH connection with SFTP browsing, upload, download, copy, move, rename, delete, directory creation, `chmod`, and `chown`.
- Native RDP launcher using FreeRDP or the Windows Remote Desktop client when available.
- Multiple local terminals powered by `node-pty`; usable WSL distributions are detected automatically on Windows and preferred over PowerShell/CMD.
- Searchable session library with favorites, folders, pagination, reconnect state, and SQLite persistence.
- Application password, manual lock, and configurable inactivity auto-lock while active terminal sessions continue running in the background.
- Portable database backup and restore from Settings.
- Windows NSIS installer plus Linux AppImage and Debian packages built by GitHub Actions.

## Security and data persistence

MoriXterm uses Electron context isolation, a sandboxed renderer, a narrow typed preload API, single-instance locking, and hardened Electron fuses.

Session metadata is stored in `morixterm.sqlite` under Electron's stable `userData` directory. Application updates reuse this database and run versioned migrations; they do not recreate or delete existing data. A timestamped backup is created before an upgrade migration.

Passwords and application-lock secrets are stored in the operating system credential store through Keytar. They are never written to SQLite.

Typical data locations:

| Platform | Application data |
| --- | --- |
| Linux | `~/.config/morixterm/` |
| Windows | `%APPDATA%\morixterm\` |
| macOS | `~/Library/Application Support/morixterm/` |

Use **Settings → Data → Backup database** before moving the application to another machine. Restoring a backup safely replaces the database and restarts the app.

## Requirements

- Node.js 22 or newer for development and packaging.
- npm with the lockfile included in this repository.
- A supported desktop environment for Electron.

### Linux RDP

RDP opens an installed native client. On Debian/Ubuntu, install FreeRDP:

```bash
sudo apt install freerdp-x11
```

MoriXterm detects `xfreerdp3`, `xfreerdp`, `wlfreerdp`, and `sdl-freerdp`. If none is available, the application displays an installation hint instead of reporting a false connection.

### Linux native dependencies

Keytar requires the Secret Service development package when dependencies or release packages are built:

```bash
sudo apt install libsecret-1-dev
```

## Development

Install dependencies and start the development application:

```bash
npm ci
npm run dev
```

Available verification commands:

```bash
npm run typecheck
npm run build
npm test
```

`npm test` performs a production build and runs the Node test suites for session persistence, security controls, and application locking.

## Packaging

Build a package for the current operating system:

```bash
npm run package
```

Examples for explicit targets:

```bash
npm run package -- --linux AppImage deb --publish never
npm run package -- --win nsis --publish never
```

Generated packages are written to `release/`.

Every push to `main`, `feature/**`, or `fix/**` runs the desktop packaging workflow. Successful runs publish two downloadable artifacts for 30 days:

- `MoriXterm-windows`: Windows NSIS installer (`.exe`)
- `MoriXterm-linux`: Linux AppImage and Debian package (`.deb`)

See [GitHub Actions](https://github.com/mortenaho/morixterm/actions/workflows/desktop-build.yml) for current builds and artifacts.

## Project structure

```text
electron/             Electron main process, IPC, repositories, and services
src/renderer/         React desktop interface and terminal workspace
public/branding/      Renderer branding assets
assets/branding/      Installer and package branding assets
tests/                Security, persistence, and application-lock tests
.github/workflows/    Windows and Linux packaging automation
```

## Package identity

| Field | Value |
| --- | --- |
| Package | `morixterm` |
| Product | `MoriXterm` |
| Application ID | `com.morixterm.desktop` |
| Current version | `0.1.0` |
| License | MIT |
| Repository | [github.com/mortenaho/morixterm](https://github.com/mortenaho/morixterm) |

## Current limitations

- RDP is launched in a native external client and is not embedded in the Electron workspace.
- Transfer queue progress, cancellation, retry, and bounded concurrency remain planned.
- Release binaries are currently provided as GitHub Actions artifacts rather than signed GitHub Releases.
