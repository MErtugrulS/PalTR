namespace PalTR.Accounts;

public sealed class AccountOptions
{
    public string DatabasePath { get; set; } = "Data/paltr-accounts.db";
    public string PublicBaseUrl { get; set; } = "http://localhost:5086";
    public int AccessTokenMinutes { get; set; } = 20;
    public int RefreshTokenDays { get; set; } = 30;
    public int VerificationTokenHours { get; set; } = 24;
}

public sealed class SmtpOptions
{
    public string Host { get; set; } = string.Empty;
    public int Port { get; set; } = 587;
    public bool UseSsl { get; set; } = true;
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public string FromAddress { get; set; } = string.Empty;
    public string FromName { get; set; } = "PalTR";
    public bool IsConfigured => !string.IsNullOrWhiteSpace(Host) && !string.IsNullOrWhiteSpace(FromAddress);
}
