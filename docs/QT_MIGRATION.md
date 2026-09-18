# Qt/QML migration

This document tracks the staged replacement of the Flutter desktop client with
Qt 6 and QML. The legacy implementation remains available as a behavior and
security reference until parity is verified.

## Architecture

The Qt application separates UI state from operating-system integrations:

```text
QML views
   │
   ├── SessionModel ── sessions.json
   │
   └── ConnectionManager
          ├── OpenSSH
          └── FreeRDP
```

`SessionModel` is a `QAbstractListModel`, so QML never reads or writes the JSON
store directly. `QSaveFile` provides atomic bookmark updates. Password fields
are not part of the model and cannot be serialized accidentally.

`ConnectionManager` owns the active SSH process and launches RDP without
putting a password on the command line. Host-key and certificate verification
remain enabled.

## Parity status

| Capability | Qt status | Notes |
|---|---|---|
| Application shell | Done | Responsive sidebar and workspace |
| Bookmark create/edit/delete | Done | JSON persistence, validation, search |
| SSH launch and command input | Initial | Uses system OpenSSH; native PTY terminal is next |
| RDP launch | Initial | FreeRDP opens as an external native window |
| Password vault | Pending | No password persistence in the interim |
| Known-host management UI | Pending | OpenSSH verification remains enabled |
| SFTP file browser/transfers | Pending | Planned after native SSH transport |
| Multi-session tabs | Pending | Model designed to support the next milestone |
| Terminal themes/search/zoom | Pending | Requires the native terminal component |
| System monitor | Pending | Depends on the SSH transport layer |
| App lock and auto-lock | Pending | Will wrap the Qt credential vault |
| Packaging and CI | Pending | Linux and Windows targets |

## Next milestones

1. Add a cross-platform PTY-backed terminal and one connection object per tab.
2. Introduce an SSH transport abstraction with host-key callbacks and SFTP.
3. Implement an encrypted credential vault and application lock.
4. Port the file manager, transfers, permissions, and remote monitoring.
5. Replace Flutter packaging and CI only after parity tests pass.

## Migration rules

- Do not remove a legacy capability before an equivalent Qt path is tested.
- Never store passwords in `sessions.json`, logs, process arguments, or QML.
- Preserve strict host identity verification for SSH and TOFU for RDP.
- Keep backend APIs independent from QML so Linux and Windows transports can
  evolve without rewriting the interface.
