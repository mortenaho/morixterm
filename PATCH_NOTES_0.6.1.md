# MoriXterm 0.6.1 hotfix

This release fixes the QML parser failures reported during CMake configuration/build.

## Fixed
- Removed invalid semicolons between inline child QML object declarations in `qml/Main.qml`.
- Bumped the application/package version to `0.6.1`.
- Added `qt6-declarative-dev-tools` to Ubuntu CI/dev dependencies.
- Added the generated `morixtrem_qmllint` target to GitHub Actions so QML syntax failures are caught before packaging.

## About the Qt plugin warnings
Warnings such as `Qt6::qtquick2plugin does not exist in the current scope` are emitted by Qt's QML import scanning on some distro Qt packages. They are warnings, not the parser errors fixed above. The build should be judged by the subsequent build/lint step rather than the configure warnings alone.
