using System.Text;
using Renci.SshNet;
using Renci.SshNet.Common;
using Morixterm.Desktop.Models;

namespace Morixterm.Desktop.Services;

public sealed class SshSessionService : IDisposable
{
    private SshClient? _client;
    private ShellStream? _shell;
    public bool IsConnected => _client?.IsConnected == true;

    public async Task ConnectAsync(SavedSession session, Action<string> append)
    {
        await DisconnectAsync();
        if (string.IsNullOrWhiteSpace(session.Host)) throw new InvalidOperationException("Enter a server address.");
        if (string.IsNullOrWhiteSpace(session.Username)) throw new InvalidOperationException("Enter a username.");
        var connection = new PasswordConnectionInfo(session.Host, session.Port, session.Username, session.Password);
        _client = new SshClient(connection);
        await Task.Run(() => _client.Connect());
        _shell = _client.CreateShellStream("xterm", 120, 32, 800, 600, 4096);
        append($"Connected to {session.Username}@{session.Host}:{session.Port}\n\u001b[38;5;51m{session.Username}\u001b[0m@\u001b[38;5;141m{session.Host}\u001b[0m\n");
        _ = Task.Run(async () =>
        {
            while (IsConnected && _shell is not null)
            {
                if (_shell.DataAvailable) append(_shell.Read());
                await Task.Delay(25);
            }
        });
    }

    public Task WriteAsync(string text)
    {
        if (_shell is null) return Task.CompletedTask;
        _shell.Write(text);
        _shell.Flush();
        return Task.CompletedTask;
    }

    public async Task DisconnectAsync()
    {
        if (_client is null) return;
        await Task.Run(() => { if (_client.IsConnected) _client.Disconnect(); });
        _shell?.Dispose();
        _client.Dispose();
        _shell = null;
        _client = null;
    }

    public void Dispose() => _client?.Dispose();
}
