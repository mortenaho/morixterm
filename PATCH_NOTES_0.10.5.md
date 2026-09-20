# MoriXterm 0.10.5

- Prefer FreeRDP `/from-stdin:force` for secure password transport; keep `/args-from:stdin` as fallback.
- Map FreeRDP exit codes to readable connection/authentication/TLS errors.
- Filter harmless XKB `no RDP scancode found` warnings from the primary RDP error message.
- Include the actual target host:port in RDP failure messages.
