# MoriXterm 0.10.6

## RDP
- Passwords are now supplied through FreeRDP `/args-from:stdin`.
- `/from-stdin` is no longer used from the GUI because it requires a controlling TTY and fails with `tcgetattr/tcsetattr: Inappropriate ioctl for device` when launched through `QProcess`.
- Secrets remain out of argv and the environment.

## UI
- Reworked the top command toolbar with vector Canvas icons, clearer grouping, spacing and active state.
- Reworked session tabs with protocol icons, active accent, better padding, close affordance and a new-session button.

## Terminal
- Hold Ctrl and use the mouse wheel/touchpad to zoom the terminal font.
- Font size remains clamped to the existing safe range.
