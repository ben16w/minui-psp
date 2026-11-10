# MinUI PSP

A [MinUI](https://github.com/shauninman/MinUI) and [NextUI](https://github.com/LoveRetro/NextUI) Emu Pak for PSP, wrapping the standalone PPSSPP emulator.

## Requirements

This pak is designed and tested on the following MinUI Platforms and devices:

- `tg5040`: Trimui Brick (formerly `tg3040`), Trimui Smart Pro
- `tg5050`: Trimui Smart Pro S

The pak may work on other platforms and devices, but it has not been tested on them.

## Installation

1. Mount your MinUI SD card.
2. Download the latest release from GitHub. It will be named `PSP.pak.zip`.
3. Copy the zip file to the correct platform folder in the "/Emus" directory on the SD card. Please ensure the new zip file name is `PSP.pak.zip`.
4. Extract the zip in place, then delete the zip file.
5. Confirm that there is a `/Emus/<PLATFORM>/PSP.pak/launch.sh` file on your SD card.
6. Create a folder at `/Roms/PlayStation Portable (PSP)` and place your ROMs in this directory.
7. Unmount your SD Card and insert it into your MinUI device.

Note: The `<PLATFORM>` folder name is based on the name of your device. For example, if you are using a TrimUI Brick, the folder is `tg5040`.

## Extra Controls

- `Menu` - Open the PPSSPP menu.
- `R2` - Swap between the D-Pad and the Analog Stick.

## Deep Sleep & Shutdown

Deep sleep is supported on compatible devices. Click the power button to enter deep sleep. Click again to resume the game. To shut down, hold the power button for 2 seconds. **Note:** Shutdown does not save or resume the game and any unsaved progress will be lost. For more information and issues, see [MinUI Power Control](https://github.com/ben16w/minui-power-control).

## Saves & States

- Save states are stored in the `/.userdata/shared/PSP-ppsspp/` directory.
- Game saves are stored in the `/Saves/PSP/` directory.

## Game Switcher Image

Like the built-in emulators, the image NextUI's Game Switcher shows for a game comes from a save state. When PPSSPP exits (or the device powers off while it runs), the pak takes the newest save state written during that session, converts its thumbnail with the bundled `jpg2bmp` and writes it to `/.userdata/shared/.minui/PSP/<rom file>.<slot>.bmp`, together with the slot number in `<rom file>.txt`.

No save state means no image: NextUI shows "No Preview". Opening and resuming a game works as before.

## PPSSPP Configuration

The PPSSPP configuration directory is located at `/Emus/<PLATFORM>/PSP.pak/PPSSPP/.config/ppsspp/`. This directory contains:

- **TEXTURES directory**: `/Emus/<PLATFORM>/PSP.pak/PPSSPP/.config/ppsspp/PSP/TEXTURES/` - Place custom texture packs here for texture replacement/modding.
- **SYSTEM directory**: Contains configuration files like `ppsspp.ini` and `controls.ini`.

Note: The `<PLATFORM>` folder name is based on your device (e.g., `tg5040` for TrimUI Brick).

## Aspect Ratio

The pak auto-sets the Aspect Ratio based on the device model. On Trimui Brick it uses `0.848000`, on other supported devices it uses `1.000000`. To disable automatic configuration changes, create a file named `no-config-changes` in `/.userdata/<PLATFORM>/PSP-ppsspp/`. This will prevent the pak from modifying aspect ratio and other configuration settings.

## Skip Buffer Effects

This option can be found under Settings > Graphics > Speed Hacks > Skip buffer effects. Use it as a last‑resort speed boost for demanding games. It can break transparency/lighting or even cause black screens. It's best to toggle it per game as needed.

## Thanks

- [hrydgard](https://github.com/hrydgard) for developing [PPSSPP](https://github.com/hrydgard/ppsspp) and related projects.
- [spruceUI](https://github.com/spruceUI) team for creating the [PPSSPP-spruce](https://github.com/spruceUI/PPSSPP-spruce) repository.
- [frysee](https://github.com/frysee) and the rest of the NextUI contributors for developing [NextUI](https://github.com/LoveRetro/NextUI).
- [Shaun Inman](https://github.com/shauninman) for developing [MinUI](https://github.com/shauninman/MinUI).
- Also [josegonzalez](https://github.com/josegonzalez), for their pak repositories, which this project is based on.

## License

This project uses PPSSPP, which is open-source software. Please refer to the original PPSSPP [LICENSE.TXT](PPSSPP/LICENSE.TXT) file for more details.

The project code which is not part of PPSSPP is licensed under the [MIT License](https://opensource.org/licenses/MIT). See the project [LICENSE](LICENSE) file for more details.

## Testing the Game Switcher image on a device

`tests/device/run.sh` runs the real `launch.sh` and `bin/jpg2bmp` against a stub PPSSPP in a throw-away SD tree, and checks the preview image and slot file (no save state, one state, the newest slot wins, other games unaffected), that the resume hand-off file is removed, and the SIGTERM (power-off) path. Over SSH:

```sh
scp -r tests root@<device>:/mnt/SDCARD/Emus/tg5040/PSP.pak/
ssh root@<device> 'sh /mnt/SDCARD/Emus/tg5040/PSP.pak/tests/device/run.sh'
```

It prints PASS/FAIL per test and exits non-zero on failure. Logs are kept in `/tmp/psp-preview-test-out`. The real SD card is not modified.

### Fully automated end-to-end test

`tests/device/e2e.sh` drives the real NextUI and PPSSPP on a TrimUI device with no one at the buttons: it injects button presses through the `TRIMUI Player1` evdev device, launches the first game in `Roms/*(PSP)` through NextUI's `/tmp/next` hand-off, and takes screenshots with the [Screenshot Monitor](https://github.com/josegonzalez/minui-screenshot-monitor-pak) pak's `bin/screenshot`. Screenshots are judged by the bundled `pngcolor` helper.

Requirements: root over SSH, this pak and the Screenshot Monitor pak installed, and a game in `Roms/*(PSP)`. CI publishes the `psp-device-tests` artifact (`psp-device-tests.tar.gz`) with the script, fixtures and the aarch64 helper:

```sh
scp psp-device-tests.tar.gz root@<device>:/tmp/
ssh root@<device> 'cd /tmp && tar xzf psp-device-tests.tar.gz && sh tests/device/e2e.sh'
```

The script temporarily changes the recents and resume files of the test game and restores them on exit (its backup is kept on the SD card, so a run that was cut short is restored at the start of the next one). It restarts NextUI with SIGKILL, never SIGTERM, because NextUI treats SIGTERM as a power-off request. It expects these PPSSPP hotkeys: select+R1 saves a state, select+right moves to the next slot, select+start exits. See the header of `e2e.sh` for the settings (`PSP_KEYS`, `EXIT_KEYS`, wait times).
