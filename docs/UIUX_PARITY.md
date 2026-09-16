# MoriXterm UI/UX Parity Contract
The current MoriXterm shell is the visual source of truth. New features must fit this system; they must not introduce a second design language or replace the existing shell with a generic dashboard.

## Invariants

- Keep the dark navy palette: `#080e18` application background, `#0d1622` panels, `#101b29` raised surfaces, `#1d293a` borders and `#3ddac5` accent.
- Keep the 48px title bar, 220px expanded sidebar, 58px collapsed sidebar, 36px tab bar and 28px status bar.
- Keep Manrope for UI text and DM Mono/JetBrains Mono for technical metadata and terminal-adjacent text.
- Keep 6–12px corner radii, thin blue-gray borders, restrained shadows and compact desktop density.
- Reuse the existing `panel`, `page`, `nav-item`, `tab`, `icon-button`, `new-button`, `toast` and modal classes before adding a new primitive.
- Reuse the existing logo assets. Do not redraw or replace MoriXterm branding.
- Keep Lucide icons, icon sizing and the existing cyan/amber/blue/purple semantic accents.

## Interaction parity

- New connection forms remain in the existing native modal treatment and preserve entered values on validation errors.
- Async operations retain the current tab/sidebar and report outcomes through the existing toast stack.
- Destructive actions use SweetAlert2 with the existing dark visual language and explicit cancel action.
- New lists extend the current compact row treatment and add filtering/pagination without changing page rhythm.
- Terminal and file panes must occupy the existing workspace content area and preserve the current tab/status behavior.

## Review rule

Every UI change must answer: does this look like it shipped with the current MoriXterm shell? If not, extract the needed shared token/component rather than styling a one-off screen.
