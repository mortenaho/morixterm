# MoriXterm 0.10.4

## Terminal scrollback

- Adds a real scrollback buffer (up to 10,000 lines) for normal terminal screens.
- Mouse wheel and touchpad scrolling browse terminal history.
- `Shift+PageUp` / `Shift+PageDown` scroll by a page.
- `Shift+Home` jumps to the oldest retained history and `Shift+End` returns to live output.
- A compact draggable scrollbar is painted on the right side of the terminal.
- Typing while browsing history returns to the live terminal before sending input.
- Incoming output preserves the viewed history position while the user is scrolled up.
- Alternate-screen applications keep their own screen and do not pollute shell scrollback.
- `CSI 3 J` clears both the visible screen and retained scrollback.
