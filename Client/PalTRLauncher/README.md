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

## Yerel kurulum ve güncelleme

Launcher açılışı ve hesap girişi güncellemeye bağlı değildir. Kullanıcı launcher'a
girebilir; PalTR kurulumu yalnız **Sunucuya Katıl** işleminden önce zorunlu tutulur.
Ana sayfadaki **Kur / Güncelle / Onar** işlemi isteğe bağlı olarak çalıştırılır.

`LocalPalTRInstallationService`:

- Steam kayıtları ve `libraryfolders.vdf` üzerinden Palworld kurulumunu bulur.
- Publish çıktısındaki `Payload/PalTRUI` içeriğini kaynak kabul eder.
- Publish çıktısındaki doğrulanmış `Payload/Dependencies` dağıtımından Win64
  UE4SS proxy/runtime zincirini ve `UE4SSExperimentalPW` kaydını otomatik ekler.
- PalTRUI pak, Lua ve `Info.json` dosyalarını SHA-256 ile doğrular.
- Win64 runtime içindeki mevcut `UE4SS-settings.ini`, `mods.txt` ve `mods.json`
  kullanıcı ayarlarını korur; çekirdek bağımlılık dosyalarını yedekleyerek onarır.
- Win64 UE4SS `mods.json` ve geriye dönük `mods.txt` içindeki yalnız `PalTRUI`
  kaydını etkinleştirir; diğer modların durumunu ve yerleşik `Keybinds` sırasını
  korur.
- Çift yüklemeyi önlemek için eski Workshop `UE4SS.dll` dosyasını yedekli ve
  geri alınabilir bir adla devre dışı bırakır; eski PalTRUI Lua dizinini yedekleyip
  doğru Win64 runtime dizinine taşır.
- Palworld resmi mod yöneticisinin `PalModSettings.ini` kaydında
  `UE4SSExperimentalPW` bağımlılığını etkinleştirir ve eksik yönetilen mod
  `InstallManifest.json` dosyasını üretir; mevcut diğer aktif mod kayıtlarını korur.
- Yalnız değişen dosyaları yedekleyerek geçici dosya üzerinden atomik değiştirir.
- Bir hata oluşursa o işlemde değiştirdiği dosyaları geri alır.
- Palworld çalışırken mod dosyalarını değiştirmez.

PalTRUI, UE4SS ve `UE4SSExperimentalPW` payload'ları proje publish edilirken
otomatik eklenir. UE4SS lisansı bağımlılık dizininde dağıtılır. Eksik bileşenler
**Kur / Güncelle / Onar** işlemiyle birlikte kurulur; ayrı bir manuel mod
kurulumu gerekmez.

## GitHub Releases üzerinden güncelleme

Launcher, public `MErtugrulS/PalTR` reposunun en son GitHub Release'inde bulunan
`paltr-update.json` manifestini denetler. Manifestte yeni sürüm varsa **Güncelle**
işlemi ZIP paketini indirir; boyutunu ve SHA-256 değerini doğrular, arşivi yol
geçişine karşı kontrollü biçimde açar ve mevcut yedekli kurulum katmanına teslim
eder. Ağ veya GitHub kullanılamazsa launcher açılmaya devam eder ve gömülü paket
kurtarma seçeneği olarak korunur.

Release dosyalarını üretmek için repo kökünde:

```powershell
powershell -ExecutionPolicy Bypass -File Scripts/New-PalTRUIReleaseAssets.ps1
```

Çıktıdaki ZIP ve `paltr-update.json`, scriptin bildirdiği aynı tag ile oluşturulan
GitHub Release'e eklenmelidir. Launcher özel repo tokenı içermez; bu akış public
release dosyaları içindir.

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
