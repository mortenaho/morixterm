# MoriXterm 0.9.8

- Detects libcurl FTPS certificate verification failures (including curl exit code 60).
- Shows an in-app certificate warning instead of treating certificate errors as an MLSD capability failure.
- Adds **Trust once** for the running FTPS session.
- Adds an explicit per-profile certificate exception for known legacy/misconfigured FTPS hosts.
- Keeps TLS certificate verification enabled by default.
- Reuses the existing `ignore_certificate` session field, so no database migration is required.
- Applies the same TLS exception to listing, upload/download, and FTP remote commands.
