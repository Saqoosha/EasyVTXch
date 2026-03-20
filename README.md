# EasyVTXch

> **[日本語版はこちら (Japanese)](README_ja.md)**

**One-tap VTX channel changer for EdgeTX + ELRS.**

Changing your VTX channel through ELRS normally takes 8-10 button presses:
SYS → Tools → ELRS → wait → VTX Admin → Band → Channel → Power → Send

**EasyVTXch does it in 2 steps:** launch the script → tap the channel. Done.

![EasyVTXch on RadioMaster TX15](screenshot.jpg)

## Features

- **One-tap switching** — tap a channel button and the VTX command is sent instantly
- **Favorites** — long-press any channel to save it. Your favorites appear at the top for quick access
- **All 5 bands** — A, B, E, F, R with 8 channels each (40 channels total)
- **Frequency display** — every button shows the actual frequency in MHz
- **Remembers your settings** — favorites and last selected band persist across power cycles
- **Works on any radio** — color LCD radios (TX16S, TX15, etc.). B&W LCD support (Boxer, Zorro, TX12, etc.) is planned but not yet tested

> **Note:** EasyVTXch changes band and channel only — VTX power is not modified. Your current power setting stays as-is.

## What You Need

| Requirement | Details |
|-------------|---------|
| **Radio firmware** | EdgeTX 2.11 or newer |
| **TX module** | Any ELRS module (internal or external) |
| **VTX** | Any VTX with SmartAudio, Tramp, or HDZero (DisplayPort) |
| **Receiver** | ELRS receiver connected to the VTX |

> **How do I know if my setup is compatible?** If you can change VTX channel/power from your goggles OSD (Betaflight OSD → VTX settings), SmartAudio/Tramp is already working. EasyVTXch uses the same connection — just controlled from your radio instead of the OSD.

## Installation

**Just one file — no dependencies, no configuration.**

1. Download [`EasyVTXch.lua`](https://github.com/Saqoosha/EasyVTXch/releases/latest/download/EasyVTXch.lua) from the [Releases page](https://github.com/Saqoosha/EasyVTXch/releases)
2. Copy it to your radio's SD card at:
   ```
   /SCRIPTS/TOOLS/EasyVTXch.lua
   ```
3. That's it! Find it on your radio under **SYS → Tools → EasyVTXch**

### How to copy to SD card

- **USB:** Connect your radio via USB, choose "USB Storage" mode, and copy the file
- **SD card reader:** Remove the SD card, use a card reader on your computer

### Updating

To update, just overwrite the `.lua` file with the new version. If the script doesn't seem to update, delete the cached file `EasyVTXch.luac` from the same folder (EdgeTX caches compiled scripts).

## How to Use

### Step by Step

1. **Power on your transmitter** and wait for EdgeTX to boot
2. **Plug in the battery** to your drone (or power on your VTX)
3. **Confirm binding** — make sure your TX module and receiver are bound and connected
4. **SYS → Tools → EasyVTXch** — launch the script
5. **Tap the channel** you want — done!

### Color LCD Radios (TX16S, TX15, etc.)

| Action | What it does |
|--------|-------------|
| **Tap a channel button** | Sends the VTX command immediately |
| **Long-press a channel** | Adds/removes it from favorites |
| **Tap a band button** (A/B/E/F/R) | Switches to that band's channels |

Favorite channels appear in a quick-access grid at the top of the screen.

### B&W LCD Radios (Boxer, Zorro, TX12, etc.)

> **Note:** B&W LCD support is included but not yet tested on real hardware.

| Action | What it does |
|--------|-------------|
| **Scroll** (encoder/buttons) | Navigate the channel list |
| **Enter** | Send VTX command |
| **Long-press Enter** | Add/remove favorite |
| **Menu** | Cycle through bands (A → B → E → F → R) |

Favorites are marked with a `*` and shown at the top of the list.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "TX module not found" | Make sure your ELRS module is powered on and bound. Check that CRSF is selected as the protocol in EdgeTX. |
| "VTX Admin not found" | VTX Admin must be enabled in ELRS. Connect to your module via ExpressLRS Configurator or Lua script and verify VTX Admin is available. |
| "VTX fields incomplete" | Your ELRS firmware may be too old. Update to ELRS 3.x or newer. |
| Script doesn't appear in Tools | Make sure the file is named `EasyVTXch.lua` (case-sensitive) and is in `/SCRIPTS/TOOLS/`. |
| Script doesn't update after replacing file | Delete `EasyVTXch.luac` from the same folder. EdgeTX caches compiled scripts. |
| Channel changes but VTX doesn't respond | Check the wiring between your receiver and VTX (SmartAudio, Tramp, or DisplayPort). Also verify your VTX supports the protocol. |

## Supported Frequencies

| Band | Ch1  | Ch2  | Ch3  | Ch4  | Ch5  | Ch6  | Ch7  | Ch8  |
|------|------|------|------|------|------|------|------|------|
| A    | 5865 | 5845 | 5825 | 5805 | 5785 | 5765 | 5745 | 5725 |
| B    | 5733 | 5752 | 5771 | 5790 | 5809 | 5828 | 5847 | 5866 |
| E    | 5705 | 5685 | 5665 | 5645 | 5885 | 5905 | 5925 | 5945 |
| F    | 5740 | 5760 | 5780 | 5800 | 5820 | 5840 | 5860 | 5880 |
| R    | 5658 | 5695 | 5732 | 5769 | 5806 | 5843 | 5880 | 5917 |

These are the standard FPV frequency bands used by all major VTX manufacturers.

## For Developers

See [ARCHITECTURE.md](ARCHITECTURE.md) for internal architecture, CRSF protocol details, and implementation notes.

### Running Tests

```bash
lua5.4 test_mock.lua
```

## License

MIT
