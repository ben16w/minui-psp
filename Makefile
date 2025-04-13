TAG ?= latest
PAK_NAME := $(shell jq -r .label config.json)

ARCHITECTURES := arm64
PLATFORMS := tg5040

EVTEST_VERSION := 0.1.0

clean:
	rm -f bin/*/evtest || true
	rm -f bin/*/evtest.LICENSE || true

build: $(foreach arch,$(ARCHITECTURES),bin/$(arch)/evtest)

bin/%/evtest:
	mkdir -p bin/$*
	curl -sSL -o bin/$*/evtest https://github.com/josegonzalez/compiled-evtest/releases/download/$(EVTEST_VERSION)/evtest-$*
	curl -sSL -o bin/$*/evtest.LICENSE "https://raw.githubusercontent.com/freedesktop-unofficial-mirror/evtest/refs/heads/master/COPYING"
	chmod +x bin/$*/evtest

release: build
	mkdir -p dist
	git archive --format=zip --output "dist/$(PAK_NAME).pak.zip" HEAD
	while IFS= read -r file; do zip -r "dist/$(PAK_NAME).pak.zip" "$$file"; done < .gitarchiveinclude
	ls -lah dist