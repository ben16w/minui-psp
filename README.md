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

## PPSSPP Configuration

The PPSSPP configuration directory is located at `/Emus/<PLATFORM>/PSP.pak/PPSSPP/.config/ppsspp/`. This directory contains:

- **TEXTURES directory**: `/Emus/<PLATFORM>/PSP.pak/PPSSPP/.config/ppsspp/PSP/TEXTURES/` - Place custom texture packs here for texture replacement/modding.
- **SYSTEM directory**: Contains configuration files like `ppsspp.ini` and `controls.ini`.

Note: The `<PLATFORM>` folder name is based on your device (e.g., `tg5040` for TrimUI Brick).

## Aspect Ratio

The pak auto-sets the Aspect Ratio based on the device model. On Trimui Brick it uses `0.848000`, on other supported devices it uses `1.000000`. To disable automatic configuration changes, create a file named `no-config-changes` in `/.userdata/<PLATFORM>/PSP-ppsspp/`. This will prevent the pak from modifying aspect ratio and other configuration settings. If the aspect ratio or graphics backend setting is missing from the `[Graphics]` section of `ppsspp.ini`, the pak adds it.

## RetroAchievements

On NextUI, the pak copies the RetroAchievements settings from the NextUI Settings menu into PPSSPP every time a game is launched:

- **Enabled and logged in** in NextUI: RetroAchievements are enabled in PPSSPP with the same username and login token, and NextUI's Hardcore Mode setting is applied to PPSSPP's Hardcore Mode. No separate login inside PPSSPP is needed.
- **Disabled, or not logged in** in NextUI: RetroAchievements are disabled in PPSSPP, and the PPSSPP username and login token are removed.
- **MinUI** (no NextUI settings file), or a NextUI version without RetroAchievements settings: PPSSPP's own RetroAchievements settings are left untouched.

Notes:

- NextUI's offline RetroAchievements mode (caching and replaying unlocks when Wi-Fi returns) is built into NextUI's own emulator frontend and is not available to standalone PPSSPP. PPSSPP connects to retroachievements.org directly, so Wi-Fi must be connected when the game starts. If the login fails at startup, PPSSPP retries it periodically while its menu is open.
- In Hardcore Mode, PPSSPP disables save states.
- To manage RetroAchievements inside PPSSPP yourself, create a file named `no-ra-sync` in `/.userdata/<PLATFORM>/PSP-ppsspp/`. The `no-config-changes` file also disables this sync.
- To use a different RetroAchievements server (for example a local caching proxy), put its URL (e.g. `http://192.168.1.10:8080`) on the first line of `/.userdata/<PLATFORM>/PSP-ppsspp/ra-host`. Delete the file to switch back to retroachievements.org.

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
