# MoriXterm 0.9.9

## SSH host-key management

- MoriXterm now uses its own `~/.config/morixtrem/known_hosts` file.
- First-seen SSH hosts use OpenSSH `StrictHostKeyChecking=accept-new`, so a new host is saved automatically.
- A changed host key is **not** silently accepted. MoriXterm detects the OpenSSH warning and shows an in-app security dialog.
- The dialog includes the SHA-256 fingerprint reported by OpenSSH when available.
- `Replace host key & connect` removes the old entry from MoriXterm's own known-hosts file using `ssh-keygen -R` and reconnects.
- The user's global `~/.ssh/known_hosts` is not modified by this flow.
- SSH file-manager/scp operations inherit the same dedicated known-hosts policy through `SshSecurity::commonOptions`.
