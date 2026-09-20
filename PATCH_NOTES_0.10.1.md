# MoriXterm 0.10.1

## Fixes

- Reworked FreeRDP startup for better compatibility across FreeRDP 2/3:
  - prefers `/args-from:stdin` when available;
  - falls back to `/from-stdin` for secure password delivery;
  - removes the forced `/gfx` option;
  - uses the correct `/f` fullscreen switch;
  - captures FreeRDP output and surfaces fast startup failures as application errors;
  - detects `xfreerdp3`, `xfreerdp`, `sdl-freerdp3`, and `sdl-freerdp`.
- Rebuilt session drag/drop for Qt/Wayland using an explicit drag proxy and a root-level session identity, then persists `folder_id` through `SessionStore`.
- Hardened `moveSessionToFolder` so it validates the database/session/folder and treats dropping into the existing folder as success.
- Reduced terminal input latency by removing the artificial 8ms repaint delay and repainting only dirty rows for normal interactive output.

## UI

- Reworked the main palette into a neutral charcoal desktop theme based on the supplied reference image.
- Reduced top toolbar, tabs, sidebar and status-bar density.
- Added dedicated SVG icons for folders, normal files, and archive files in both the SSH/local File Manager and FTP/SFTP workspace.
- Kept green as a restrained connection/selection/status accent rather than tinting every surface.

## Packaging

- Version: 0.10.1
- DEB runtime dependencies now include FreeRDP and Qt SVG support.
