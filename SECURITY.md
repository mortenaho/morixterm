# Security

MoriXterm is a privileged desktop client: it can open local shells, authenticate to remote systems, transfer files, and launch RDP clients. Treat every release and dependency update as security-sensitive.

## Implemented controls

- Electron renderer sandboxing, context isolation, no Node integration, blocked webviews, navigation and popup denial, restrictive permissions, and a Content Security Policy.
- IPC calls are accepted only from the trusted top-level renderer origin and all payloads are schema-validated.
- SSH server keys use SHA-256 fingerprints with trust-on-first-use confirmation. A changed key is blocked until the user explicitly confirms replacement.
- Legacy SSH ciphers, SHA-1 host keys, and weak key-exchange algorithms are rejected. Remote OSC 52 clipboard access is disabled; clipboard actions require local user interaction.
- Saved passwords are stored in the operating-system credential vault through `keytar`; SQLite stores only a boolean indicating whether a secret exists.
- RDP passwords are sent through the client standard input instead of process arguments where FreeRDP is used.
- Session metadata, host fingerprints, settings, and logs are created with owner-only permissions on POSIX systems.
- Release packages enable Electron fuses that disable `ELECTRON_RUN_AS_NODE`, Node options, inspector arguments, and non-ASAR application loading.

## Operational requirements

- Verify every new or changed SSH fingerprint through an independent channel.
- Code-sign Windows installers before public distribution. The build workflow reads `WINDOWS_CSC_LINK` and `WINDOWS_CSC_KEY_PASSWORD` from GitHub Actions secrets; signing material must never be committed to this repository.
- Keep Electron and all runtime dependencies current and review `npm audit --omit=dev` results before each release.
- Protect GitHub release branches and require passing build/test checks and review before merging.
- Never attach application logs, session databases, or credential-store exports to public bug reports.

## Reporting vulnerabilities

Do not open a public issue containing exploit details, credentials, hostnames, or logs. Contact the repository owner privately with reproduction steps and the affected version.
