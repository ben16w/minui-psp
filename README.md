# MinUI PSP

A [MinUI](https://github.com/shauninman/MinUI) and [NextUI](https://github.com/LoveRetro/NextUI) Emu Pak for PSP, wrapping the standalone PPSSPP emulator.

## Requirements

This pak is designed and tested on the following MinUI Platforms and devices:

- `tg4040`: Trimui Brick Pro
- `tg5040`: Trimui Brick (formerly `tg3040`), Trimui Smart Pro
- `tg5050`: Trimui Smart Pro S
- `h700`: Anbernic H700 devices (e.g. RG XX)

The pak may work on other platforms and devices, but it has not been tested on them.

## Installation

1. Mount your MinUI SD card.
2. Download the latest release from GitHub. It will be named `PSP.pak.zip`.
3. Copy the zip file to the correct platform folder in the "/Emus" directory on the SD card. Please ensure the new zip file name is `PSP.pak.zip`.
4. Extract the zip in place, then delete the zip file.
5. Confirm that there is a `/Emus/<PLATFORM>/PSP.pak/launch.sh` file on your SD card.
6. Create a folder at `/Roms/PlayStation Portable (PSP)` and place your ROMs in this directory.
7. Unmount your SD Card and insert it into your MinUI device.

Note: The `<PLATFORM>` folder name is based on the name of your device. For example, use `tg4040` for TrimUI Brick Pro and `tg5040` for TrimUI Brick.

## Extra Controls

- `Menu` - Open the PPSSPP menu.
- `R2` - Swap between the D-Pad and the Analog Stick.

## Deep Sleep & Shutdown

Deep sleep is supported on compatible devices. Click the power button to enter deep sleep. Click again to resume the game. To shut down, hold the power button for 2 seconds. **Note:** Shutdown does not save or resume the game and any unsaved progress will be lost. For more information and issues, see [MinUI Power Control](https://github.com/ben16w/minui-power-control).

## Saves & States

- Save states are stored in the `/.userdata/shared/PSP-ppsspp/` directory.
- Game saves are stored in the `/Saves/PSP/` directory.

## PPSSPP Configuration

Per-device defaults live in `/Emus/<PLATFORM>/PSP.pak/config/` (`controls-*.ini` and `ppsspp-*.ini`). On launch the active profile is copied into `PPSSPP/.config/ppsspp/PSP/SYSTEM/`; on exit, changes are written back to the matching `config/` files.

The PPSSPP configuration directory also contains:

- **TEXTURES directory**: `/Emus/<PLATFORM>/PSP.pak/PPSSPP/.config/ppsspp/PSP/TEXTURES/` - Place custom texture packs here for texture replacement/modding.
- **SYSTEM directory**: The live `ppsspp.ini` and `controls.ini` used while PPSSPP runs.

Note: The `<PLATFORM>` folder name is based on your device (e.g., `tg4040` for TrimUI Brick Pro, `tg5040` for TrimUI Brick, `h700` for Anbernic H700).

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
