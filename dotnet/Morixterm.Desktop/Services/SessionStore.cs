using System.Text.Json;
using Morixterm.Desktop.Models;

namespace Morixterm.Desktop.Services;

public sealed class SessionStore
{
    private readonly string _file = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Morixterm", "sessions.json");
    private readonly JsonSerializerOptions _options = new() { WriteIndented = true };

    public async Task<List<SavedSession>> LoadAsync()
    {
        if (!File.Exists(_file)) return DefaultSessions();
        try { return JsonSerializer.Deserialize<List<SavedSession>>(await File.ReadAllTextAsync(_file), _options) ?? []; }
        catch { return DefaultSessions(); }
    }

    public async Task SaveAsync(IEnumerable<SavedSession> sessions)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_file)!);
        await File.WriteAllTextAsync(_file, JsonSerializer.Serialize(sessions, _options));
    }

    private static List<SavedSession> DefaultSessions() =>
    [
        new() { Name = "Windows Server", Host = "192.168.1.10", Port = 3389, Username = "admin" },
        new() { Name = "Linux SSH", Host = "192.168.1.20", Port = 22, Username = "root", Protocol = SessionProtocol.Ssh }
    ];
}
