using PalTRLauncher.Models;

namespace PalTRLauncher.Services;

public sealed class DemoAccountService : IAccountService
{
    public const string DemoUsername = "Herakles";
    public const string DemoPassword = "PalTRDemo2026!";
    private const string DemoRefreshToken = "paltr-demo-refresh-v1";
    private readonly IAccountService remoteService;

    public DemoAccountService(IAccountService remoteService)
    {
        this.remoteService = remoteService;
    }

    public Task<AccountOperationResult> RegisterAsync(string username, string email, string password)
        => remoteService.RegisterAsync(username, email, password);

    public Task<AccountOperationResult> LoginAsync(string identifier, string password)
    {
        if (!identifier.Equals(DemoUsername, StringComparison.OrdinalIgnoreCase) || password != DemoPassword)
        {
            return remoteService.LoginAsync(identifier, password);
        }

        return Task.FromResult(AccountOperationResult.Completed(
            "Demo oturumu açıldı.",
            CreateDemoSession()));
    }

    public Task<AccountOperationResult> RefreshAsync(string refreshToken)
    {
        if (refreshToken == DemoRefreshToken)
        {
            return Task.FromResult(AccountOperationResult.Completed(
                "Demo oturumu yenilendi.",
                CreateDemoSession()));
        }

        return remoteService.RefreshAsync(refreshToken);
    }

    public Task LogoutAsync(string refreshToken)
        => refreshToken == DemoRefreshToken
            ? Task.CompletedTask
            : remoteService.LogoutAsync(refreshToken);

    private static AccountSession CreateDemoSession()
    {
        DateTimeOffset now = DateTimeOffset.UtcNow;
        return new AccountSession(
            DemoUsername,
            "demo@paltr.local",
            "paltr-demo-access-v1",
            now.AddHours(1),
            DemoRefreshToken,
            now.AddDays(30));
    }
}
