TAG ?= latest
PAK_NAME := $(shell jq -r .label config.json)

ARCHITECTURES := arm64
PLATFORMS := tg5040

clean:
	rm -f bin/*/handle-power-button

build: $(foreach arch,$(ARCHITECTURES),bin/$(arch)/handle-power-button)
	@echo "Building for $(ARCHITECTURES)"
	@echo "Building for $(PLATFORMS)"
	@echo "Build complete"

bin/%/handle-power-button:
	mkdir -p bin/$*
	CGO_ENABLED=0 GOOS=linux GOARCH="$*" go build -o bin/$*/handle-power-button -ldflags="-s -w" -trimpath ./src/handle-power-button.go
	chmod +x bin/$*/handle-power-button

release: build
	mkdir -p dist
	git archive --format=zip --output "dist/$(PAK_NAME).pak.zip" HEAD
	while IFS= read -r file; do zip -r "dist/$(PAK_NAME).pak.zip" "$$file"; done < .gitarchiveinclude
	ls -lah dist
