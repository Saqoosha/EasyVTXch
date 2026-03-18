# EasyVTXch

**One-tap VTX channel changer for EdgeTX + ELRS.**

Changing your VTX channel through ELRS normally takes 8-10 button presses:
SYS → Tools → ELRS → wait → VTX Admin → Band → Channel → Power → Send

**EasyVTXch does it in 2 steps:** launch the script → tap the channel. Done.

## Features

- **One-tap switching** — tap a channel button and the VTX command is sent instantly
- **Favorites** — long-press any channel to save it. Your favorites appear at the top for quick access
- **All 5 bands** — A, B, E, F, R with 8 channels each (40 channels total)
- **Frequency display** — every button shows the actual frequency in MHz
- **Remembers your settings** — favorites and last selected band persist across power cycles
- **Works on any radio** — color LCD (TX16S, TX18S, Boxer, etc.) and B&W LCD (Zorro, TX12, etc.)

## What You Need

| Requirement | Details |
|-------------|---------|
| **Radio firmware** | EdgeTX 2.11 or newer |
| **TX module** | Any ELRS module (internal or external) |
| **VTX** | Any VTX that supports SmartAudio or Tramp (CRSF VTX control) |
| **Receiver** | ELRS receiver connected to the VTX via SmartAudio/Tramp |

> **Note:** Your VTX must be wired to the receiver's SmartAudio/Tramp output, and VTX Admin must be enabled in ELRS. If you can already change VTX settings through ELRS Lua → VTX Administrator, you're good to go.

## Installation

**Just one file — no dependencies, no configuration.**

1. Download [`EasyVTXch.lua`](https://raw.githubusercontent.com/Saqoosha/EasyVTXch/main/EasyVTXch.lua)
2. Copy it to your radio's SD card at:
   ```
   /SCRIPTS/TOOLS/EasyVTXch.lua
   ```
3. That's it! Find it on your radio under **SYS → Tools → EasyVTXch**

### How to copy to SD card

- **USB:** Connect your radio via USB, choose "USB Storage" mode, and copy the file
- **SD card reader:** Remove the SD card, use a card reader on your computer
- **EdgeTX Companion:** Use the SD card sync feature

### Updating

To update, just overwrite the `.lua` file with the new version. If the script doesn't seem to update, delete the cached file `EasyVTXch.luac` from the same folder (EdgeTX caches compiled scripts).

## How to Use

### Color LCD Radios (TX16S, TX18S, Boxer, etc.)

| Action | What it does |
|--------|-------------|
| **Tap a channel button** | Sends the VTX command immediately |
| **Long-press a channel** | Adds/removes it from favorites |
| **Tap a band button** (A/B/E/F/R) | Switches to that band's channels |

Favorite channels appear in a quick-access grid at the top of the screen.

### B&W LCD Radios (Zorro, TX12, etc.)

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
| Channel changes but VTX doesn't respond | Check the SmartAudio/Tramp wiring between your receiver and VTX. Also verify your VTX supports the protocol. |

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
