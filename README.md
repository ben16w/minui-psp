# MinUI PSP

A [MinUI](https://github.com/shauninman/MinUI) and [NextUI](https://github.com/LoveRetro/NextUI) Emu Pak for PSP, wrapping the standalone PPSSPP emulator.

## Requirements

This pak is designed and tested on the following MinUI Platforms and devices:

- `tg5040`: Trimui Brick (formerly `tg3040`), Trimui Smart Pro
- `tg5050`: Trimui Smart Pro S
- `zero28`: MagicX Mini Zero 28, on MinUI with [MOSS](https://github.com/shauninman/Moss-zero28) (see [MagicX Mini Zero 28](#magicx-mini-zero-28))

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

The pak auto-sets the Aspect Ratio based on the device model. On Trimui Brick it uses `0.848000`, on other supported devices it uses `1.000000`. To disable automatic configuration changes, create a file named `no-config-changes` in `/.userdata/<PLATFORM>/PSP-ppsspp/`. This will prevent the pak from modifying aspect ratio and other configuration settings.

## MagicX Mini Zero 28

The Zero 28 has the same Allwinner A133P and PowerVR GE8300 as the Trimui Brick and Smart Pro, and MOSS ships the Smart Pro's SDL2, so it runs the same PowerVR PPSSPP build (`PPSSPPSDL_TrimUI`). That build needs two things that come from [PPSSPP-spruce's `magicx-zero28` work](https://github.com/arniebradfo/PPSSPP-spruce/tree/magicx-zero28): display rotation, and the in-game menu. Both stay off unless `launch.sh` turns them on, so the Brick and Smart Pro are unaffected.

- **Display:** the 640x480 panel is mounted portrait (480x640), and MOSS's SDL2 can't rotate GL output. `launch.sh` sets `DISPLAY_ROTATION=90` and PPSSPP rotates its own output. If the picture is upside down, put `270` in `/.userdata/zero28/PSP-ppsspp/rotation`.
- **In-game menu:** `Menu` opens a MinUI-style menu: Continue, Save State, Load State (slots with screenshots), Options, PPSSPP Menu (PPSSPP's own menu) and Quit. It draws with MinUI's own font and turns with the display. The settings under Options are listed in [`zero28/overlay/overlay_settings.json`](zero28/overlay/overlay_settings.json).
- **Controls:** face buttons follow the PSP's layout by position: bottom (B) = Cross, right (A) = Circle, left (Y) = Square, top (X) = Triangle. `R2` swaps the D-Pad and the Analog Stick.
- **Power button:** MinUI Power Control reads a fixed input device that isn't the Zero 28's power key, so the Zero 28 uses [`zero28-powerd`](zero28/powerd.c) instead. It follows MinUI's own Zero 28 sleep: click to sleep and click again to wake. Holding for a second, or sleeping for two minutes on battery, quits PPSSPP and powers off. Shutdown doesn't save, so make a save state first.
- **Volume:** opening the audio device leaves the Zero 28's codec at full volume, so `launch.sh` has MinUI's `syncsettings.elf` restore your volume a few seconds after launch.
- **Save state screenshots** go to `/.userdata/shared/.minui/PSP/`, where MinUI's own emulators keep theirs.

Related pull requests (each links the others, so this code stays findable whichever is merged or declined):

- [ben16w/minui-psp#88](https://github.com/ben16w/minui-psp/pull/88): Zero 28 support in the MinUI PSP pak
- [ben16w/PPSSPP-spruce#3](https://github.com/ben16w/PPSSPP-spruce/pull/3): display rotation and the in-game menu in the PowerVR build
- [spruceUI/PPSSPP-spruce#5](https://github.com/spruceUI/PPSSPP-spruce/pull/5): only the rotation fix
- [ryanmsartor/Mini-Zero-28-Custom-MinUI-Paks#4](https://github.com/ryanmsartor/Mini-Zero-28-Custom-MinUI-Paks/pull/4): a ready-built PSP.pak for the Zero 28, built from these

## Skip Buffer Effects

This option can be found under Settings > Graphics > Speed Hacks > Skip buffer effects. Use it as a last‑resort speed boost for demanding games. It can break transparency/lighting or even cause black screens. It's best to toggle it per game as needed.

## Thanks

- [hrydgard](https://github.com/hrydgard) for developing [PPSSPP](https://github.com/hrydgard/ppsspp) and related projects.
- [spruceUI](https://github.com/spruceUI) team for creating the [PPSSPP-spruce](https://github.com/spruceUI/PPSSPP-spruce) repository.
- [frysee](https://github.com/frysee) and the rest of the NextUI contributors for developing [NextUI](https://github.com/LoveRetro/NextUI).
- [Shaun Inman](https://github.com/shauninman) for developing [MinUI](https://github.com/shauninman/MinUI).
- Also [josegonzalez](https://github.com/josegonzalez), for their pak repositories, which this project is based on.

For the MagicX Mini Zero 28 support:

- [mohammadsyuhada](https://github.com/mohammadsyuhada) for [nx-redux](https://github.com/mohammadsyuhada/nx-redux), whose emulator overlay and PPSSPP integration are the Zero 28's in-game menu. `zero28/overlay/overlay_settings.json` is adapted from its PPSSPP settings list, and `zero28/overlay/res/` holds its button icons.
- [Shaun Inman](https://github.com/shauninman) for [MOSS](https://github.com/shauninman/Moss-zero28) and MinUI's Zero 28 platform. `zero28-powerd` follows MinUI's Zero 28 sleep and power-off, and uses its `bl_enable`, `bl_disable` and `syncsettings.elf`.
- The [spruceUI](https://github.com/spruceUI) team, whose [spruceOS](https://github.com/spruceUI/spruceOS) Zero 28 platform config confirmed the panel rotation and the pad's controller mapping.
- [ben16w](https://github.com/ben16w)'s [MinUI Power Control](https://github.com/ben16w/minui-power-control), which `zero28-powerd` stands in for on the Zero 28.
- [josegonzalez/minui-n64-pak](https://github.com/josegonzalez/minui-n64-pak), whose `EMU_PAD` button format the Zero 28 menu uses.
- The Zero 28 port was written by Claude (Anthropic's Claude Opus 5.5) in Claude Code, and tested on a Zero 28 by [arniebradfo](https://github.com/arniebradfo).

## License

This project uses PPSSPP, which is open-source software. Please refer to the original PPSSPP [LICENSE.TXT](PPSSPP/LICENSE.TXT) file for more details.

The project code which is not part of PPSSPP is licensed under the [MIT License](https://opensource.org/licenses/MIT). See the project [LICENSE](LICENSE) file for more details.

The files in `zero28/overlay/` come from [nx-redux](https://github.com/mohammadsyuhada/nx-redux) and are licensed under the [GPL-3.0](https://www.gnu.org/licenses/gpl-3.0.html), as is the in-game menu code built into the PowerVR PPSSPP binary.
