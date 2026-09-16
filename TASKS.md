# MoriXterm Implementation Plan

The work is intentionally split into independently verifiable slices. `[x]` means implemented on the current feature branch; `[ ]` remains planned.

## Phase 0 — Baseline and guardrails

- [x] Capture existing Electron/React behavior and current feature gaps.
- [x] Establish project engineering rules and a feature-parity checklist.
- [x] Keep a dedicated feature branch and verify each slice with build/tests.

## Phase 1 — Domain and persistence foundation

- [ ] Session schema: protocol, timestamps, folder IDs and stable tab color.
- [ ] Nested folder repository and session move/duplicate operations.
- [x] Persist nested folder paths with create/rename/delete repository and IPC operations.
- [ ] Secure credential references for passwords, key passphrases and RDP secrets.
- [ ] Typed IPC API with versioned contracts and structured safe errors.
- [ ] Migration tests and repository error-path tests.

## Phase 2 — Workspace and session UX

- [x] Freeze current MoriXterm visual tokens and interaction parity contract.
- [x] Add the visual Connections/Favorites/Recent/Folders navigator using the existing shell.
- [x] Drag sessions onto visible nested folders to move them without losing credentials.
- [ ] Connection sidebar: Connections, Favorites, Recent and nested folders.
- [ ] Search/filter and server-side pagination without stale responses.
- [x] Search/filter with server-side pagination, reset-on-filter and stale-response protection.
- [ ] Session context menu, drag/drop organization and duplicate flow.
- [ ] Persistent multi-session tabs with full reconnect state indicators.
- [x] Preserve SSH tabs across failed/disconnected states and surface live state events.
- [x] Reorderable tabs, middle-click close and per-session tab color accent.
- [ ] Preserve live terminal transports while changing tabs.

## Phase 3 — Terminal engine

- [ ] Terminal theme controls and complete keyboard shortcut actions.
- [x] xterm Fit/Search/WebLinks/WebGL/Clipboard/Unicode11 addon lifecycle with WebGL fallback.
- [ ] 256-color/true-color, mouse, selection, scrollback and keyboard shortcuts.
- [ ] Configurable font, size, line height, cursor, shell, theme and scrollback.
- [ ] Multiple real local terminals with platform shell detection and cleanup.

## Phase 4 — SSH and host security

- [ ] SSH PTY (`xterm-256color`), resize, keepalive and reconnect state machine.
- [ ] Password, private key, encrypted key, agent and keyboard-interactive auth.
- [ ] Host-key TOFU prompt and changed-key MITM warning.
- [ ] Disconnect/reconnect without destroying the tab or terminal buffer.

## Phase 5 — Remote files and transfers

- [x] Typed SFTP directory listing through the existing SSH transport and narrow IPC.
- [x] Add the MoriXterm Files pane with breadcrumbs, parent navigation, refresh and remote metadata.
- [x] Add upload/download, recursive copy/cut/paste, rename/delete, mkdir, chmod and chown controls.
- [x] Use SCP over the authenticated SSH channel for upload/download without exposing secrets in command arguments.
- [ ] SFTP directory listing, breadcrumbs, permissions, dates and multi-select.
- [ ] Upload/download, rename/delete/mkdir and clipboard copy/cut/paste.
- [ ] Transfer queue with progress, cancellation, retry and bounded concurrency.
- [ ] Resizable Files pane and follow-terminal-current-directory integration.

## Phase 6 — RDP, security and release

- [ ] FreeRDP process lifecycle, platform detection and safe failure states.
- [ ] Application lock, settings persistence and secret redaction audit.
- [ ] Accessibility, keyboard navigation, responsive desktop layouts and RTL readiness.
- [ ] Linux AppImage/deb, Windows NSIS and macOS-compatible boundaries.
- [ ] End-to-end smoke tests and release documentation.
