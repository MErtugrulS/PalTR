using System.Diagnostics;
using PalTRLauncher.Models;

namespace PalTRLauncher.Services;

public sealed class SystemExternalLinkService : IExternalLinkService
{
    public LauncherActionResult Open(string targetUrl)
    {
        if (!Uri.TryCreate(targetUrl, UriKind.Absolute, out Uri? uri)
            || (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps))
        {
            return new LauncherActionResult(false, "Bu paylaşım için güvenli bir bağlantı henüz tanımlanmadı.");
        }

        try
        {
            Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true });
            return new LauncherActionResult(true, "Paylaşım bağlantısı tarayıcıda açıldı.");
        }
        catch (Exception)
        {
            return new LauncherActionResult(false, "Paylaşım bağlantısı açılamadı.");
        }
    }
}
