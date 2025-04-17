TAG ?= latest
PAK_NAME := $(shell jq -r .label config.json)

MINUI_PRESENTER_VERSION := 0.7.0

clean:
	rm -f bin/*/handle-power-button

build: bin/minui-power-control
	@echo "Build complete"

bin/minui-power-control:
	@echo "Building minui-power-control"

release: build
	mkdir -p dist
	git archive --format=zip --output "dist/$(PAK_NAME).pak.zip" HEAD
	while IFS= read -r file; do zip -r "dist/$(PAK_NAME).pak.zip" "$$file"; done < .gitarchiveinclude
	ls -lah dist
