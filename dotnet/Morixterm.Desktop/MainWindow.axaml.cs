using System.Collections.ObjectModel;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Threading;
using Morixterm.Desktop.Models;
using Morixterm.Desktop.Services;
using Morixterm.Desktop.Views;

namespace Morixterm.Desktop;

public partial class MainWindow : Window
{
    private readonly SessionStore _store = new();
    private readonly SshSessionService _ssh = new();
    private readonly ObservableCollection<SavedSession> _sessions = [];
    private SavedSession? _active;

    public MainWindow()
    {
        InitializeComponent();
        SessionList.ItemsSource = _sessions;
        OpenSavedSessionsAsync();
    }

    private async void OpenSavedSessionsAsync()
    {
        foreach (var session in await _store.LoadAsync()) _sessions.Add(session);
        StatusText.Text = $"Ready · {_sessions.Count} saved sessions";
    }

    private async void NewSession(object? sender, RoutedEventArgs e)
    {
        var dialog = new ConnectionDialog();
        var result = await dialog.ShowDialog<SavedSession?>(this);
        if (result is null) return;
        _sessions.Add(result);
        await _store.SaveAsync(_sessions);
        await ActivateAsync(result);
    }

    private async void SessionMenu(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: SavedSession session }) return;
        var menu = new ContextMenu();
        var edit = new MenuItem { Header = "Edit session" };
        edit.Click += async (_, _) =>
        {
            var dialog = new ConnectionDialog(session);
            var updated = await dialog.ShowDialog<SavedSession?>(this);
            if (updated is null) return;
            var index = _sessions.IndexOf(session);
            _sessions[index] = updated;
            await _store.SaveAsync(_sessions);
        };
        var remove = new MenuItem { Header = "Delete session" };
        remove.Click += async (_, _) => { _sessions.Remove(session); await _store.SaveAsync(_sessions); };
        menu.Items.Add(edit); menu.Items.Add(remove); menu.Open(sender as Control);
    }

    private async void OpenSession(object? sender, RoutedEventArgs e)
    {
        if (SessionList.SelectedItem is SavedSession session) await ActivateAsync(session);
    }

    private async Task ActivateAsync(SavedSession session)
    {
        _active = session;
        WelcomePane.IsVisible = false; FilesPane.IsVisible = false; SessionPane.IsVisible = true;
        SessionTitle.Text = session.Name; SessionEndpoint.Text = $"{session.ProtocolLabel} · {session.Endpoint}";
        SessionState.Text = "Connecting…"; TerminalOutput.Text = "";
        if (!session.IsSsh)
        {
            SessionState.Text = "Backend unavailable";
            TerminalOutput.Text = "RDP session target selected.\n\nThe RDP surface is intentionally kept behind a platform service boundary.\nAdd a native FreeRDP/Windows backend without changing this workspace.\n";
            StatusText.Text = "RDP target ready";
            return;
        }
        try
        {
            await _ssh.ConnectAsync(session, AppendTerminal);
            SessionState.Text = "Connected"; StatusText.Text = $"Connected · {session.Username}@{session.Host}";
        }
        catch (Exception ex)
        {
            SessionState.Text = "Connection failed"; StatusText.Text = ex.Message;
            TerminalOutput.Text = $"SSH connection failed\n{ex.Message}";
        }
    }

    private void AppendTerminal(string text)
    {
        Dispatcher.UIThread.Post(() =>
        {
            TerminalOutput.Text += text;
            TerminalOutput.CaretIndex = TerminalOutput.Text?.Length ?? 0;
        });
    }

    private async void TerminalKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter || _active?.IsSsh != true) return;
        var command = TerminalInput.Text ?? "";
        TerminalInput.Text = "";
        await _ssh.WriteAsync(command + "\n");
        e.Handled = true;
    }

    private void Home(object? sender, RoutedEventArgs e)
    {
        _ = _ssh.DisconnectAsync(); _active = null;
        WelcomePane.IsVisible = true; SessionPane.IsVisible = false; FilesPane.IsVisible = false;
        StatusText.Text = "Ready";
    }

    private void OpenFiles(object? sender, RoutedEventArgs e)
    {
        WelcomePane.IsVisible = false; SessionPane.IsVisible = false; FilesPane.IsVisible = true;
        FilesMessage.Text = _active is null ? "Connect to a session to browse remote files." :
            "Remote file browsing is ready for the next backend adapter.\nSSH: implement SFTP through the same session service boundary.\nRDP: expose the shared-folder virtual channel here.";
    }

    private async void Disconnect(object? sender, RoutedEventArgs e)
    {
        await _ssh.DisconnectAsync();
        if (_active is not null) SessionState.Text = "Disconnected";
        StatusText.Text = "Disconnected";
    }

    private void FilesUnavailable(object? sender, RoutedEventArgs e) => StatusText.Text = "Connect a session before using remote files.";
    private void NewFolder(object? sender, RoutedEventArgs e) => StatusText.Text = "Folders are persisted with session metadata in the next iteration.";
    private void About(object? sender, RoutedEventArgs e) => StatusText.Text = "Morixterm · Avalonia desktop rewrite";
    private void Fullscreen(object? sender, RoutedEventArgs e) => WindowState = WindowState == WindowState.FullScreen ? WindowState.Normal : WindowState.FullScreen;

    protected override async void OnClosed(EventArgs e)
    {
        await _ssh.DisconnectAsync();
        _ssh.Dispose();
        base.OnClosed(e);
    }
}
