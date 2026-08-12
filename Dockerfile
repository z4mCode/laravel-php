# syntax=docker/dockerfile:1

# Paylasilan Laravel PHP base image.
#
# Uygulama kodu, nginx/supervisor konfigurasyonu ve .env BURADA YOKTUR — bunlar
# uygulama repolarinda kalir. Bu image yalnizca calisma zamani saglar:
# PHP + extension'lar + opinionated php.ini + composer, ve fpm-nginx varyantinda
# nginx ile supervisor binary'leri.
#
# Iki varyant (build target):
#   fpm-nginx  Tek container'da nginx + php-fpm calistiran uygulamalar icin.
#              Varsayilan varyant; :8.4 gibi sade etiketler bunu isaret eder.
#   cli        Queue worker, scheduler ve artisan islerini ayri container'da
#              calistiran kurulumlar icin. nginx/supervisor icermez, daha kucuktur.
#
# Elle build:
#   docker build --platform linux/amd64 --target fpm-nginx \
#     --build-arg PHP_VERSION=8.4 -t ghcr.io/z4mcode/laravel-php:8.4 .

ARG PHP_VERSION=8.4


# ---------------------------------------------------------------------------
# base — her iki varyantin ortak katmani
# ---------------------------------------------------------------------------
FROM php:${PHP_VERSION}-fpm-alpine AS base

# install-php-extensions extension'larin derleme bagimliliklarini kurar, derler
# ve build paketlerini temizler. Elle $PHPIZE_DEPS + apk del yapmaya gerek yok.
# Ikisi de major surume sabitlendi. :latest kullanmak, kod degismeden yapilan
# haftalik yeniden build'lerde beklenmedik davranis degisikligi getirebilirdi.
COPY --from=mlocati/php-extension-installer:2 /usr/bin/install-php-extensions /usr/local/bin/
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# curl  : healthcheck
# git   : composer'in VCS kaynaklarini cekmesi
# unzip : composer dist paketleri
# fcgi  : cgi-fcgi, php-fpm healthcheck'i icin
# tzdata: konteynerde dogru saat dilimi (Europe/Istanbul vb.)
RUN apk add --no-cache curl git unzip fcgi tzdata

# Extension listesi tek yerden yonetilir. Yeni bir extension gerektiginde bu
# varsayilani degistir ve image'i yeniden yayinla; uygulama repolarinda islem yok.
#
# Listede olanlar ve gerekceleri:
#   redis      cache, session, queue surucusu (phpredis; REDIS_CLIENT=phpredis)
#   igbinary   phpredis'in daha kompakt serilestiricisi. Yalnizca extension'in
#              varligi davranisi degistirmez; opsiyonel olarak acilir.
#   gd         gorsel isleme. WebP/AVIF/JPEG/FreeType destegi install-php-extensions
#              tarafindan otomatik acilir — elle --with-webp unutulma riski yok.
#   pdo_mysql  MySQL/MariaDB
#   pdo_sqlite testler ve kucuk yerel depolar
#   zip        composer, yedek alma/geri yukleme
#   bcmath     para ve hassas sayi hesaplari
#   intl       yerellestirme, Carbon, para birimi bicimleme
#   soap       kargo/odeme entegrasyonlari
#   exif       yuklenen gorsellerin yonelimi
#   opcache    uretim performansi
#   pcntl      queue worker'larin sinyal isleyisi (graceful shutdown)
#   sockets    Reverb/websocket ve bazi queue surucileri
#
# Bilerek disarida birakilanlar:
#   xdebug, pcov  yalnizca gelistirme/test; uretim image'ini yavaslatir
#   imagick       gd yeterli oldugu surece gereksiz agirlik
#   pdo_pgsql     su an hicbir proje Postgres kullanmiyor
# Gerekirse uygulama kendi Dockerfile'inda ekleyebilir:
#   RUN install-php-extensions pdo_pgsql
ARG PHP_EXTENSIONS="redis igbinary gd pdo_mysql pdo_sqlite zip bcmath intl soap exif opcache pcntl sockets"
RUN install-php-extensions ${PHP_EXTENSIONS}

# conf.d alfabetik yuklenir; zz- oneki bu dosyalarin en son okunmasini ve
# onceki tanimlari ezmesini saglar. Uygulama kendi conf.d dosyasini ekleyerek
# bu degerleri gecersiz kilabilir.
COPY conf/php.ini /usr/local/etc/php/conf.d/zz-laravel.ini
COPY conf/opcache.ini /usr/local/etc/php/conf.d/zz-opcache.ini

# php-fpm'i HTTP katmani olmadan yoklamak icin. Tek container kurulumlarinda
# genelde nginx uzerinden /up yoklanir; ayri fpm container'i calistiranlar
# HEALTHCHECK olarak bunu kullanabilir.
COPY bin/php-fpm-healthcheck /usr/local/bin/php-fpm-healthcheck
RUN chmod +x /usr/local/bin/php-fpm-healthcheck

WORKDIR /var/www/html


# ---------------------------------------------------------------------------
# cli — queue worker / scheduler / artisan container'lari
# ---------------------------------------------------------------------------
FROM base AS cli

CMD ["php", "-v"]


# ---------------------------------------------------------------------------
# fpm-nginx — varsayilan varyant
# ---------------------------------------------------------------------------
FROM base AS fpm-nginx

RUN apk add --no-cache nginx supervisor

# Alpine'in nginx paketi /var/lib/nginx dizinini `nginx` kullanicisina ait
# olusturur. Laravel kurulumlari php-fpm ile ayni kullaniciyi paylasmak icin
# nginx.conf'ta `user www-data;` kullanir; bu durumda worker'lar istek govdesini
# spool dizinine yazamaz:
#
#   [crit] open() "/var/lib/nginx/tmp/client_body/0000000001" failed
#          (13: Permission denied)
#   POST /livewire/upload-file -> 500
#
# Sinsi tarafi: nginx kucuk govdeleri client_body_buffer_size kadar bellekte
# tutar, diske hic yazmaz. Bu yuzden kucuk istekler sorunsuz gecer ve hata
# yalnizca birkac yuz KB'i asan dosya yuklemelerinde ortaya cikar.
RUN mkdir -p /var/lib/nginx/tmp /var/log/nginx /run/nginx \
    && chown -R www-data:www-data /var/lib/nginx /var/log/nginx /run/nginx

# supervisorctl konfigurasyonu /etc/supervisor/conf.d/ altinda aramaz; uygulama
# repolari config'i oraya kopyaladigi icin symlink'i burada hazir tutuyoruz.
RUN mkdir -p /etc/supervisor/conf.d \
    && ln -sf /etc/supervisor/conf.d/supervisord.conf /etc/supervisord.conf

EXPOSE 80

CMD ["php-fpm"]
