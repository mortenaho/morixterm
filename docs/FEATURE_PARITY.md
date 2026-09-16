# Feature-Parity Checklist
| Area | Current baseline | Target |
|---|---|---|
| Session CRUD | SSH/RDP/local, favorite, search, pagination | Nested folders, recent, duplicate, move, timestamps, secure references |
| Workspace | Home/settings/about and basic tabs | Reorderable persistent live tabs with connection states |
| Local terminal | node-pty with xterm and fit/resize | Real multi-terminal shell detection and full addon lifecycle |
| SSH terminal | ssh2 interactive PTY and resize | Auth variants, keepalive, reconnect and host-key TOFU |
| Remote files | Deferred | SFTP explorer, transfers and terminal-directory following |
| RDP | Opens native FreeRDP client | Managed lifecycle, status and safe errors |
| Secrets | OS credential store for passwords | All sensitive material in OS vault; no plaintext persistence |
| Security | Context isolation, sandbox, IPC validation | Typed narrow contracts and complete host-key/app-lock flows |
| UI | Dark desktop shell with modals/toasts | Consistent modal/AJAX-style async operations, filters, pagination and accessible actions |
