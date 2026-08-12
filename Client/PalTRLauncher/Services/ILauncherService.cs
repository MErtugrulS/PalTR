using PalTRLauncher.Models;

namespace PalTRLauncher.Services;

public interface ILauncherService
{
    Task<LauncherSnapshot> GetSnapshotAsync(CancellationToken cancellationToken = default);
    Task<LauncherActionResult> PrepareDirectJoinAsync(CancellationToken cancellationToken = default);
    Task<LauncherActionResult> CheckForUpdatesAsync(CancellationToken cancellationToken = default);
    Task<LauncherActionResult> CreateSupportTicketAsync(
        string subject,
        string message,
        CancellationToken cancellationToken = default);
}
