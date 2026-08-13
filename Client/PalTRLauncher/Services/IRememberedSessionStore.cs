using PalTRLauncher.Models;

namespace PalTRLauncher.Services;

public interface IRememberedSessionStore
{
    AccountSession? Load();
    void Save(AccountSession session);
    void Clear();
}
