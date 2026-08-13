namespace PalTRLauncher.Models;

public sealed record PalTRUpdateManifest
{
    public int SchemaVersion { get; init; }
    public string Channel { get; init; } = string.Empty;
    public string Version { get; init; } = string.Empty;
    public string PackageUrl { get; init; } = string.Empty;
    public string Sha256 { get; init; } = string.Empty;
    public long Size { get; init; }
    public DateTimeOffset PublishedAtUtc { get; init; }
}
