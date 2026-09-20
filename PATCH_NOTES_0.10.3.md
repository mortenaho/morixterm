# MoriXterm 0.10.3

## Session folder drag-and-drop fix

- Replaced Qt Quick `Drag`/`DropArea` session movement with manual pointer hit-testing inside the Sessions `ListView`.
- Works without relying on `DropEvent.source`, which can be unreliable with ListView delegates on Wayland.
- Destination folders highlight while the pointer is over them.
- Drop hint shows the actual target folder name.
- Session database movement is deferred until the pointer release handler completes, avoiding delegate destruction during the input event.
- Existing `SessionStore::moveSessionToFolder()` remains the single database update path and expands the destination folder after a successful move.
