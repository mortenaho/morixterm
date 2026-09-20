# MoriXterm 0.10.2

## Build fix

- Fixed Qt 6 compilation in `TerminalItem::flushRepaint()`.
- `QQuickPaintedItem::update()` accepts `QRect`, while the optimized repaint code passed `QRectF`.
- The dirty terminal region is now converted with `QRectF::toAlignedRect()` before calling `update()`.
- Keeps the partial repaint optimization introduced in 0.10.1 without falling back to full-screen repainting.
