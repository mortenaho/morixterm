using System.Text.Json.Serialization;

namespace Morixterm.Desktop.Models;

public enum SessionProtocol { Rdp, Ssh }

public sealed class SavedSession
{
    public string Name { get; set; } = "New session";
    public string Host { get; set; } = "";
    public int Port { get; set; } = 3389;
    public string Username { get; set; } = "";
    public string Password { get; set; } = "";
    public SessionProtocol Protocol { get; set; } = SessionProtocol.Rdp;
    public string? Folder { get; set; }

    [JsonIgnore] public bool IsSsh => Protocol == SessionProtocol.Ssh;
    [JsonIgnore] public string ProtocolLabel => IsSsh ? "SSH" : "RDP";
    [JsonIgnore] public string Endpoint => $"{Host}:{Port}";

    public SavedSession Copy() => new()
    {
        Name = Name, Host = Host, Port = Port, Username = Username,
        Password = Password, Protocol = Protocol, Folder = Folder
    };

    public bool SameBookmark(SavedSession other) => Name == other.Name && Host == other.Host &&
        Port == other.Port && Username == other.Username && Protocol == other.Protocol;
}
