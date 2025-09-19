# Galaksija GTP Builder

## Introduction
`gal_build_gtp.py` is a helper tool that makes developing software for the **Galaksija** computer easier. It allows you to:
- Write Z80 code in a modern environment and compile it with your preferred toolchain (e.g. **z88dk**, **pasmo**, **sjasmplus**, etc.).
- Quickly wrap the resulting flat binary into a `.gtp` file, which can be easily imported into most Galaksija emulators.
- Optionally generate a `.wav` file for loading on real hardware (experimental feature).

This bridges the gap between modern Z80 development and Galaksija emulation or hardware testing.

## Requirements
- Python **3.8+**
- Standard library only (no external dependencies required)

Optional (for WAV generation):
- **numpy** (used for efficient PCM conversion)

Install requirements:
```bash
pip install numpy
```

## Usage

### Basic usage
Wrap a compiled Z80 binary into a `.gtp` file with default settings:
```bash
python gal_build_gtp.py --bin out.bin --out out.gtp
```
This produces a `.gtp` file with:
- Start address: `0x2C36`
- Code start: `0x2C3A`
- A BASIC line tail appended automatically so the program can be run with `RUN` or directly executes `USR(&2C3A)`.

### No BASIC tail
If you want the raw binary without any BASIC wrapper:
```bash
python gal_build_gtp.py --bin out.bin --out out.gtp --no-basic
```
This loads the machine code only (defaults to `0x2C3A` unless overridden with `--usr`).

### Custom code start address
You can override the code start with `--usr`. The tool will pad with `0x00` up to that address:
```bash
python gal_build_gtp.py --bin out.bin --out out.gtp --usr 0x3000
```

### WAV export (experimental)
You can also generate an audio `.wav` file, encoded using **Tomaz Šolc’s pulse-train timings**:
```bash
python gal_build_gtp.py --bin out.bin --out out.gtp --wav out.wav
```
- Mono, 16‑bit PCM, 44100 Hz
- Pulse widths: 0.6 ms
- Bit `0` = one 3.0 ms period
- Bit `1` = two 1.5 ms periods
- Inter-byte pause: 4.5 ms
- Inter-block pause: 2.0 s
- Sync leader: 100 bytes

⚠️ Note: WAV loading has not been extensively tested on real hardware yet.

## GTP File Format
The `.gtp` file format as implemented:
```
[00]
[len_lo len_hi]                 # length of everything from [00 00] before A5 up to final 0x00
[00 00]
[A5]
[start_lo start_hi]             # load address (usually 0x2C36)
[endp1_lo endp1_hi]             # end address + 1
[payload bytes ...]             #
  if BASIC present: [basic_start][basic_end+1][machine code][BASIC tail]
  else:              [machine code only]
[checksum]                      # 0xFF - (sum(A5..last payload) & 0xFF)
[00]                            # trailing terminator
```

## Credits
- **Aleksandar Miladinović** — developer of this tool.
- **Tomaz Šolc** — documentation and reference implementation of Galaksija formats.
- The original Galaksija community and emulator authors who preserved the `.gtp` specification.
