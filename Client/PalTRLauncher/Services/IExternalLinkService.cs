using PalTRLauncher.Models;

namespace PalTRLauncher.Services;

public interface IExternalLinkService
{
    LauncherActionResult Open(string targetUrl);
}
