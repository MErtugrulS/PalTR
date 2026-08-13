namespace PalTRLauncher.Models;

public sealed record AccountSession(
    string Username,
    string Email,
    string AccessToken,
    DateTimeOffset AccessExpiresAt,
    string RefreshToken,
    DateTimeOffset RefreshExpiresAt);

public sealed record AccountOperationResult(bool Success, string Message, AccountSession? Session = null)
{
    public static AccountOperationResult Failed(string message) => new(false, message);
    public static AccountOperationResult Completed(string message, AccountSession? session = null)
        => new(true, message, session);
}
