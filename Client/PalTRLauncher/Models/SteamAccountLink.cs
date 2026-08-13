namespace PalTRLauncher.Models;

public enum SteamAccountLinkState
{
    Unavailable,
    Unlinked,
    Pending,
    Linked,
    Failed
}

public sealed record SteamAccountLinkSnapshot(
    SteamAccountLinkState State,
    string StatusLabel,
    string Detail,
    string? SteamId64 = null,
    string? PersonaName = null)
{
    public static SteamAccountLinkSnapshot BackendUnavailable { get; } = new(
        SteamAccountLinkState.Unavailable,
        "Bağlantı servisi bekleniyor",
        "Steam hesabı yalnız PalTR sunucusu tarafından doğrulandıktan sonra bağlanabilir.");
}

public sealed record SteamAccountLinkActionResult(
    bool Success,
    string Message,
    SteamAccountLinkSnapshot Snapshot,
    string? AuthorizationUrl = null);
