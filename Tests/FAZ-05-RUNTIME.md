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

## Fetih runtime engelleri

Asagidakiler dogrulanmis Palworld/UE sozlesmesi bulunmadan uygulanmadi ve
runtime'da gecmis sayilmadi:

- Bayrak ve kusatma kampi icin dogrulanmis world class, spawn, sahiplik,
  referans ve yok edilme adapteri.
- Bayrak hasarini merkezi fetih politikasina baglayacak dogrulanmis native hook.
- `LEADER`, `DEPUTY_LEADER` ve `COMMANDER` rollerini mevcut oyun rol verisinden
  hatasiz esleyecek adapter.
- `CAPTURE_SPHERE_LEVEL:Ancient_2` secicisini fiziksel item kimligine cevirip
  sandiga/spawn noktasina koyacak dogrulanmis item adapteri.
- Bayrak bolgesindeki offline-koruma istisnasini native hasar akimina baglayan
  world-object eslemesi.

Baskin saati `raid_utc_offset_minutes` ile hesaplanir. Lua runtime'inda IANA
zaman dilimi veritabani olmadigi icin `Europe/Istanbul` etiketi aciklayicidir;
UTC ofseti yaz/kis saati degisen bolgelerde yonetici tarafindan guncellenmelidir.
