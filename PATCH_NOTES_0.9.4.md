# MoriXterm 0.9.4 — Session drag/drop + toast notifications

- Added robust drag-and-drop of saved SSH/RDP/FTP/SFTP sessions into sidebar session folders.
- Folder drop targets are highlighted and successful moves are persisted in SQLite.
- Session moves validate both source session and destination folder and report failures.
- Added a professional toast notification layer for runtime errors.
- Session-store, file-manager, terminal, RDP and FTP/SFTP runtime errors are surfaced as toasts.
- App-lock validation feedback can also be shown as a toast without interrupting active sessions.
- Added a drag hint banner while moving a session.
