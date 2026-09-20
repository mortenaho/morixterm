# MoriXterm 0.9.2 — QML registration build fix

- Fixed `FtpClientController` being declared `final` while also being registered with `qmlRegisterType`.
- Qt's `qmlRegisterType<T>()` creates an internal `QQmlElement<T>` subclass, so registered QML types must be inheritable.
- Audited all classes registered via `qmlRegisterType`; `TerminalItem`, `FileManagerController`, `FtpClientController`, and `RdpSessionController` are all non-final now.
- Version bumped to 0.9.2.
