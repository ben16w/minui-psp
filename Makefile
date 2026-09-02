PAK_NAME := $(shell jq -r .name pak.json)

MINUI_POWER_CONTROL_VERSION := 1.1.0
PPSSPP_RELEASE_URL := https://github.com/ben16w/PPSSPP-spruce/releases/download/beta-main
SPRUCEOS_PSP_URL := https://raw.githubusercontent.com/spruceUI/spruceOS/main/Emu/PSP

clean:
	rm -f bin/minui-power-control bin/setalpha PPSSPP/PPSSPPSDL_tg4040 PPSSPP/PPSSPPSDL_tg5040 PPSSPP/PPSSPPSDL_tg5050 PPSSPP/libstdc++.so.6

bump-version:
	jq '.version = "$(RELEASE_VERSION)"' pak.json > pak.json.tmp
	mv pak.json.tmp pak.json

build: bin/minui-power-control bin/setalpha PPSSPP/PPSSPPSDL_tg4040 PPSSPP/PPSSPPSDL_tg5040 PPSSPP/PPSSPPSDL_tg5050 PPSSPP/libstdc++.so.6
	@echo "Build complete"

bin/minui-power-control:
	mkdir -p bin
	curl -f -o bin/minui-power-control -sSL https://github.com/ben16w/minui-power-control/releases/download/$(MINUI_POWER_CONTROL_VERSION)/minui-power-control
	chmod +x bin/minui-power-control

PPSSPP/PPSSPPSDL_tg5040:
	curl -f -o PPSSPP/PPSSPPSDL_tg5040 -sSL $(PPSSPP_RELEASE_URL)/PPSSPPSDL_TrimUI
	chmod +x PPSSPP/PPSSPPSDL_tg5040

PPSSPP/PPSSPPSDL_tg4040:
	curl -f -o PPSSPP/PPSSPPSDL_tg4040 -sSL $(PPSSPP_RELEASE_URL)/PPSSPPSDL_TrimUI
	chmod +x PPSSPP/PPSSPPSDL_tg4040


PPSSPP/PPSSPPSDL_tg5050:
	curl -f -o PPSSPP/PPSSPPSDL_tg5050 -sSL $(PPSSPP_RELEASE_URL)/PPSSPPSDL_SmartProS
	chmod +x PPSSPP/PPSSPPSDL_tg5050

bin/setalpha:
	curl -f -o bin/setalpha -sSL $(SPRUCEOS_PSP_URL)/setalpha
	chmod +x bin/setalpha

PPSSPP/libstdc++.so.6:
	curl -f -o PPSSPP/libstdc++.so.6 -sSL $(SPRUCEOS_PSP_URL)/libstdc%2B%2B.so.6

release: build
	mkdir -p dist
	git archive --format=zip --output "dist/$(PAK_NAME).pak.zip" HEAD
	while IFS= read -r file; do zip -r "dist/$(PAK_NAME).pak.zip" "$$file"; done < .gitarchiveinclude
	ls -lah dist
