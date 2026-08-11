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
Uretim ayarlari: offline grace 5 dakika, combat lock 20 dakika.
