PAK_NAME := $(shell jq -r .name pak.json)

MINUI_POWER_CONTROL_VERSION := 1.1.0
PPSSPP_RELEASE_URL := https://github.com/ben16w/PPSSPP-spruce/releases/download/beta-main
SPRUCEOS_PSP_URL := https://raw.githubusercontent.com/spruceUI/spruceOS/main/Emu/PSP
STB_COMMIT := d14d46f6b44456eb88beac58cba833a4135d4c89

# bin/jpg2bmp must be an aarch64 binary. CI builds natively on ubuntu-24.04-arm;
# when building elsewhere pass a cross compiler, e.g. CC=aarch64-linux-gnu-gcc.

clean:
	rm -f bin/minui-power-control bin/setalpha bin/jpg2bmp PPSSPP/PPSSPPSDL_tg5040 PPSSPP/PPSSPPSDL_tg5050 PPSSPP/libstdc++.so.6 src/stb_image.h tests/device/bin/pngcolor dist/psp-device-tests.tar.gz

bump-version:
	jq '.version = "$(RELEASE_VERSION)"' pak.json > pak.json.tmp
	mv pak.json.tmp pak.json

build: bin/minui-power-control bin/setalpha bin/jpg2bmp PPSSPP/PPSSPPSDL_tg5040 PPSSPP/PPSSPPSDL_tg5050 PPSSPP/libstdc++.so.6
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

bin/setalpha:
	curl -f -o bin/setalpha -sSL $(SPRUCEOS_PSP_URL)/setalpha
	chmod +x bin/setalpha

src/stb_image.h:
	curl -f -o src/stb_image.h -sSL https://raw.githubusercontent.com/nothings/stb/$(STB_COMMIT)/stb_image.h

bin/jpg2bmp: src/jpg2bmp.c src/stb_image.h
	mkdir -p bin
	$(CC) -Os -s -static -o bin/jpg2bmp src/jpg2bmp.c
	@if ! file bin/jpg2bmp | grep -q 'ARM aarch64'; then \
		echo "bin/jpg2bmp is not an aarch64 binary ($$(file -b bin/jpg2bmp)). Build on aarch64 or pass CC=aarch64-linux-gnu-gcc." >&2; \
		rm -f bin/jpg2bmp; \
		exit 1; \
	fi
	chmod +x bin/jpg2bmp

PPSSPP/libstdc++.so.6:
	curl -f -o PPSSPP/libstdc++.so.6 -sSL $(SPRUCEOS_PSP_URL)/libstdc%2B%2B.so.6

# Test helper for tests/device/e2e.sh (not shipped in the pak): average colour of a PNG.
tests/device/bin/pngcolor: src/pngcolor.c src/stb_image.h
	mkdir -p tests/device/bin
	$(CC) -Os -s -static -o tests/device/bin/pngcolor src/pngcolor.c
	@if ! file tests/device/bin/pngcolor | grep -q 'ARM aarch64'; then \
		echo "tests/device/bin/pngcolor is not an aarch64 binary ($$(file -b tests/device/bin/pngcolor)). Build on aarch64 or pass CC=aarch64-linux-gnu-gcc." >&2; \
		exit 1; \
	fi

# Everything needed to run the on-device tests; copy to the device and extract anywhere.
test-bundle: tests/device/bin/pngcolor
	mkdir -p dist
	tar -czf dist/psp-device-tests.tar.gz tests/device/run.sh tests/device/e2e.sh tests/device/fixtures tests/device/bin
	ls -lah dist

release: build
	mkdir -p dist
	git archive --format=zip --output "dist/$(PAK_NAME).pak.zip" HEAD
	while IFS= read -r file; do zip -r "dist/$(PAK_NAME).pak.zip" "$$file"; done < .gitarchiveinclude
	ls -lah dist
