# MoriXterm 0.6.2

## Runtime/QML loader hotfix

- Replaced the executable QML module bootstrap with an embedded Qt resource bundle.
- `Main.qml` is now loaded explicitly from `qrc:/qml/Main.qml`, avoiding the runtime error `Module "MoriXterm" contains no type named "Main"`.
- Removed the QML-module plugin auto-link path that produced distro-specific `Qt6::*plugin target does not exist` warnings.
- GitHub Actions now performs a parser-level QML syntax check with `qmlformat` before compiling.
- Running the desktop application as root is rejected by `scripts/run.sh`; root breaks user DBus/desktop services and is not required.
- Linux `PR_SET_DUMPABLE=0` is now opt-in via `MORIXTERM_STRICT_NO_DUMP=1` because GNOME portals may otherwise fail to inspect `/proc/<pid>`. Core dumps remain disabled by default.
