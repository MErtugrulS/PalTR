namespace PalTRLauncher.Models;

public enum InstallationState
{
    Checking,
    Ready,
    InstallRequired,
    Blocked,
    Failed
}

public sealed record InstallationSnapshot(
    InstallationState State,
    string Title,
    string Detail,
    string? GameRoot = null,
    string? PackageVersion = null)
{
    public bool IsReady => State == InstallationState.Ready;
    public bool CanInstall => State == InstallationState.InstallRequired;
    public bool CanRepair => State == InstallationState.Ready;
    public bool CanRetry => State is InstallationState.Blocked or InstallationState.Failed;

    public static InstallationSnapshot Checking { get; } = new(
        InstallationState.Checking,
        "Kurulum denetleniyor",
        "Palworld ve PalTR bileşenleri doğrulanıyor.");
}

public sealed record InstallationActionResult(
    bool Success,
    InstallationSnapshot Snapshot);
