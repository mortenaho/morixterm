# MoriXterm 0.9.3 — FtpWorkspace runtime QML fix

- Removed the duplicated `cursorShape` assignment in `qml/components/FtpWorkspace.qml` that caused `Property value set multiple times` at runtime.
- Added a lightweight QML duplicate-property guard for CI/preflight checks.
- Version bumped to 0.9.3.
