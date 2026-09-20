# MoriXterm 0.9.6

- Toast host is now parented to `Overlay.overlay` with a top-most z-order, so notifications stay above dialogs, popups, and the lock screen.
- Reworked the legacy SQLite session migration. The `kind` database CHECK is removed after a one-time table rebuild; protocol validation remains in C++ so FTP/SFTP and future protocols do not require another CHECK migration.
- Schema migration is retried/verified during reload and before save, preventing a failed startup migration from silently leaving the old `ssh/rdp` constraint active.
- Added a SQLite migration smoke test and release-CI step.
- Fixed session drag-and-drop: the dragged delegate now physically follows the pointer so folder `DropArea`s receive the internal Qt drag event; its ListView indentation/position is restored after the drop.
