# Faz-05 runtime dogrulama kaydi

## Dogrulanan

- Online ve tarafsiz iki klan arasinda Pal Kutusu alani disindaki normal yapi
  hasari vanilla oyun kurallarina birakildi ve hedef yapi hasar aldi.
- Son klan uyesi ayrildiktan sonraki grace suresinde dis hasar alinabildi;
  offline koruma aktif olduktan sonra ayni yapi hasar almadi.
- Engellenen offline-koruma vurusu `guild_combat_activity.tsv` kaydini uzatmadi.
- Oyuncu yeniden baglandiginda snapshot durumu `ONLINE` ve `protected=false`
  oldu; dis yapi hasari tekrar oyun kurallarina birakildi.
- Online ve tarafsiz durumda us Pal'i dis oyuncuyu hedefledi; Pal ile oyuncu
  birbirlerine hasar verebildi.
- Offline koruma aktifken dis oyuncunun us Pal'ina verdigi hasar native hook'ta
  `OFFLINE_PROTECTION` gerekcesiyle engellendi. Runtime logunda saldiran NWO ve
  hedef Exceed klan GUID'leri dogru cozuldu.
- Offline korunan us Pal'inin bolge savunmasi dis oyuncuyu hedeflemeye ve ona
  hasar vermeye devam etti. Bu tek yonlu davranis bilincli oyun kurali olarak
  kabul edildi: Pal korunur, ancak base savunmasi pasiflestirilmez.
- Combat-lock ayri runtime penceresinde dogrulandi: grace bittikten sonra koruma
  baslamadan once yapi hasar aldi; bu izin verilen vurus `last_hostile_at`
  zamanini ve koruma baslangicini ileri tasidi. Son vurusun combat-lock suresi
  doldugunda snapshot `OFFLINE_PROTECTED` oldu ve ayni yapi hasar almadi.

Runtime combat-lock testi: offline grace 15 saniye, combat lock 60 saniye.
Uretim ayarlari: offline grace 10 dakika, combat lock 20 dakika.

## Fetih domain dogrulamasi

Saf Lua testlerinde asagidaki kurallar dogrulandi:

- Baskent, karakol ve normalize baglanti grafigi persistence sonrasi geri yukleniyor.
- Klan basina yeni karakol limiti, baglanti mesafesi, fetih alani,
  kusatma kampi mesafeleri, baskin penceresi, isgal suresi ve rol izinleri
  merkezi config uzerinden degistirilebiliyor.
- Aktif hedef keyfi degistirilemiyor; ilk hedef kusatma kampindan, sonraki
  hedefler ele gecirilmis sinir grafiginden aciliyor.
- Ateskes isgali duraklatiyor; ateskes bozulduktan sonra ayarlanabilir yeniden
  silahlanma suresi dolmadan fetih hasari ve isgal sayaci acilmiyor.
- Karsi saldiri, geri alma, barista isgalcinin kazanmasi ve baskent yenilgisi
  state-machine testlerinde dogrulandi.
- Baskent yenilgisi savunucunun kontrol ettigi dugumleri devrediyor ve kaybeden
  klanin yeni baskentle sifirdan baslamasina izin veriyor.
- Ganimet secimi ayarlanabilir agirlikli tablodan tek en degerli Pal topu
  secicisi uretiyor.
- Karsi saldiri artik anlik domain komutu degildir. Eski sahip isgal noktasina
  kendi fiziksel Klan Bayragi'ni kurar; ayarlanabilir koruma suresi dolarsa
  karakol `RESTORED` olur. Bayrak once yikilirsa isgal devam eder.
- Karsi saldiri ve isgal sureleri ayri tutulur, ateskeste ikisi de donar ve
  restart sonrasi fiziksel bayrak referansi ile birlikte geri yuklenir.

## Fetih world entegrasyonu

UHT dump ve mevcut native hook sozlesmesiyle statik olarak dogrulananlar:

- Pal Kutusu vanilla us olarak kalir ve fetih node limitine dahil edilmez.
- Klan Bayragi adapteri dogrulanmis `PalBuildObject` kimlik, klan ve konum
  getter'larini kullanir; fiziksel sinif token'i config'ten gelir.
- Varsayilan fiziksel kusatma kampi gercek runtime kaydinda gorulen
  `BP_BuildObject_WorkBench_C` yapisidir; izinli sinif listesi config'tedir.
- `!fetih KLAN` kampanyayi, `!kusatmakampi KLAN` yakindaki klana ait tezgahi
  ve en yakin gecerli dusman karakolunu kaydeder.
- Lua aktif hedefleri `conquest_damage_policy.tsv` snapshot'ina yazar; mevcut
  native map-object hasar hook'u bu sozlesmeyi tuketir.
- Lua aktif hedef bolgesini `conquest_zone_policy.tsv` snapshot'ina Unreal
  dunya birimleriyle yazar. Native taraf hedef yapinin UHT dump'ta dogrulanmis
  `UPalMapObjectModel.InitialTransformCache` konumunu kullanir. Istisna yalniz
  hedef node'un mevcut sahibi, resmi saldiran klan ve ayarlanmis yaricap ayni
  anda eslesirse uygulanir; yanlis klan ve bolge disi fail-closed kalir.
- Hedef olmayan kayitli Klan Bayragi native politikada kapali kalir; yalniz aktif
  hedef ve dogru saldiran klan offline korumayi asabilir.
- Oyun rol enumu `GuildMaster=1`, `SubMaster=2`, `Member=3`, `Guest=4` olarak
  dogrulandi. Lider ve yardimci lider eslemesi config'ten yapilir.

## Siyasi bolge ve harita sozlesmesi

- Baskent ve karakol siyasi sinirlari fetih hasar yaricapindan ayridir. Ilk
  surum yatay duzlemde dairesel alan kullanir; varsayilan baskent 250 metre,
  karakol 150 metredir ve config'ten degistirilebilir.
- Her node `display_name` ve `territory_radius_meters` alani tasir. Eski kayitlar
  geriye uyumlu okunur; bos ad otomatik olarak `Klan Baskenti` veya
  `Klan N. Karakolu`, sifir yaricap node tipinin varsayilani olur.
- Yetkili klan rolu kendi kayitli fiziksel bayraginin yaninda
  `!bolgeadi AD` ve `!bolgesinir METRE` komutlarini kullanabilir. Uzak node veya
  baska klanin kontrolundeki node degistirilemez.
- Sunucu `territory_snapshot.tsv` dosyasina node kimligi, gorunen ad, tip,
  mevcut kontrolcu, metre cinsinden merkez/yaricap, fetih ve bayrak durumunu
  deterministik sirada yazar. Harita arayuzu bu sozlesmeyi tuketecek; bu commit
  oyun haritasi cizimi veya client UI degisikligi yapmaz.
- Oyuncu konumu mevcut dogrulanmis `K2_GetActorLocation` akisi ile 5 saniyelik
  scheduler'da okunur. Yeni bolgeye giriste mevcut `SendSystemAnnounce`
  sozlesmesiyle tek bildirim gonderilir. Ayni bolgede beklemek tekrar bildirim
  uretmez; 20 metrelik ayarlanabilir cikis toleransi sinir titresimini onler.
- Cakisan alanlarda merkeze olan mesafenin yaricapa orani en kucuk node
  secilir. Bayragi gecici olarak kayip node siyasi haritadan silinmez ve fetih
  sonrasi ad/snapshot mevcut kontrolcu klana gore guncellenir.

## Fetih runtime dogrulamasi

- Ayakli tabela `BP_BuildObject_Signboard_C` gecici fiziksel Klan Bayragi olarak
  runtime'da dogrulandi. Mevcut persistence referanslari korunur, ancak yeni
  kayitlar icin config'ten kaldirildi.
- Yerel `Pal-WindowsServer.pak` indeksinde Believer, DarkIsland, FireCult,
  Hunter, Ninja, Police, Scientist ve SkyIsland direkli `BP_BuildObject_*_Flag`
  Blueprintleri dogrulandi. Yeni baskent, karakol, yeniden baglama ve karsi
  saldiri kayitlari yalniz bu gercek direkli bayrak siniflarini kabul eder;
  dikey banner ve yan dekorlar stratejik node sayilmaz.
- NWO ve Exceed klanlari icin baskent/karakol chat komutlariyla kaydedildi;
  kayitlar sunucu yeniden baslatmasindan sonra korundu.
- Savas ilani, hazirlik suresi, fetih kampanyasi, kusatma kampi ve ilk hedef
  secimi iki klanla oyun icinde dogrulandi.
- Aktif Exceed karakolu native politikada hasar aldi. Ayni anda henuz cepheyle
  acilmamis Exceed baskenti hasar almadi.
- Ilk karakol ele gecirildikten sonra baskent cephe hedefi olarak acildi ve
  native politikada hasar almaya basladi.
- Test ekipmani bulunmadigi icin karakol ve baskentin tamamen yikilmasi fiziksel
  vurusla tamamlanmadi. `FLAG_DISPOSED` girdileri acik kullanici onayi ile runtime
  TSV'sine enjekte edilerek state gecisleri ayri olarak dogrulandi; bu sonuc
  fiziksel dispose hook'unun runtime dogrulamasi sayilmaz.
- Simule edilen karakol dususu isgal, bekleme, fetih, ganimet kaydi ve cephe
  ilerlemesini olusturdu.
- Simule edilen baskent dususu savunucunun dugumlerini NWO'ya devretti, eski
  baskenti karakola dusurdu ve NWO-Exceed savasini tarafsiz iliskiyle sonlandirdi.

## Runtime'da bekleyenler

Asagidakiler oyun icinde henuz gecmis sayilmadi:

- Son server saglamlik commitleri kurulduktan sonraki ilk temiz baslangicta
  `BASLATMA_HATASI` gorulmemesi; mevcut registry, diplomasi, fetih ve bolge TSV
  dosyalarinin yeni baslik dogrulamasindan gecmesi ve health durumunun `STARTED`
  olmasi. Bu paket henuz oyun klasorune kurulmadigi icin onceki runtime sonucu
  yeni commitleri kapsamiyor.
- Temiz baslangictan sonra bir `!durum` ve bir fetih durum komutunun cevap
  vermesi; logda `KOMUT_RESPONSE_WRITE_FAILED` veya
  `FAZ05_EVENT_WRITE_FAILED` bulunmamasi. Salt-okunur/disk-dolu hata senaryolari
  otomatik testte kapsanir, canli veri klasorunde elle hata uretilmeyecek.
- Varsayilan `enable_damage_audit=false` ayariyla tarafsiz oyuncu PvP'sinde
  `passive_damage_events.tsv` dosyasinin her vurusla buyumemesi ve konsolda
  `Oyuncu hasarina izin verildi` spam'i olusmamasi. Ayni pakette ittifakli
  oyuncu hasarinin halen engellenmesi; tekrarlanan engel logunun en fazla bes
  saniyede bir gorunmesi.
- Diplomasi veya offline koruma snapshot'i normal oyun akisi ile degistiginde
  native politikanin yaklasik bir saniye icinde yeni durumu almasi. Snapshot
  degisimi sirasinda `guard failing open` mesaji gorulmemeli; gecici okuma
  yarisi olursa son gecerli politika korunmali ve sonraki yenileme basarili
  olmali. Canli TSV dosyalari elle bozulmayacak veya silinmeyecek.
- Normal calisma ve temiz yeniden baslatma sonrasinda veri klasorunde kalici
  `.next`/`.backup` dosyasi bulunmamasi. Bir onceki kesintiden kalirsa server
  hedef TSV'yi otomatik toparlamali; bu kontrol icin calisan sunucunun veri
  dosyalari elle degistirilmeyecek.
- Gercek direkli faction bayraklarindan birini kurup `!bayrakaday` ile sinif,
  model kimligi, klan sahipligi ve konum cozumunun runtime dogrulanmasi; ardindan
  ayni bayrakla baskent/karakol, yeniden baglama ve karsi saldiri kaydi.
- Gercek fiziksel tabela tamamen yikildiginda native hook'un `FLAG_DISPOSED`
  olayi uretmesi; karakol ve baskent icin ayri ayri denenmeli.
- Fethedilen dugumlere yeni fetheden-klan tabelasi kurup `!fetihbayragi` ile
  yeniden baglama; `BayrakBekleyen` sayacinin sifira inmesi ve sonraki cephenin
  ancak baglamadan sonra acilmasi.
- Devredilen eski dusman tabelasi sahada kalirsa fetheden klanin onu temizleme
  izninin yeni tabela baglandiktan sonra da korunmasi.
- Ateskes, ateskes bozma, yeniden silahlanma, karsi saldiri ve geri alma
  dongulerinin iki oyuncuyla runtime dogrulamasi.
- Savunucu klan offline korumadayken resmi saldiranin aktif hedef bolgesi
  icindeki normal yapilara hasar verebilmesi; ayni node yaricapi disindaki,
  baska node yakinindaki ve yanlis klanin vurdugu yapilarin korunmaya devam
  etmesi.
- Karsi saldiri koruma suresi baskin penceresinin kalanina tam sigiyorsa
  baslatilabilmeli; kapanisa kalan sure daha kisaysa komut
  `COUNTER_HOLD_EXCEEDS_RAID_WINDOW` nedeniyle reddedilmeli.
- Ganimet kaydinin gercek fiziksel sandik veya teslim adapteriyle oyuncuya
  verilmesi; su anda yalniz domain/persistence kaydi vardir.
- Oyunun bu surumunde ayri `COMMANDER` rolu bulunmadigi icin komutan yetkisi.
- PAK'ta statik kimligi `PalSphere_Ancient_2` olarak dogrulandi; bunu fiziksel
  sandiga/spawn noktasina koyacak guvenli global item adapteri bulunmadi.
- Baskent ve karakol sinirina giriste bildirimin oyun ustunde yalniz bir kez
  gorunmesi; sinirda ileri-geri hareketin spam yapmamasi, cikis/yeniden giriste
  bildirimin tekrar gelmesi ve iki alan cakismasinda dogru bolgenin secilmesi.
- `!bolgeadi NWO Kuzey 3 Karakolu` ve `!bolgesinir 175` komutlarinin yalniz
  yetkili rol ve yakindaki klana ait kayitli bayrakta calismasi; member, uzak
  bayrak ve baska klan bayragi denemelerinin reddedilmesi.
- `territory_snapshot.tsv` kaydinin runtime koordinatlari, adlari, yaricaplari ve
  fetih sonrasi yeni kontrolcuyu dogru yansitmasi. Snapshot'in oyun haritasinda
  marker ve dairesel alan olarak gosterilmesi ayri client UI entegrasyonudur.

Ganimet world entegrasyonu icin UHT dump yeniden tarandi. Oyuncu network
component'inde dogrudan envantere ekleme RPC'si bulunuyor, ancak ganimetin cebe
otomatik verilmemesi kuralina aykiri. World drop fonksiyonlari ise incident,
status veya cheat-manager nesnelerine bagli; bagimsiz ve guvenli bir server
spawn sozlesmesi vermiyor. Bu nedenle dogrulanmamis nesne olusturma veya ozel
fonksiyon cagrisi eklenmedi.

Baskin saati `raid_utc_offset_minutes` ile hesaplanir. Lua runtime'inda IANA
zaman dilimi veritabani olmadigi icin `Europe/Istanbul` etiketi aciklayicidir;
UTC ofseti yaz/kis saati degisen bolgelerde yonetici tarafindan guncellenmelidir.
