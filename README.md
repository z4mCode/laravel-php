# laravel-php

Laravel projeleri icin paylasilan PHP base image.

```
ghcr.io/z4mcode/laravel-php:8.4
```

## Neden var

PHP extension'lari kaynak koddan derlenir. Tipik bir Laravel extension seti
(`redis`, `gd`, `intl`, `soap`, `pdo_mysql`, `opcache`, …) her deploy'da yeniden
derlendiginde **5-6 dakika** surer. Oysa bu liste ayda bir bile degismez.

Bu image extension'lari onceden derlenmis olarak tasir. Uygulama Dockerfile'i
`FROM` ile bunu alir, derleme adimi tamamen ortadan kalkar.

Olculen etki (arthouseweb, 2026-08-11):

| Adim | Once | Sonra |
|---|---|---|
| PHP extension derleme | 371 sn | **0 sn** |
| Toplam deploy | 9 dk 17 sn | **1 dk 52 sn** |

Yan kazanc: extension listesi tek yerde tanimli oldugu icin projeler arasinda
surunme olmuyor, ve `gd`'nin WebP destegi gibi kolayca gozden kacan derleme
bayraklari her yerde ayni.

## Kullanan projeler

- `z4mCode/arthouseweb`
- `z4Soft/inncontrol`

Extension listesini degistirirken her ikisinin ihtiyacini birlikte gozet.

---

## Etiketler

| Etiket | Icerik |
|---|---|
| `8.4` | PHP 8.4, fpm-nginx varyanti (varsayilan) |
| `8.4-fpm-nginx` | Yukaridakinin acik yazilmis hali |
| `8.4-cli` | PHP 8.4, cli varyanti |
| `8.4-20260812` | Tarihli, degismez etiket — pinlemek icin |
| `latest`, `latest-cli` | Varsayilan PHP surumu (su an 8.4) |

Desteklenen PHP surumleri: **8.3**, **8.4**, **8.5**.
Mimariler: **linux/amd64**, **linux/arm64**.

> arm64, GitHub'in amd64 runner'inda QEMU emulasyonuyla kurulur ve extension
> derlemesi orada belirgin sekilde yavastir. Uretim sunucusu x86_64; arm64
> yalnizca Apple Silicon'da yerel kullanim icin yayinlaniyor. CI maliyeti sorun
> olursa `workflow_dispatch` uzerinden yalnizca `linux/amd64` secilebilir ya da
> `build.yml` icindeki `DEFAULT_PLATFORMS` daraltilabilir. Uzun vadeli alternatif
> native arm64 runner'lara gecip manifest'leri birlestirmektir.

Uretimde sade etiket (`:8.4`) yeterli — haftalik yeniden build guvenlik
yamalarini otomatik getirir. Bir deploy'u tam olarak sabitlemen gerekiyorsa
tarihli etiketi kullan.

## Varyantlar

**`fpm-nginx`** — varsayilan. php-fpm, nginx ve supervisor binary'lerini icerir.
Tek container'da web sunucusu + PHP + queue worker calistiran kurulumlar icin.
Konfigurasyon dosyalari (nginx.conf, supervisord.conf) image'da **yok**; onlari
uygulama repon saglar.

**`cli`** — nginx ve supervisor yok. Queue worker, scheduler ve artisan islerini
ayri container'da calistiran kurulumlar icin. Daha kucuk.

## Icindekiler

**PHP extension'lari**

| Extension | Neden |
|---|---|
| `redis` | cache, session, queue surucusu (phpredis) |
| `igbinary` | phpredis icin kompakt serilestirici — varligi tek basina davranisi degistirmez |
| `gd` | gorsel isleme |
| `pdo_mysql` | MySQL / MariaDB |
| `pdo_sqlite` | testler, kucuk yerel depolar |
| `zip` | composer, yedek alma/geri yukleme |
| `bcmath` | para ve hassas sayi hesaplari |
| `intl` | yerellestirme, Carbon, para birimi bicimleme |
| `soap` | kargo/odeme entegrasyonlari |
| `exif` | yuklenen gorsellerin yonelimi |
| `opcache` | uretim performansi |
| `pcntl` | queue worker'larda sinyal isleyisi (graceful shutdown) |
| `sockets` | Reverb/websocket ve bazi queue surucileri |

`gd` tam format destegiyle derlenir: WebP, AVIF, JPEG, PNG, FreeType, XPM.
`install-php-extensions` bu bayraklari kendisi ayarlar — elle yazilan
`docker-php-ext-configure gd --with-freetype --with-jpeg` satirinda `--with-webp`
unutmak mumkun ve bu tam olarak bir kez basimiza geldi. CI her build'de dogrular;
bir upstream degisikligi WebP'yi dusurse build kirmizi olur.

**Bilerek disarida birakilanlar**

| Extension | Neden |
|---|---|
| `xdebug`, `pcov` | yalnizca gelistirme/test; uretim image'ini yavaslatir |
| `imagick` | `gd` yeterli oldugu surece gereksiz agirlik |
| `pdo_pgsql` | su an hicbir proje Postgres kullanmiyor |

Uygulama kendi Dockerfile'inda ekleyebilir:

```dockerfile
RUN install-php-extensions pdo_pgsql
```

**Araclar**: composer 2, curl, git, unzip, fcgi (`cgi-fcgi`), tzdata

`composer` ve `php-extension-installer` major surume sabitli (`:2`). `:latest`
kullanmak, kod degismeden yapilan haftalik yeniden build'lerde beklenmedik
davranis degisikligi getirebilirdi.

**Konfigurasyon**: `conf/php.ini` ve `conf/opcache.ini`, image icinde
`/usr/local/etc/php/conf.d/zz-*.ini` olarak

**Icermeyenler**: uygulama kodu, `.env`, nginx.conf, supervisord.conf, vendor/

---

## Kullanim

Uygulama Dockerfile'inda ikinci asama olarak:

```dockerfile
# Stage 1 — asset ve bagimlilik derlemesi
FROM php:8.4-fpm-alpine AS build
RUN apk add --no-cache git unzip nodejs npm
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
WORKDIR /app

COPY composer.json composer.lock ./
RUN --mount=type=cache,target=/tmp/composer-cache \
    COMPOSER_CACHE_DIR=/tmp/composer-cache \
    composer install --no-dev --no-interaction --no-scripts --no-autoloader --ignore-platform-reqs

COPY package*.json ./
RUN --mount=type=cache,target=/root/.npm npm ci

COPY . .
RUN composer dump-autoload --optimize --no-dev --ignore-platform-reqs \
    && npm run build \
    && rm -rf node_modules

# Stage 2 — calisma zamani
FROM ghcr.io/z4mcode/laravel-php:8.4

WORKDIR /var/www/html

COPY docker/nginx.conf /etc/nginx/nginx.conf
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

COPY --from=build /app /var/www/html

EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost/up || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
```

Build stage neden `php:8.4-fpm-alpine`'dan basliyor: o asama yalnizca composer
ve npm calistirir, extension'a ihtiyaci yoktur. `--ignore-platform-reqs` ile
composer'in extension kontrolu atlanir. Extension'lari orada da derlemek bosuna
zaman harcar.

`rm -rf node_modules` onemli: `.dockerignore` build context'ten eler ama
`npm ci` build stage icinde yeniden yaratir ve `COPY --from=build` hepsini
production image'a tasir.

### Ayri queue container'i

```dockerfile
FROM ghcr.io/z4mcode/laravel-php:8.4-cli
WORKDIR /var/www/html
COPY --from=build /app /var/www/html
CMD ["php", "artisan", "queue:work", "--tries=3"]
```

`fpm-nginx` ve `cli` ayni base katmanlari paylastigi icin ikinci image'in
registry maliyeti dusuktur.

### Varsayilanlari ezmek

`conf.d` alfabetik yuklenir ve bu image'in dosyalari `zz-` onekli. Sonra
gelmesi icin daha ileri bir isim kullan:

```dockerfile
RUN printf 'memory_limit=1G\nopcache.validate_timestamps=0\n' \
    > /usr/local/etc/php/conf.d/zzz-app.ini
```

---

## Gelistirme

```bash
make build              # PHP=8.4 VARIANT=fpm-nginx
make test               # extension, GD, php.ini dogrulamasi
make build PHP=8.5 VARIANT=cli
make all-versions       # 8.3 / 8.4 / 8.5
make shell              # image icinde kabuk
```

Varsayilan platform `linux/amd64` — uretim sunucusu x86_64 oldugu icin Apple
Silicon'da bile uretimle ayni mimari kurulur.

## Yayinlama

CI (`.github/workflows/build.yml`) yayinlar. Uc tetikleyici:

- **push** — `Dockerfile`, `conf/` ya da `bin/` degistiginde
- **schedule** — her pazartesi 04:00 UTC; upstream `php:X-fpm-alpine` ve Alpine
  guvenlik yamalarini kod degismeden alir
- **workflow_dispatch** — elle; istege bagli tek bir PHP surumu secilebilir

Her matris girdisi push'tan sonra duman testinden gecer: PHP calisiyor mu,
beklenen extension'lar yuklu mu, GD'nin WebP/JPEG/FreeType destegi var mi,
`php.ini` limitleri uygulanmis mi, composer/nginx/supervisord calisiyor mu.
Herhangi biri basarisizsa is kirmizi olur.

`fail-fast: false` — bir surum patlarsa digerleri yayinlanmaya devam eder.

---

## Bakim

### Extension eklemek

`Dockerfile` icindeki `PHP_EXTENSIONS` varsayilanini duzenle, push et. CI tum
surumleri yeniden yayinlar. Uygulama repolarinda yapilacak bir sey yok — sonraki
deploy guncel image'i ceker.

Duman testine de ekle (`.github/workflows/build.yml` icindeki `$required`
dizisi), yoksa eksikligi fark edilmez.

### PHP surumu eklemek/cikarmak

`build.yml` icindeki `matrix.php` listesini duzenle. Varsayilan surumu
degistiriyorsan `env.DEFAULT_PHP` degerini de guncelle — `latest` etiketi ona
bagli.

### Uygulamalari yeni bir PHP surumune tasimak

1. Base image o surum icin yayinlanmis olmali (CI'da yesil)
2. Uygulama Dockerfile'inda `FROM …:8.5` yap
3. Uygulamanin `composer.json` icindeki `require.php` ve `config.platform.php`
   degerlerini gozden gecir

---

## Bilinmesi gerekenler

**Etiket degisikligi ile uygulama degisikligi ayri commit'lerde push edilmeli.**
Base image registry'e dusmeden uygulama deploy'u tetiklenirse `FROM` adimi
`401 Unauthorized` ya da manifest bulunamadi hatasi verir.

**GHCR paket gorunurlugu repository gorunurlugunden bagimsizdir** ve ayri bir
sayfadan yonetilir: `github.com/<kullanici>?tab=packages` → paket → Package
settings → Danger Zone. Repo private kalirken image public olabilir.

**Organization hesaplarinda ek kilit var.** Org yoneticisi ayari public
paketleri engelliyorsa "Public" secenegi gri gorunur ve
`github.com/organizations/<org>/settings/packages` altindan acilmasi gerekir.
Aksi halde Coolify build'i su hatayi verir:

```
failed to fetch anonymous token: ... 401 Unauthorized
```

**Yeni olusturulan her GHCR paketi private dogar.** Ilk yayindan sonra
gorunurlugu ayarlamayi unutma. Anonim erisimi dogrulamak icin:

```bash
curl -s -o /dev/null -w "%{http_code}\n" \
  "https://ghcr.io/token?scope=repository%3Az4mcode%2Flaravel-php%3Apull&service=ghcr.io"
```

`200` = public. `401` = hala private.

**Resmi `php` image'i hicbir `php.ini` aktive etmez.** Bu image `conf/php.ini`
ile bu boslugu doldurur. Base image kullanmadan calisan bir kurulumda PHP'nin
dahili varsayilanlari gecerli olur: `upload_max_filesize=2M`,
`post_max_size=8M`, `memory_limit=128M`. nginx `client_max_body_size 100M`
derken PHP 2M'de kesiyorsa yuklemeler sessizce basarisiz olur.

**Uretim sunucusunun mimarisini dogrula.** Bu image amd64 ve arm64 yayinlar,
ama yerelde elle build ederken Apple Silicon varsayilan olarak arm64 uretir.
`make` hedefleri bu yuzden `linux/amd64` zorluyor.
