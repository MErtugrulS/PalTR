using PalTRLauncher.Models;

namespace PalTRLauncher.Services;

public interface IInstallationService
{
    Task<InstallationSnapshot> InspectAsync(CancellationToken cancellationToken = default);
    Task<InstallationActionResult> InstallOrRepairAsync(CancellationToken cancellationToken = default);
}
