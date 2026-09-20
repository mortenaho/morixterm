# MoriXterm 0.9.1 — FTP/SFTP client and transfer UX

- Fixed the connection dialog footer so action buttons have deterministic 38px height, consistent widths, and a bounded 70px footer instead of stretching with the dialog.
- Removed the duplicated MoriXterm wordmark beneath the brand image in About.
- Repository text in About is now an actual clickable link with pointer cursor.
- Added pointer cursors to workspace tabs and FTP/SFTP file rows.
- Added FTP and SFTP session types to the unified connection editor and SQLite schema.
- FTP/SFTP sessions open a two-pane file workspace (local source + remote destination) instead of a terminal.
- Added multi-selection, concurrent multi-file/folder upload, overwrite mode, transfer queue, cancellation, per-transfer progress and overall progress.
- Added remote create folder, rename, delete and SFTP chmod actions.
- FTP supports passive/active mode and optional TLS; SFTP supports password/private key and known-hosts integration through curl.
- Added a professional progress card to the SSH/local File Manager for upload/download/archive operations.
- Hardened ZIP/Unzip command execution with a stable C locale and stricter archive/destination-name validation.
- Version bumped to 0.9.1.
