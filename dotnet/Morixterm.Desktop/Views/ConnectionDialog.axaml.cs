using Avalonia.Controls;
using Avalonia.Interactivity;
using Morixterm.Desktop.Models;

namespace Morixterm.Desktop.Views;

public partial class ConnectionDialog : Window
{
    private readonly SavedSession? _initial;
    public SavedSession? Result { get; private set; }

    public ConnectionDialog(SavedSession? initial = null)
    {
        InitializeComponent();
        _initial = initial;
        if (initial is not null)
        {
            NameBox.Text = initial.Name; HostBox.Text = initial.Host; PortBox.Value = initial.Port;
            ProtocolBox.SelectedIndex = initial.IsSsh ? 1 : 0; UsernameBox.Text = initial.Username;
            PasswordBox.Text = initial.Password; SavePasswordBox.IsChecked = initial.Password.Length > 0;
            Title = "Edit session";
        }
    }

    private void Cancel(object? sender, RoutedEventArgs e) => Close(null);

    private void Connect(object? sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(NameBox.Text) || string.IsNullOrWhiteSpace(HostBox.Text) || string.IsNullOrWhiteSpace(UsernameBox.Text))
        { ErrorText.Text = "Name, host, and username are required."; return; }
        var ssh = ProtocolBox.SelectedIndex == 1;
        Result = new SavedSession
        {
            Name = NameBox.Text.Trim(), Host = HostBox.Text.Trim(),
            Port = (int)(PortBox.Value ?? (ssh ? 22 : 3389)), Username = UsernameBox.Text.Trim(),
            Password = SavePasswordBox.IsChecked == true ? PasswordBox.Text ?? "" : "",
            Protocol = ssh ? SessionProtocol.Ssh : SessionProtocol.Rdp, Folder = _initial?.Folder
        };
        Close(Result);
    }
}
