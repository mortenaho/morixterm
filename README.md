# MoriXterm

Modern Remote Terminal & Connection Manager — a cross-platform Electron workstation for SSH, SCP/SFTP, RDP, local terminals and remote files.

## Phase 1–2 status

Working now:

- Secure Electron shell (`contextIsolation`, no Node in renderer, sandboxed preload API)
- Desktop workstation UI: title bar, collapsible sidebar, tabs, status bar, command palette
- Local terminal via `node-pty` + `xterm.js` (fit/resize, multi-tab)
- Real SSH interactive shell via `ssh2` + xterm, passwords in OS credential store (keytar)
- SQLite session persistence, favorites, search, create/edit/delete
- Settings (terminal font/size/scrollback) and About screen
- Single-instance lock and application menu

Deferred (stubs in UI): SFTP/SCP, transfer manager, embedded RDP canvas, snippets, command history, workspaces, tray.

## RDP requirement

RDP opens the native FreeRDP / system client (not embedded in the Electron window yet).

Linux:
```bash
sudo apt install freerdp-x11
```

That package provides `xfreerdp`. MoriXterm also looks for `xfreerdp3`, `wlfreerdp`, and `sdl-freerdp`. If no client is installed, Connect shows an install hint instead of a fake success toast.

## Branding

Place the official MoriXterm logo (do not redesign) under `assets/branding/`:

- `morixterm-logo.png`
- `morixterm-icon.png`

Temporary SVG/PNG marks ship until those files are replaced. Also mirrored for the renderer at `public/branding/`.

## Development

```bash
npm install
npm run build
npm test
npm run dev
```

Sessions live in `morixterm.sqlite` under Electron `userData` (Linux: `~/.config/morixterm/`). Passwords stay in the OS credential store, keyed by session UUID.

## Package identity

- name: `morixterm`
- productName: `MoriXterm`
- appId: `com.morixterm.desktop`
