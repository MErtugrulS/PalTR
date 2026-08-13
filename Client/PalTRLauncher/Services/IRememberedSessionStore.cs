namespace PalTRLauncher.Services;

public interface IRememberedSessionStore
{
    string? LoadAccountName();
    void SaveAccountName(string accountName);
    void Clear();
}
