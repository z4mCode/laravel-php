# Degisiklik gunlugu

Bu image'in etiketleri hareketlidir (`:8.4` her yeniden yayinda guncellenir).
Burada yalnizca davranisi etkileyen degisiklikler tutulur; upstream
`php:X-fpm-alpine` ve Alpine guvenlik yamalari haftalik yeniden build ile
sessizce gelir.

Bir deploy'u sabitlemen gerekiyorsa tarihli etiketi kullan: `:8.4-20260812`.

## Yayinlanmamis

### Eklendi
- Proje arthouseweb reposundan ayrilarak kendi reposuna tasindi. Onceden tek bir
  `Dockerfile.base` ve tek PHP surumu vardi.
- PHP 8.3, 8.4 ve 8.5 icin matris build.
- `cli` varyanti: nginx ve supervisor icermez, ayri queue/scheduler
  container'lari icin.
- `linux/arm64` desteklendi (Apple Silicon'da yerel kullanim icin).
- `conf/php.ini` ve `conf/opcache.ini` gercek dosya olarak geldi; onceden
  degerler Dockerfile icinde `echo` ile yaziliyordu.
- `php-fpm-healthcheck`: php-fpm'i HTTP katmani olmadan yoklar.
- `tzdata` eklendi.
- CI duman testi: PHP calisiyor mu, extension'lar yuklu mu, GD'nin
  WebP/JPEG/FreeType destegi var mi, php.ini limitleri uygulanmis mi.
- Haftalik zamanlanmis yeniden build (guvenlik yamalari icin).

### Duzeltildi
- nginx spool dizinleri (`/var/lib/nginx`, `/var/log/nginx`, `/run/nginx`) artik
  `www-data`'ya ait. Alpine'in nginx paketi bunlari `nginx` kullanicisina ait
  olusturuyor, oysa Laravel kurulumlari php-fpm ile ayni kullaniciyi paylasmak
  icin nginx.conf'ta `user www-data;` kullaniyor. Sonuc: worker istek govdesini
  diske yazamiyor ve dosya yuklemeleri 500 donuyordu.

      [crit] open() "/var/lib/nginx/tmp/client_body/0000000001" failed
             (13: Permission denied)

  nginx kucuk govdeleri bellekte tuttugu icin hata yalnizca birkac yuz KB'i asan
  yuklemelerde ortaya cikiyordu; kucuk istekler sorunsuz geciyordu. CI artik hem
  dizin sahipligini hem de www-data'nin yazabildigini dogruluyor.

### Degisti
- `mlocati/php-extension-installer` `:latest` yerine `:2` major etiketine
  sabitlendi.
- Extension listesine `sockets` ve `igbinary` eklendi. Ikisi de varliklariyla
  davranis degistirmez: `sockets` Reverb/websocket ihtiyaci dogdugunda hazir
  olsun diye, `igbinary` phpredis'in kompakt serilestiriciyi kullanabilmesi
  icin (acmak icin `redis.serializer` ayarlanmali).

### Notlar
- `ghcr.io/z4mcode/laravel-php:8.4` etiketi korundu; arthouseweb ve inncontrol
  icin `FROM` satirinda degisiklik gerekmiyor. Eklenen iki extension geriye
  donuk uyumlu.

## Oncesi (arthouseweb icinde)

- 2026-08-11 — Base image yaklasimi devreye alindi. Extension'lar her deploy'da
  derlenmek yerine onceden derlenmis image'dan geliyor. arthouseweb deploy
  suresi 9 dk 17 sn'den 1 dk 52 sn'ye indi.
- 2026-08-11 — Ayni image inncontrol tarafindan da kullanilmaya baslandi;
  `arthouse-php` adi `laravel-php` olarak degistirildi.
- 2026-08-11 — `gd`'nin WebP destegi kazanildi. Onceki elle yazilmis
  `docker-php-ext-configure gd --with-freetype --with-jpeg` satirinda
  `--with-webp` yoktu ve galeri gorsel yuklemeleri uretimde
  `Call to undefined function imagewebp()` ile patliyordu.
