namespace PalTRLauncher.Models;

public sealed class LauncherSnapshot
{
    public string AccountName { get; init; } = "-";
    public string Membership { get; init; } = "Oyuncu";
    public string ServerName { get; init; } = "PalTR Ana Sunucu";
    public string ServerStatus { get; init; } = "Bakımda";
    public string ServerAddress { get; init; } = "Yapılandırılmadı";
    public int ActivePlayers { get; init; }
    public int Capacity { get; init; }
    public string LauncherVersion { get; init; } = "0.1.0";
    public string GameVersion { get; init; } = "-";
    public string ModVersion { get; init; } = "-";
    public int NotificationCount { get; init; }
    public IReadOnlyList<LauncherSlide> Slides { get; init; } = Array.Empty<LauncherSlide>();
    public IReadOnlyList<LauncherNews> News { get; init; } = Array.Empty<LauncherNews>();
    public IReadOnlyList<LauncherNotification> Notifications { get; init; } = Array.Empty<LauncherNotification>();
    public IReadOnlyList<LauncherTicket> Tickets { get; init; } = Array.Empty<LauncherTicket>();
}

public sealed record LauncherSlide(
    string Category,
    string Title,
    string Summary,
    string ImagePath,
    string TargetUrl);

public sealed record LauncherNews(string Category, string Title, string Summary, string PublishedAt);
public sealed record LauncherNotification(string Title, string Detail, string Time);
public sealed record LauncherTicket(string Number, string Subject, string State, string UpdatedAt);

public sealed record LauncherActionResult(bool Success, string Message);
