PAK_NAME := $(shell jq -r .name pak.json)

MINUI_POWER_CONTROL_VERSION := 1.1.0
PPSSPP_RELEASE_URL := https://github.com/spruceUI/PPSSPP-spruce/releases/download/latest

clean:
	rm -f bin/minui-power-control PPSSPP/PPSSPPSDL_tg5040 PPSSPP/PPSSPPSDL_tg5050 PPSSPP/setalpha PPSSPP/libSDL2-2.0.so.0

bump-version:
	jq '.version = "$(RELEASE_VERSION)"' pak.json > pak.json.tmp
	mv pak.json.tmp pak.json

build: bin/minui-power-control PPSSPP/PPSSPPSDL_tg5040 PPSSPP/PPSSPPSDL_tg5050 PPSSPP/setalpha PPSSPP/libSDL2-2.0.so.0
	@echo "Build complete"

bin/minui-power-control:
	mkdir -p bin
	curl -f -o bin/minui-power-control -sSL https://github.com/ben16w/minui-power-control/releases/download/$(MINUI_POWER_CONTROL_VERSION)/minui-power-control
	chmod +x bin/minui-power-control

PPSSPP/PPSSPPSDL_tg5040:
	curl -f -o PPSSPP/PPSSPPSDL_tg5040 -sSL $(PPSSPP_RELEASE_URL)/PPSSPPSDL_TrimUI
	chmod +x PPSSPP/PPSSPPSDL_tg5040

PPSSPP/PPSSPPSDL_tg5050:
	curl -f -o PPSSPP/PPSSPPSDL_tg5050 -sSL $(PPSSPP_RELEASE_URL)/PPSSPPSDL_SmartProS
	chmod +x PPSSPP/PPSSPPSDL_tg5050

PPSSPP/setalpha:
	curl -f -o PPSSPP/setalpha -sSL $(PPSSPP_RELEASE_URL)/setalpha
	chmod +x PPSSPP/setalpha

PPSSPP/libSDL2-2.0.so.0:
	curl -f -o PPSSPP/libSDL2-2.0.so.0 -sSL $(PPSSPP_RELEASE_URL)/libSDL2-2.0.so.0

release: build
	mkdir -p dist
	git archive --format=zip --output "dist/$(PAK_NAME).pak.zip" HEAD
	while IFS= read -r file; do zip -r "dist/$(PAK_NAME).pak.zip" "$$file"; done < .gitarchiveinclude
	ls -lah dist
