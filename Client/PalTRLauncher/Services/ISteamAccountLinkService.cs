using PalTRLauncher.Models;

namespace PalTRLauncher.Services;

public interface ISteamAccountLinkService
{
    Task<SteamAccountLinkSnapshot> GetStatusAsync(
        CancellationToken cancellationToken = default);

    Task<SteamAccountLinkActionResult> BeginLinkAsync(
        CancellationToken cancellationToken = default);

    Task<SteamAccountLinkActionResult> UnlinkAsync(
        CancellationToken cancellationToken = default);
}
