using PalTRLauncher.Models;

namespace PalTRLauncher.Services;

public sealed class UnavailableSteamAccountLinkService : ISteamAccountLinkService
{
    private const string UnavailableMessage =
        "Steam bağlantısı için PalTR hesap API'si henüz yapılandırılmadı.";

    public Task<SteamAccountLinkSnapshot> GetStatusAsync(
        CancellationToken cancellationToken = default)
        => Task.FromResult(SteamAccountLinkSnapshot.BackendUnavailable);

    public Task<SteamAccountLinkActionResult> BeginLinkAsync(
        CancellationToken cancellationToken = default)
        => Task.FromResult(new SteamAccountLinkActionResult(
            false,
            UnavailableMessage,
            SteamAccountLinkSnapshot.BackendUnavailable));

    public Task<SteamAccountLinkActionResult> UnlinkAsync(
        CancellationToken cancellationToken = default)
        => Task.FromResult(new SteamAccountLinkActionResult(
            false,
            UnavailableMessage,
            SteamAccountLinkSnapshot.BackendUnavailable));
}
