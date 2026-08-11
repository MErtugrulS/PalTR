# Faz-05 runtime dogrulama kaydi

## Dogrulanan

- Offline Saru klanina ait normal yapi, NWO oyuncusundan gelen hasari almadi.
- Engellenen offline-koruma vurusu `guild_combat_activity.tsv` kaydini uzatmadi.
- Oyuncu yeniden baglandiginda NWO snapshot durumu `ONLINE` ve `protected=false` oldu.

## Ertelenen

- Offline korunan klanin base Pal'i dis oyuncudan hasar almamali.
- Offline korunan klanin base Pal'i dis oyuncuyu hedeflememeli veya saldiri aksiyonu almamali.
- Son klan uyesi ayrildiktan sonraki grace suresinde dis hasar alinabilmeli; sure dolunca engellenmeli.
- Son izin verilen dis saldiridan sonra combat-lock suresi dolmadan koruma baslamamali.
- Koruma aktifken engellenen vuruslar combat-lock suresini uzatmamali.
- Klandan biri yeniden baglandiginda koruma aninda kalkmali ve dis hasar tekrar oyun kurallarina birakilmali.

Ertelenen testler uygun ikinci oyuncu ve hedef base Pal olmadigi icin gecmis sayilmadi.

Runtime hizli test ayarlari: offline grace 15 saniye, combat lock 30 saniye.
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
- Hedef olmayan kayitli Klan Bayragi native politikada kapali kalir; yalniz aktif
  hedef ve dogru saldiran klan offline korumayi asabilir.
- Oyun rol enumu `GuildMaster=1`, `SubMaster=2`, `Member=3`, `Guest=4` olarak
  dogrulandi. Lider ve yardimci lider eslemesi config'ten yapilir.

## Runtime'da bekleyenler

Asagidakiler oyun icinde henuz gecmis sayilmadi:

- Fiziksel Klan Bayragi Blueprint sinifinin runtime'da dogrulanmasi ve config'e
  eklenmesi; bos sinif listesi fail-closed kaydi engeller.
- Chat komutlarinin lider/yardimci lider yetkisiyle kayit olusturmasi.
- Native hedef/hedef-disi Klan Bayragi hasar davranisi ve restart persistence.
- Oyunun bu surumunde ayri `COMMANDER` rolu bulunmadigi icin komutan yetkisi.
- `CAPTURE_SPHERE_LEVEL:Ancient_2` secicisini fiziksel item kimligine cevirip
  sandiga/spawn noktasina koyacak dogrulanmis item adapteri.

Baskin saati `raid_utc_offset_minutes` ile hesaplanir. Lua runtime'inda IANA
zaman dilimi veritabani olmadigi icin `Europe/Istanbul` etiketi aciklayicidir;
UTC ofseti yaz/kis saati degisen bolgelerde yonetici tarafindan guncellenmelidir.
