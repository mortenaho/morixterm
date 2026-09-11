# Morixterm · .NET / Avalonia

This directory is the Avalonia UI rewrite of the Flutter desktop client. It keeps the product boundaries from the original application while moving the shell to C#:

- dark desktop workspace with toolbar, saved-session sidebar, tabs, status bar, and files pane;
- RDP and SSH session models with JSON persistence in the platform local application-data directory;
- SSH connections and interactive shell through `SSH.NET`;
- RDP and remote-file operations exposed as replaceable service boundaries until a platform-native backend is selected.

## Run

```bash
cd dotnet/Morixterm.Desktop
dotnet restore
dotnet run
```

The project targets .NET 10 and Avalonia 11.3. The RDP target is intentionally represented in the UI but does not pretend to be connected; wire a FreeRDP or Windows Remote Desktop adapter into the session service before enabling production RDP connections.
