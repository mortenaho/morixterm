# MoriXterm 0.9.5 — database migration, auto refresh, actionable toasts

- Repairs legacy SQLite `sessions.kind` CHECK constraints regardless of whitespace/parenthesis formatting, allowing FTP/SFTP profiles on databases created by older releases.
- Re-runs the persisted-session model after the QML scene is ready so saved sessions/folders are visible immediately at startup.
- SSH file manager quietly retries while the interactive terminal is authenticating and refreshes automatically once the shared ControlMaster is ready.
- FTP/SFTP initial directory listing is deferred to the next event-loop turn so the workspace has completed binding its connection properties.
- Toasts are higher contrast, stay longer for errors, and now provide Copy and Close actions.
- SSH/local file-manager context menu now includes permanent file/folder deletion with an explicit confirmation dialog.
