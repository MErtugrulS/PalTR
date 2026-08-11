# PalTRUI Manuel Widget Tasarım Kılavuzu

Bu kılavuz, PalTR panelinin görsel tasarımını Unreal Editor içinde manuel
olarak hazırlarken mevcut Lua veri bağlantısını ve çalışan etkileşimleri
korumak için hazırlanmıştır.

## 1. Sıfırdan tasarım çalışma düzeni

Eski otomatik tasarım katmanları temizlenmiştir. Tasarıma başlamak için Unreal
Editor içinde hazırlanan şu bağımsız şablonu aç:

`/Game/Mods/PalTRUI/WBP_PalTRPanel_DesignTemplate`

Bu asset yalnız component hiyerarşisi, referansa yakın yerleşim, placeholder
metinler, temel hover stilleri ve tıklama kalkanı içerir. Sunucu verisi veya
diplomasi aksiyonları bağlı değildir.

İlk aşamada yalnız bu şablonun görsel tasarımını tamamla. Tasarım onaylandıktan
sonra şablonun son halini runtime yolu olan aşağıdaki assete taşıyıp kod
bağlantılarını birlikte kuracağız:

`/Game/Mods/PalTRUI/WBP_PalTRPanel`

Runtime artık `WBP_PalTRPanel_SkinV2` aramaz. Eski otomatik SkinV2 ve tam
panel kaplama assetleri kaldırılmıştır.

Şablondaki `Template...` adlı componentleri yeniden düzenleyebilir, çoğaltabilir
ve anlaşılır geçici adlarla değiştirebilirsin.
Görsel tasarım tamamlandıktan sonra bu kılavuzdaki runtime adlarını ve kod
bağlantılarını birlikte uygulayacağız. Tasarım tamamlanana kadar F6 panelinin
çalışması beklenmez.

Referans görseller şurada bulunur:

`Client/PalTRUI/Unreal/DesignReference/pixel-match-1672x941`

### Header için ayrı çalışma componenti

Content Browser yolu:

`Content/Mods/PalTRUI/WBP_PalTRHeader_DesignTemplate`

Bu component 1511x77 piksel referans header görselini doğrudan taban katmanı
olarak kullanır. Yalnız şu düzenlenebilir kontroller görselin üstündedir:

- `HeaderActivePlayerCountText`: başlangıç örneği `Aktif oyuncu sayısı: 12`
- `HeaderNotificationsButton`: hover/pressed durumu olan tıklanabilir alan
- `HeaderCloseButton`: görünür X kapatma butonu
- `HeaderInputShield`: header içindeki boş tıklamaların oyuna geçmesini önler

Bu ilk parçada butonlara runtime aksiyonu veya sunucu verisi bağlanmamıştır.

Referans görseli tam ekran bir Image olarak widget'ın üstüne koyma. Görseli
ikinci monitörde veya Image Comparison aracıyla yalnızca ölçü referansı olarak
kullan.

## 2. Entegrasyon aşamasındaki temel çalışma kuralı

Bu bölüm tasarım bittikten sonra kod bağlantısı yapılırken uygulanacaktır.

Bir widget'ın görünüşünü, boyutunu, padding değerini, rengini, fontunu,
brush'ını, anchor'ını ve animasyonunu değiştirebilirsin. Runtime tarafından
aranan widget adlarını değiştirme ve bu widget'larda `Is Variable` seçeneğini
kapatma.

Bir alanı tamamen yeniden tasarlamak istersen:

1. Runtime widget'ını silme.
2. Onu yeni oluşturduğun Border, Overlay, Size Box veya Scale Box içine taşı.
3. Runtime adını aynı bırak.
4. Yeni dekoratif widget'lara istediğin adı ver.

Bu yöntem veri bağlantısını korurken tasarımı tamamen değiştirmene izin verir.

## 3. Değişmemesi gereken ana widget adları

### Panel ve giriş katmanı

- `RootCanvas`
- `PanelInputShield`
- `PanelBackground`
- `TitleText`
- `ConnectionStatusText`
- `CloseButton`

`PanelInputShield`, panel açıkken oyun dünyasına mouse tıklamasının geçmesini
engeller. Panelin etkileşim alanını kaplamalı ve `Visible` olmalıdır. Dekoratif
Image widget'ları ise butonları engellememesi için `Not Hit-Testable (Self & All
Children)` olmalıdır.

### Üst durum alanı

- `HeaderGuildText`
- `HeaderRoleText`
- `HeaderNotificationText`

Bu metinlere sabit klan adı veya rol yazma. Oyun sırasında sunucu snapshot'ı
tarafından güncellenirler.

### Ana sekmeler

| Sayfa | Buton | Buton metni | Sayfa sırası |
|---|---|---|---:|
| Klanım | `ClanTabButton` | `ClanTabText` | 0 |
| Diplomasi | `DiplomacyTabButton` | `DiplomacyTabText` | 1 |
| İttifak | `AllianceTabButton` | `AllianceTabText` | 2 |
| Klanlar | `ChatTabButton` | `ChatTabText` | 3 |

Sekmelerin tamamı `ContentSwitcher` ile çalışır. `ContentSwitcher` içindeki
sayfa sırasını değiştirme. Görselde soldaki menüye taşıyabilir, butonların
stilini tamamen değiştirebilirsin.

## 4. Klanım sayfası veri alanları

Temel klan bilgileri:

- `ClanNameText`
- `ClanSummaryText`
- `ClanMembersHeadingText`
- `ClanMembersStatusText`
- `ClanMembersText`
- `PendingOffersText`

Ana durum kartları:

- `DashboardClanCardTitleText`
- `DashboardClanCardValueText`
- `DashboardClanCardDetailText`
- `DashboardDiplomacyCardTitleText`
- `DashboardDiplomacyCardValueText`
- `DashboardDiplomacyCardDetailText`
- `DashboardRelationsText`

Hızlı işlem butonları:

| İşlem | Buton | Metin widget'ı |
|---|---|---|
| Diplomasi ekranını aç | `DashboardDiplomacyButton` | `DashboardDiplomacyButtonText` |
| Teklifleri göster | `DashboardOffersButton` | `DashboardOffersButtonText` |
| Klanları listele | `DashboardGuildsButton` | `DashboardGuildsButtonText` |
| Bekleyen teklifi kabul et | `DashboardPendingAcceptButton` | `DashboardPendingAcceptButtonText` |
| Bekleyen teklifi reddet | `DashboardPendingRejectButton` | `DashboardPendingRejectButtonText` |

Koruma ve Yapılar kartları şimdilik görsel/mock alan olabilir. Bunların içinde
sunucudan geliyormuş gibi sahte aktif değer gösterme; `Yakında` veya pasif
durum kullan.

## 5. Diplomasi sayfası

İlişki listesi ve seçili klan ayrıntıları:

- `RelationListEmptyText`
- `RelationTitleText`
- `RelationStateText`
- `RelationDescriptionText`
- `PreviousRelationButton`
- `PreviousRelationButtonText`
- `NextRelationButton`
- `NextRelationButtonText`

Diplomasi işlem butonları:

- `AllianceRequestButton` / `AllianceRequestButtonText`
- `WarRequestButton` / `WarRequestButtonText`
- `AcceptButton` / `AcceptButtonText`
- `RejectButton` / `RejectButtonText`
- `CancelButton` / `CancelButtonText`

Butonların enabled/disabled durumunu runtime belirler. Disabled görünümünü
Button Style içindeki `Disabled` brush ve renk alanından tasarla; Blueprint'te
zorla enabled yapma.

## 6. İttifak sayfası

- `AllianceSummaryText`
- `AllianceMembersText`
- `AllianceTitleText`
- `AllianceStateText`
- `AllianceDescriptionText`
- `PreviousAllianceButton`
- `PreviousAllianceButtonText`
- `NextAllianceButton`
- `NextAllianceButtonText`

Önceki/Sonraki butonlarını görsel olarak kart, ok veya liste seçimi biçimine
çevirebilirsin. Adları korunduğu sürece davranış bozulmaz.

## 7. Klanlar sayfası

Eski isimlendirmeden kalan `Chat` adlarını değiştirme; runtime bunları Klanlar
sayfası olarak kullanır:

- `ChatTabButton`
- `ChatTabText`
- `ChatEmptyText`
- `GuildCatalogSummaryText`
- `GuildCatalogActiveHeadingText`
- `GuildCatalogActiveText`
- `GuildCatalogRegisteredHeadingText`
- `GuildCatalogRegisteredText`

Sohbet özelliği şimdilik geliştirilmediği için yeni sohbet alanı eklemek
zorunlu değildir.

## 8. İsteğe bağlı sunum widget'ları

Aşağıdaki kontroller varsa runtime günceller, yoksa panel hata vermez. Manuel
tasarımında kullanmak zorunda değilsin:

- `DashboardPendingGuildText`
- `DashboardPendingStateText`
- `DashboardClanRoleValueText`
- `DashboardClanMembersValueText`
- `DashboardDiplomacyWarValueText`
- `DashboardDiplomacyAllianceValueText`
- `DashboardDiplomacyPendingValueText`
- `DashboardRelationRow1NameText` ... `DashboardRelationRow3NameText`
- `DashboardRelationRow1StateText` ... `DashboardRelationRow3StateText`

## 9. Buton hover ve tıklama ayarları

Her aktif Button için `Style` alanında şu dört durumun ayrı brush'ı olmalı:

- Normal
- Hovered
- Pressed
- Disabled

Önerilen davranış:

- Normal: koyu lacivert, ince altın kenar.
- Hovered: bir miktar daha açık arka plan ve camgöbeği/altın vurgu.
- Pressed: hafif koyu renk ve 1-2 px içeride görünüm.
- Disabled: düşük doygunluk ve yaklaşık yüzde 45-60 opacity.

Butonun üzerine dekoratif bir Image koyarsan Image'ın hit-test özelliğini
kapat. Aksi halde hover çalışır gibi görünse bile tıklama Button'a ulaşmaz.

## 10. Referansa göre yerleşim

Referans çözünürlüğü `1672 x 941` ve yaklaşık `16:9` oranındadır. Ana şema:

1. Üst header.
2. Sol dikey navigasyon.
3. Ortada dört durum kartı.
4. Orta alt bölümde Son Olaylar ve Hızlı İşlemler.
5. Sağda İlişkiler ve Bekleyen Teklifler.
6. En altta F6/Esc kullanım şeridi.

Önce büyük kolonların anchor ve oranlarını kur. Sonra kart içlerini tasarla.
Tek tek öğeleri Canvas üzerinde mutlak koordinatla dizmek yerine Horizontal
Box, Vertical Box, Grid Panel, Size Box ve Spacer kullan. Bu yaklaşım farklı
çözünürlüklerde üst üste binmeyi önler.

## 11. Saydamlık ve katmanlama

Panelin arkasında oyunun hafif görünmesi için yalnız ana arka planlarda alpha
kullan. Metinlerin, ikonların ve butonların alpha değerini düşürme.

Önerilen başlangıç değerleri:

- Ana dış arka plan alpha: `0.88 - 0.94`
- İç kart arka plan alpha: `0.92 - 0.98`
- Dekoratif gölge alpha: `0.25 - 0.45`

Tam referans PNG'sini düşük alpha ile Overlay'e koymak doğru yöntem değildir;
çift metin, çift ikon, bozuk hover ve hizalama hatası oluşturur.

## 12. Sol menüyü ileride değiştirmek

Bildirimler yerine Battle Pass gibi yeni bir bölüm eklemek mümkündür. Mevcut
dört runtime sekmesini koru. Yeni bölüm için ayrı bir Button ve yeni bir
ContentSwitcher sayfası gerekir; bunu eklerken Lua tarafında yeni bir sekme
sözleşmesi de tanımlanmalıdır. Yalnız etiketi değiştirerek mevcut runtime
butonlarından birini başka işleve dönüştürme.

## 13. Kaydetmeden önce kontrol listesi

- Widget Blueprint `Compile` işlemi hatasız mı?
- `ContentSwitcher` sayfa sırası 0, 1, 2, 3 olarak korunuyor mu?
- Runtime widget adları değişmeden duruyor mu?
- Runtime widget'larında `Is Variable` açık mı?
- Dekoratif Image'lar buton tıklamalarını engelliyor mu?
- `PanelInputShield` tüm panel etkileşim alanını kaplıyor mu?
- Küçük çözünürlükte metinler ve kartlar üst üste biniyor mu?
- Hovered, Pressed ve Disabled stilleri ayrı ayrı görünüyor mu?
- Klan adı, rol, üye sayısı ve ilişki verileri sabit yazılmadı mı?

## 14. Runtime test sırası

Manuel tasarım tamamlanıp paketlendikten sonra sırayla şunları doğrula:

1. Sunucuya gir ve snapshot hazır olana kadar bekle.
2. F6 ile paneli aç.
3. Klan adı, rol ve üye sayısının sunucudan geldiğini kontrol et.
4. Dört sekmeyi mouse ile aç.
5. Diplomasi butonlarının enabled/disabled durumlarını kontrol et.
6. Panel gövdesine tıklayınca karakterin saldırmadığını kontrol et.
7. Mouse tekerinin oyun silahını değiştirmediğini kontrol et.
8. Esc, Tab ve F6 kapatma davranışlarını ayrı ayrı dene.
9. Panel açıkken Alt+Tab yapıp oyuna dön.
10. Tekrar F6 aç/kapat testi yap.

Runtime testi yapılmadan tasarımın oyunda çalıştığı kabul edilmez.
