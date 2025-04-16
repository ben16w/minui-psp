# minui-psp

A [MinUI](https://github.com/shauninman/MinUI) and [NextUI](https://github.com/LoveRetro/NextUI) Emu Pak for PSP, wrapping the standalone PPSSPP emulator.

## Requirements

This pak is designed and tested on the following MinUI Platforms and devices:

- `tg5040`: Trimui Brick (formerly `tg3040`)

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

Deep sleep is supported on NextUI and MinUI devices which have it enabled. Clicking the power button will immediately put the device into deep sleep. Clicking the power button again will wake the device up and resume the game.

The device can also be shut down by pressing and holding the power button for 2 seconds. **Warning**: This will **NOT** save the game, and you will lose any progress made since the last save. Also, the game will not be resumed when the device is turned back on.

### Known Issues

- When resuming from deep sleep, the Wi-Fi may not reconnect.
- When resuming from deep sleep, if the brightness is set to 0, the screen will not turn on. This can be fixed by changing the brightness.

## Saves & States

- Save states are stored in the `/.userdata/shared/PSP-ppsspp/` directory.
- Game saves are stored in the `/Saves/PSP/` directory.

## Credits

- [hrydgard](https://github.com/hrydgard) for developing [PPSSPP](https://github.com/hrydgard/ppsspp) and related projects
- [Shaun Inman](https://github.com/shauninman) for developing [MinUI](https://github.com/shauninman/MinUI).
- [ro8inmorgan](https://github.com/ro8inmorgan), [frysee](https://github.com/frysee) and the rest of the NextUI contributors for developing [NextUI](https://github.com/LoveRetro/NextUI).
- Also, thank you, [josegonzalez](https://github.com/josegonzalez), for your pak repositories, which this project is based on.

## License

This project is based on PPSSPP, which is open-source software. Please refer to the original PPSSPP license for more information.
