TAG ?= latest
PAK_NAME := $(shell jq -r .label config.json)

ARCHITECTURES := arm64
PLATFORMS := tg5040

COREUTILS_VERSION := 0.0.28
EVTEST_VERSION := 0.1.0

clean:
	rm -f bin/*/evtest || true
	rm -f bin/*/evtest.LICENSE || true

build: $(foreach arch,$(ARCHITECTURES),bin/$(arch)/coreutils bin/$(arch)/evtest bin/$(arch)/handle-power-button)
	@echo "Building for $(ARCHITECTURES)"
	@echo "Building for $(PLATFORMS)"
	@echo "Build complete"

bin/arm64/coreutils:
	mkdir -p bin/arm64
	curl -sSL -o bin/arm64/coreutils.tar.gz "https://github.com/uutils/coreutils/releases/download/$(COREUTILS_VERSION)/coreutils-$(COREUTILS_VERSION)-aarch64-unknown-linux-gnu.tar.gz"
	tar -xzf bin/arm64/coreutils.tar.gz -C bin/arm64 --strip-components=1
	rm bin/arm64/coreutils.tar.gz
	chmod +x bin/arm64/coreutils
	mv bin/arm64/LICENSE bin/arm64/coreutils.LICENSE
	rm bin/arm64/README.md bin/arm64/README.package.md || true

bin/%/evtest:
	mkdir -p bin/$*
	curl -sSL -o bin/$*/evtest https://github.com/josegonzalez/compiled-evtest/releases/download/$(EVTEST_VERSION)/evtest-$*
	curl -sSL -o bin/$*/evtest.LICENSE "https://raw.githubusercontent.com/freedesktop-unofficial-mirror/evtest/refs/heads/master/COPYING"
	chmod +x bin/$*/evtest

# compile the go code at bin/tg5040/handle-power-button.go
bin/%/handle-power-button:
	mkdir -p bin/$*
	CGO_ENABLED=0 GOOS=linux GOARCH="$*" go build -o bin/$*/handle-power-button -ldflags="-s -w" -trimpath ./src/handle-power-button.go
	chmod +x bin/$*/handle-power-button

release: build
	mkdir -p dist
	git archive --format=zip --output "dist/$(PAK_NAME).pak.zip" HEAD
	while IFS= read -r file; do zip -r "dist/$(PAK_NAME).pak.zip" "$$file"; done < .gitarchiveinclude
	ls -lah dist