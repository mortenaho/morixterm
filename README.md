# MoriXterm

MoriXterm is a desktop workspace for saved SSH and RDP sessions. The active
implementation is being rewritten with **Qt 6, C++20, and QML** on the `qt`
branch.

The first Qt milestone includes:

- a native Qt Quick application shell;
- searchable, persistent SSH/RDP bookmarks;
- modal create/edit forms and confirmed deletion;
- in-app toast notifications;
- an SSH process console with interactive standard input;
- secure RDP launching through `wlfreerdp` or `xfreerdp`;
- no plaintext password persistence or password command-line arguments.

The Flutter implementation remains in `lib/` while features are migrated and
verified. See [docs/QT_MIGRATION.md](docs/QT_MIGRATION.md) for the parity plan.

## Requirements

- CMake 3.21 or newer
- Qt 6.5 or newer with Quick and Quick Controls 2
- a C++20 compiler
- OpenSSH client for SSH connections
- `wlfreerdp` or `xfreerdp` for RDP connections

## Build and run

```bash
cmake -S . -B build -G Ninja
cmake --build build
./build/morixterm
```

Session metadata is stored in Qt's platform-specific application data
directory as `sessions.json`. Passwords are deliberately excluded from that
file. Authentication is delegated to the system connection client until the
encrypted Qt credential vault milestone is complete.

## Source layout

```text
src/                    C++ application and service layer
qml/                    Qt Quick user interface
docs/QT_MIGRATION.md    migration scope and parity status
lib/                    legacy Flutter implementation (migration reference)
```

## Security baseline

SSH keeps OpenSSH host-key verification enabled with
`StrictHostKeyChecking=ask`. RDP uses FreeRDP's `/cert:tofu` policy. MoriXterm
does not silently accept changed host keys or certificates.
