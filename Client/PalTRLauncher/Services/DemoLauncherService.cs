using PalTRLauncher.Models;

namespace PalTRLauncher.Services;

public sealed class DemoLauncherService : ILauncherService
{
    public Task<LauncherSnapshot> GetSnapshotAsync(CancellationToken cancellationToken = default)
    {
        LauncherSnapshot snapshot = new()
        {
            AccountName = "Herakles",
            Membership = "Kurucu Paket",
            ServerName = "PalTR Ana Sunucu",
            ServerStatus = "Çevrimiçi",
            ServerAddress = "API bağlantısı bekleniyor",
            ActivePlayers = 12,
            Capacity = 32,
            LauncherVersion = "0.1.0-ui",
            GameVersion = "v0.6.x",
            ModVersion = "UI Faz-00",
            NotificationCount = 2,
            Slides = new[]
            {
                new LauncherSlide(
                    "PALTR ANA SUNUCU",
                    "Maceraya kaldığın yerden devam et.",
                    "Topluluğa bağlan, sunucu durumunu gör ve PalTR güncellemelerini tek merkezden yönet.",
                    "SUNUCUYA KATIL",
                    string.Empty),
                new LauncherSlide(
                    "TOPLULUK DUYURUSU",
                    "PalTR dünyasındaki yenilikleri keşfet.",
                    "Yönetim panelinden yayınlanacak duyuru, etkinlik ve bağlantılar bu vitrinde oyunculara ulaşacak.",
                    "DETAYI AÇ",
                    "https://www.palworldgame.com/"),
                new LauncherSlide(
                    "GÜNCELLEME NOTLARI",
                    "Launcher ve mod sürümleri tek merkezde.",
                    "Yeni sürümler, bakım duyuruları ve kurulum bilgileri yayınlandığı anda burada görüntülenecek.",
                    "HABERLERİ GÖR",
                    string.Empty)
            },
            News = new[]
            {
                new LauncherNews(
                    "GÜNCELLEME",
                    "PalTR Launcher hazırlıkları başladı",
                    "Hesap, destek, güncelleme ve tek tıkla sunucuya katılma deneyimi tek uygulamada toplanıyor.",
                    "Bugün"),
                new LauncherNews(
                    "SUNUCU",
                    "Diplomasi sistemi geliştirme notları",
                    "Klan ilişkileri ve sunucu snapshot altyapısı launcher servis sözleşmesine hazırlandı.",
                    "Dün"),
                new LauncherNews(
                    "TOPLULUK",
                    "Geri bildirim merkezi",
                    "Destek talepleri ve oyuncu bildirimleri için yeni ekran taslağı kullanıma açıldı.",
                    "2 gün önce")
            },
            Notifications = new[]
            {
                new LauncherNotification("Yeni launcher sürümü", "UI iskeleti ve servis sözleşmesi hazır.", "Şimdi"),
                new LauncherNotification("Sunucu duyurusu", "Haftalık bakım bilgisi yakında yayınlanacak.", "1 saat önce")
            },
            Tickets = new[]
            {
                new LauncherTicket("#PTR-1042", "Karakter aktarımı hakkında", "Yanıtlandı", "Bugün"),
                new LauncherTicket("#PTR-1031", "Bağlantı sorunu", "İnceleniyor", "Dün")
            }
        };

        return Task.FromResult(snapshot);
    }

    public Task<LauncherActionResult> PrepareDirectJoinAsync(CancellationToken cancellationToken = default)
        => Task.FromResult(new LauncherActionResult(
            false,
            "Doğrudan katılma API'si henüz yapılandırılmadı; oyun başlatılmadı."));

    public Task<LauncherActionResult> CheckForUpdatesAsync(CancellationToken cancellationToken = default)
        => Task.FromResult(new LauncherActionResult(
            true,
            "Demo kontrol tamamlandı. Gerçek sürüm manifesti sonraki fazda bağlanacak."));

    public Task<LauncherActionResult> CreateSupportTicketAsync(
        string subject,
        string message,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(subject) || string.IsNullOrWhiteSpace(message))
        {
            return Task.FromResult(new LauncherActionResult(
                false,
                "Konu ve açıklama alanlarını doldurun."));
        }

        return Task.FromResult(new LauncherActionResult(
            true,
            "Talep demo modunda doğrulandı; sunucuya gönderilmedi."));
    }
}
