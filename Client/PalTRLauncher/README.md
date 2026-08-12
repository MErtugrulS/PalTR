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
- Yönetim panelinden beslenecek bağlantılı ana sayfa slider sözleşmesi

## Görsel mimari

- Referanstaki koyu katmanlı yüzey, eskitilmiş ince altın çerçeve, düşük
  opaklıklı ornament ve parşömen hissi launcher bileşenlerine uyarlanır.
- Tema ve tekrar kullanılabilir bileşenler `Themes/PalTRTheme.xaml` altında
  tutulur.
- Navigasyon satırları birbirinden bağımsızdır; gelecekte Battle Pass veya
  farklı bir modül mevcut sayfalar değiştirilmeden eklenebilir.
- Slider içeriği `LauncherSlide` modeliyle sunumdan ayrıdır. Yönetim paneli
  başlık, açıklama, bağlantı etiketi ve güvenli HTTP(S) hedefini besleyebilir.

Uygulama şu anda `DemoLauncherService` kullanır. Gerçek API adresi, kimlik
doğrulama, güncelleme manifesti veya oyun başlatma komutu tahmin edilmemiştir.
Bu nedenle **Sunucuya Katıl** butonu oyunu çalıştırmaz.

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
