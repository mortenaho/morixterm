# MoriXterm 0.10.0

## Terminal responsiveness

- Batches printable PTY bytes before UTF-8 decoding instead of invoking the decoder byte-by-byte.
- Coalesces terminal repaints on a short 8 ms timer to avoid repaint storms while preserving interactive feel.
- Draws terminal text as style runs rather than one `drawText()` call per cell.
- Stops SSH host-key diagnostic scanning after startup instead of rescanning terminal history on every echoed keystroke.

## Sessions sidebar

- Reworked into a compact remote-client tree inspired by the supplied reference.
- Compact Sessions toolbar with New connection, New folder and Local terminal actions.
- Denser folder/session rows, protocol badges, active-session indicator and host/user subtitle.
- Preserves right-click menus and folder expand/collapse behavior.
- Uses a dedicated invisible drag source so dragging a session does not move/rebind the ListView delegate itself.
- Folder drop targets highlight while a session is dragged over them.

## Version

- Application/package version: 0.10.0
