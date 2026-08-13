# PalTR Launcher

PalTR oyun içi UI'sinden bağımsız Windows launcher istemcisidir.

## Mevcut UI kapsamı

- Sunucu durumu ve aktif oyuncu özeti
- Sunucuya katılma giriş noktası
- Haberler ve bildirim merkezi
- Destek talebi formu ve talep listesi
- Hesap yönetimi iskeleti
- Launcher, oyun ve mod sürüm özeti
- Sonradan yeni sayfalar eklenebilen sol navigasyon
- Yönetim panelinden beslenecek bağlantılı reklam/duyuru slider sözleşmesi

## Görsel mimari

- Referanstaki koyu katmanlı yüzey, eskitilmiş ince altın çerçeve, düşük
  opaklıklı ornament ve parşömen hissi launcher bileşenlerine uyarlanır.
- Tema ve tekrar kullanılabilir bileşenler `Themes/PalTRTheme.xaml` altında
  tutulur.
- Navigasyon satırları birbirinden bağımsızdır; gelecekte Battle Pass veya
  farklı bir modül mevcut sayfalar değiştirilmeden eklenebilir.
- Slider yalnızca reklam ve duyuru yayını içindir; sunucuya katılma ve yenileme
  işlemleri ayrı sunucu durumu kartında tutulur.
- Slider içeriği `LauncherSlide` modeliyle sunumdan ayrıdır. Yönetim paneli
  başlık, açıklama, bağlantı etiketi ve güvenli HTTP(S) hedefini besleyebilir.

Uygulama şu anda `DemoLauncherService` kullanır. Gerçek API adresi, kimlik
doğrulama, güncelleme manifesti veya oyun başlatma komutu tahmin edilmemiştir.
Bu nedenle **Sunucuya Katıl** butonu oyunu çalıştırmaz.

## Demo giriş

- Kullanıcı adı: `Herakles`
- Parola: `PalTRDemo2026!`

`Beni hatırla` seçildiğinde yalnız kullanıcı adı yerel uygulama verisine
kaydedilir; parola diske yazılmaz. Hesap sayfasındaki **Oturumu Kapat** işlemi
hatırlanan oturumu temizler.

## Steam hesap eşleştirme sözleşmesi

Launcher SteamID64 değerini yerel Steam dosyalarından okuyup doğrulanmış kabul
etmez. Güvenli bağlantı akışı PalTR hesap sunucusunda tamamlanmalıdır:

1. Oturum açmış hesap için tek kullanımlık, süreli ve hesaba bağlı bir bağlantı
   isteği oluşturulur.
2. Launcher yalnız sunucunun döndürdüğü Steam OpenID adresini tarayıcıda açar.
3. OpenID dönüşü sunucuda doğrulanır; dönen claimed ID içindeki SteamID64 hesaba
   benzersiz olarak bağlanır.
4. Launcher durum uç noktasından yalnız sunucunun doğruladığı SteamID64 ve
   görünen Steam adını alır.
5. Bağlantıyı kaldırma işlemi yeniden kimlik doğrulama ve sunucu yetkisi ister.

Steam publisher/Web API anahtarı launcher içine veya yerel ayarlara konmaz.
`ISteamAccountLinkService` bu backend sözleşmesinin istemci sınırıdır. Gerçek
hesap API'si yapılandırılana kadar `UnavailableSteamAccountLinkService` sahte
bir Steam kimliği üretmeden bekleme durumunu gösterir.

## Derleme

PowerShell:

```powershell
dotnet build Client\PalTRLauncher\PalTRLauncher.csproj -c Debug
```

Çalıştırma:

```powershell
dotnet run --project Client\PalTRLauncher\PalTRLauncher.csproj
```

## Gerçek servis bağlantısı

Sonraki fazda `ILauncherService` uygulaması şu sunucu uçlarına bağlanacak:

- oturum açma ve hesap profili
- sunucu durumu ve aktif oyuncu sayısı
- sürüm manifesti ve güvenli dosya güncellemesi
- destek talepleri
- bildirimler ve duyurular
- doğrulanmış doğrudan sunucuya katılma bileti

UI, servis uygulamasından ayrıldığı için bu bağlantılar tasarım yeniden
yazılmadan eklenebilir.
