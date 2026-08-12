# Yerel build ve dogrulama kisayollari.
#
# Uretim image'lari CI'da yayinlanir; buradaki hedefler degisikligi push
# etmeden once denemek icindir.

PHP     ?= 8.4
VARIANT ?= fpm-nginx
IMAGE   ?= laravel-php-local
# Coolify sunucusu x86_64. Apple Silicon'da yereldeki varsayilan arm64 olurdu,
# bu yuzden uretimle ayni mimariyi zorluyoruz.
PLATFORM ?= linux/amd64

TAG := $(IMAGE):$(PHP)-$(VARIANT)

.PHONY: help build test shell sizes clean all-versions

help:
	@echo "make build            PHP=$(PHP) VARIANT=$(VARIANT) icin image kur"
	@echo "make test             Kurulan image'i dogrula (extension, GD, ini)"
	@echo "make shell            Image icinde kabuk ac"
	@echo "make sizes            Yerel image boyutlarini listele"
	@echo "make all-versions     8.3 / 8.4 / 8.5 icin fpm-nginx kur"
	@echo "make clean            Yerel image'lari sil"
	@echo ""
	@echo "Degiskenler: PHP=$(PHP) VARIANT=$(VARIANT) PLATFORM=$(PLATFORM)"

build:
	docker build \
		--platform $(PLATFORM) \
		--target $(VARIANT) \
		--build-arg PHP_VERSION=$(PHP) \
		-t $(TAG) .
	@echo "kuruldu: $(TAG)"

test: build
	@echo "== PHP surumu =="
	@docker run --rm --platform $(PLATFORM) $(TAG) php -v | head -1
	@echo "== Extension kontrolu =="
	@docker run --rm --platform $(PLATFORM) $(TAG) php -r '\
		$$req = ["redis","igbinary","gd","pdo_mysql","pdo_sqlite","zip","bcmath","intl","soap","exif","Zend OPcache","pcntl","sockets"]; \
		$$m = array_values(array_filter($$req, fn($$e) => !extension_loaded($$e))); \
		if ($$m) { fwrite(STDERR, "eksik: ".implode(", ", $$m)."\n"); exit(1); } \
		echo "hepsi yuklu\n";'
	@echo "== GD format destegi =="
	@docker run --rm --platform $(PLATFORM) $(TAG) php -r '\
		$$g = gd_info(); \
		$$m = array_values(array_filter(["WebP Support","JPEG Support","PNG Support","FreeType Support"], fn($$k) => empty($$g[$$k]))); \
		if ($$m) { fwrite(STDERR, "GD eksik: ".implode(", ", $$m)."\n"); exit(1); } \
		echo "GD tam destekli\n";'
	@echo "== php.ini limitleri =="
	@docker run --rm --platform $(PLATFORM) $(TAG) php -r '\
		printf("upload_max_filesize=%s post_max_size=%s memory_limit=%s\n", \
			ini_get("upload_max_filesize"), ini_get("post_max_size"), ini_get("memory_limit"));'
	@echo "TAMAM"

shell:
	docker run --rm -it --platform $(PLATFORM) $(TAG) sh

sizes:
	@docker images --filter "reference=$(IMAGE)" \
		--format "table {{.Repository}}:{{.Tag}}\t{{.Size}}"

all-versions:
	@for v in 8.3 8.4 8.5; do $(MAKE) --no-print-directory build PHP=$$v || exit 1; done
	@$(MAKE) --no-print-directory sizes

clean:
	-docker rmi $$(docker images -q "$(IMAGE)") 2>/dev/null || true
