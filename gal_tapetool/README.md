# Galaksija Tape Tool (`gal_gtp_wav.py`)

This tool provides conversion between **Galaksija .GTP files** (tape images) and **.WAV audio files** following Tomaž Šolc’s documented timing. It simplifies transferring programs between emulators, modern development, and real Galaksija hardware.

## Features
- Convert `.gtp` → `.wav` with correct pulse timings.
- Convert `.wav` → `.gtp` using a robust PCM pulse decoder.
- Supports variable leader lengths (sync bytes).
- Automatically wraps A5-starting decoded streams into valid `.gtp`.
- Debug mode for inspecting thresholds, impulses, and hex dumps.

## Requirements
- Python 3.7 or newer
- Libraries:
  - `numpy`
  - `scipy`

Install requirements:
```bash
pip install numpy scipy
```

## Usage

### GTP → WAV
Convert a `.gtp` tape image into an audio file suitable for loading on Galaksija:

```bash
python gal_tapetool/gal_gtp_wav.py gtp2wav --in program.gtp --out program.wav
```

Options:
- `--sr` Sample rate in Hz (default: 44100)
- `--bits` Bit depth: 8 or 16 (default: 16)
- `--debug` Print extra information during generation

### WAV → GTP
Decode a `.wav` file back into a `.gtp`:

```bash
python gal_tapetool/gal_gtp_wav.py wav2gtp --in tape.wav --out program.gtp
```

Options:
- `--debug` Print decoding stats, impulses, and hex dump of payload

## Debug Mode
When `--debug` is used, the tool prints:
- Samplerate and amplitude threshold
- Number of detected impulses
- Timing parameters in samples
- Hex dump (first 256 bytes) of decoded payload and resulting GTP block

## Format Notes
- Standard `.gtp` files begin with `[00][len_lo len_hi][00 00][A5..]…[checksum][00]`.
- Some tapes may start directly with `A5`; the tool will automatically wrap such payloads into a valid `.gtp`.

## Credits
- Tomaž Šolc – *Replika mikroračunalnika Galaksija* thesis (2007).  
  [Link to thesis (archived)](https://web.archive.org/web/20221228104808if_/https://www.tablix.org/~avian/blog/papers/tomaz_solc_replika_mikroracunalnika_galaksija.pdf)
- Timings and original specification by **Tomaž Šolc**
- Adaptation and tooling by **Aleksandar Miladinović**
