# MoriXterm 0.8.1 — toolbar, archive tools, button-system fix

- Rebuilt `MButton`, `MIconButton`, `MContextItem`, and the new `MTopToolButton` around fixed hit areas and deterministic content centering.
- Added a top workspace toolbar inspired by classic remote-terminal clients: Session, Files, Fullscreen, Disconnect, and About.
- Removed duplicate New connection/File Manager icons from the tab strip.
- Added ZIP creation for files and folders in the File Manager.
- Added safe-path preflight before ZIP extraction and extraction into a new destination folder.
- ZIP/Unzip works locally and over the active SSH connection; remote hosts must provide `zip`/`unzip`.
- Added archive actions to the File Manager context menu instead of adding more permanent buttons.
- Added Enter handling to archive dialogs and retained Enter-as-primary-action behavior across existing forms.
- Added `zip` and `unzip` to Ubuntu bootstrap dependencies and DEB runtime dependencies.
- Version bumped to 0.8.1.
