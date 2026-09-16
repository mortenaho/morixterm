# MoriXterm Engineering Rules
## Scope

MoriXterm is a cross-platform Electron workstation for SSH, SFTP/SCP, RDP and local terminals. Existing Flutter behavior is the functional reference; the Electron implementation must preserve working behavior while using Electron-native boundaries.

## Architecture

- Keep privileged work in `electron/main`, services and IPC handlers.
- Keep React renderer code free of Node.js, filesystem, networking, SQLite, `ssh2`, `node-pty` and FreeRDP access.
- Expose only narrow, typed APIs through a context-isolated preload. Never expose `ipcRenderer`.
- Validate every IPC payload with Zod and bind connection operations to opaque session IDs.
- Keep domain services small; do not create giant React components or service files.
- Store canonical dates and data in persistence; convert only at UI boundaries.

## Security

- `contextIsolation: true`, `nodeIntegration: false`, `sandbox: true` are mandatory.
- Passwords, private-key passphrases and other secrets must use the OS credential store. They must not enter SQLite, localStorage or persisted renderer state.
- SSH host keys use TOFU: first-use requires explicit trust; changed keys require an explicit reject/replace decision and a MITM warning.
- Redact credentials and private key material from logs and error messages.
- Preserve authorization checks, sender validation and safe IPC error handling.

## UX

- Connection actions must be asynchronous and keep tabs alive while switching.
- All state changes provide loading, success and failure feedback through the shared toast flow.
- Destructive actions require SweetAlert2 confirmation.
- Forms use shared modal behavior; lists use filtering, pagination, loading and empty states.
- Actions have consistent icons and accessible labels. Preserve RTL/Persian localization requirements when adding localized screens.

## Verification

- Run `npm run typecheck` for TypeScript changes and `npm test` for persistence/service changes.
- Add focused tests for security boundaries, migrations, validation and reconnect behavior.
- Review the complete diff against `main` before handoff. Do not merge the feature branch without explicit user approval.
