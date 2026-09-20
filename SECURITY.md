# MoriXterm security model

MoriXterm is a remote administration client, so credentials, host identity and command execution are treated as security boundaries.

## Credentials

- Session passwords are **never stored in SQLite**.
- On Linux, remembered passwords are stored through Secret Service using `secret-tool` (libsecret).
- On Windows, remembered passwords use Windows Credential Manager.
- SSH password automation on Unix uses `sshpass -d` with an anonymous pipe. The password is not placed in the process command line or environment.
- RDP passwords are sent to FreeRDP through `/args-from:stdin`; the password is not placed on its command line. If an older FreeRDP build lacks this secure input mode, MoriXterm refuses saved-password injection rather than exposing the secret in process arguments.
- Password fields are cleared from the QML session model after a connection starts.

## SSH host verification and algorithms

The default **Modern** profile does not override OpenSSH's enabled algorithms. MoriXterm keeps SSH host identities in its own `~/.config/morixtrem/known_hosts` file and uses `StrictHostKeyChecking=accept-new`: a first-seen key is saved automatically, while a changed key is rejected until the user explicitly approves replacement in the in-app security dialog. MoriXterm hashes known-host entries, displays OpenSSH's visual fingerprint, and allows OpenSSH host-key updates. Agent/X11 forwarding and local-command execution are disabled by default, and a configured identity file is used with `IdentitiesOnly=yes`.

Compatibility is per session and explicit:

- **Modern**: installed OpenSSH defaults. Recommended.
- **Compatible**: appends RSA/SHA-1 host/user signatures and group14/SHA-1 KEX for older servers while retaining modern defaults.
- **Legacy**: additionally requests DSA, group1/SHA-1, CBC ciphers and HMAC-SHA1. This is intentionally opt-in and may be rejected by recent OpenSSH builds if an algorithm is no longer compiled in.

Do not use Compatible or Legacy mode as a global default. Upgrade remote hosts whenever possible.

## Local application hardening

- The application data directory and SQLite database are owner-only where the OS supports POSIX permissions.
- SQLite uses foreign keys, WAL, secure deletion and a busy timeout.
- Core dumps are disabled on Unix; on Linux the process is marked non-dumpable to reduce exposure of in-memory credentials.
- The SSH ControlMaster socket is reused only while its owning terminal session is alive; closing the tab does not intentionally leave a persistent master connection behind.
- The application lock uses a salted PBKDF2-HMAC-SHA256 verifier and constant-time hash comparison. Repeated failed unlock attempts are progressively rate-limited. Locking hides the UI without terminating active sessions.
- RDP certificate verification defaults to TOFU. Certificate-ignore is a visible per-session opt-in.
- File operation inputs are validated; `chmod` and `chown` do not accept arbitrary option strings.
- MoriXterm never runs `sudo` automatically for file ownership or permission changes.
- Terminal OSC payloads are size-limited and OSC 52 clipboard writes are not implemented.

## Remaining trust boundaries

- A compromised remote host can still display malicious terminal text and can receive anything the user intentionally types or pastes into its session.
- The OS clipboard is outside MoriXterm's security boundary.
- RDP is provided by the installed FreeRDP client, and SSH/SCP by the installed OpenSSH client.
- Windows currently uses a QProcess fallback for the terminal backend; a native ConPTY backend is the recommended next step for full Windows terminal semantics.
