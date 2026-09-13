# Vendored FreeRDP client

`xfreerdp` is shipped here so MoriXterm can open an RDP window without Remmina.

On Linux it still needs FreeRDP shared libraries (`libfreerdp3`, `libwinpr3`, …).
If the binary fails to start, install:

```bash
sudo apt install freerdp-x11
```
