# MoriXterm 0.7.0 — UI polish & branding

- Reworked dialog padding and spacing. Previous `anchors.margins` values on unanchored layouts were ineffective.
- Redesigned Home into a calmer two-section layout: one hero/quick-actions area and recent connections.
- Redesigned the lock screen with a layered dark gradient, subtle blue/green accents and a protected-session card.
- Added Enter/Return handling for the primary action in connection, file operation, session-folder, lock and password forms.
- Integrated the user-provided MoriXterm brand mark.
  - `morixtrem-brand.png`: full mark used in About.
  - `morixtrem-app.png`: square app/taskbar icon derived from the emblem.
  - `morixtrem.ico`: multi-resolution Windows icon.
- Linux: application icon is installed to the hicolor theme, desktop file gets StartupWMClass, and Qt desktopFileName/windowIcon are set at runtime.
- AppImage release workflow now packages the new MoriXterm icon.
- Version bumped to 0.7.0.
