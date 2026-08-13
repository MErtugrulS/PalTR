using PalTRLauncher.Models;

namespace PalTRLauncher.Services;

public interface IAccountService
{
    Task<AccountOperationResult> RegisterAsync(string username, string email, string password);
    Task<AccountOperationResult> LoginAsync(string identifier, string password);
    Task<AccountOperationResult> RefreshAsync(string refreshToken);
    Task LogoutAsync(string refreshToken);
}
