# Galaksija High-Resolution Maker (hires_maker)

Turn any image into a 2 KB graphics stream for the Yugoslav 8-bit computer **Galaksija**.  
The app ships with several dithering modes tailored to Galaksija’s **2×3-dot tile raster**.

This tool targets enthusiasts working with real hardware or emulators that support **Tomaž Šolc’s high-resolution hires routine**.

## Features
- Live preview GUI (pan/zoom with mouse wheel + drag)
- Dithering modes:
  - Threshold (with adjustable slider)
  - Tile 2×3 (levels) — mimics Galaksija’s native tile layout
  - Floyd–Steinberg
  - Ordered 8×8 (Bayer)
  - Halftone 45° / 90°
  - Stucki
  - Atkinson
- Threshold slider + Invert checkbox
- Level correction sliders (black/white/midpoint)
- Vertical separators overlay (to see 2×3 tile boundaries)
- Dictionary-based encoding:
  - **Dot (DICT)** — uses only C0–FF from the Galaksija dictionary
  - **Full ASCII** — uses the entire ASCII + C0–FF dictionary
- Template injection into two `.GTP` variants (Galaksija 40 and Original) with automatic checksum fixup
- Optional WAV export for the “Original” template (audio load)
- Background worker keeps UI responsive while rendering and encoding

## Examples

Original → Processed preview → Display on Galaksija

<img src="img/gkidorg.png?raw=true" alt="Logo" width=320/>  
Izvor: "Računari u vašoj kući" br. 1, jan. 1984

**Dithering Ordered 8×8**

<img src="img/gkid1sc.png?raw=true" alt="Logo" height=420/>

Result on Galaksija:

![On Galaksija 1](img/gkid1.png?raw=true)

**No Dithering**

<img src="img/gkid2sc.png?raw=true" alt="Logo" height=420/>

Result on Galaksija:

![On Galaksija 2](img/gkid2.png?raw=true)

## Installation (Prebuilt Binaries)

## Prebuilt Binaries
Prebuilt executables are provided for convenience:
- **macOS Apple Silicon** (`.app` bundle, built on macOS 14.3)
- **macOS Intel** (`.app` bundle, built on macOS 14.3)
- **Windows 10/11 64-bit** (`.exe`)
- **Linux Ubuntu 24.04 LTS** (`.bin`)

Just download and run the correct version for your platform.  
On Linux, mark the binary as executable first:
```bash
chmod +x Galaksija_HRES_Maker_Linux.bin
./Galaksija_HRES_Maker_Linux.bin
```
## Installation (Linux/macOS/Windows, from source)
Make sure you have **Python 3.8+** installed.  

Required dependencies:
```bash
pip install pillow numpy
```

On Linux you also need Tkinter development libraries for the GUI:
```bash
sudo apt install python3-tk python3-pil.imagetk
```

Clone the repository:
```bash
git clone https://github.com/miladinovic/galaksija.git
cd galaksija/hires_maker
```

Or download as ZIP file:  
https://github.com/miladinovic/galaksija/archive/refs/heads/main.zip

## Running
### GUI
```bash
python gal_hres_gui.py
```
- **Open Image…** — load PNG/JPG/etc.
- **Dither** — choose algorithm
- **Threshold** — slider; pair with Invert for negative effect
- **Vertical separators** — draw 2×3 tile guides in the preview
- **Generate GTP…** — injects current 2 KB stream into a template and saves `.gtp`
- **Reset** — restore defaults (threshold, dither, zoom/pan, options)

Mouse: drag to pan; wheel to zoom

### CLI
Basic example:
```bash
python gal_hres_gui.py   --image in.jpg   --out out.gtp   --template G40   --dither "Tile 2×3"   --threshold 140   --preview preview.png   --vlines
```

Options:
- `--image PATH` — input image
- `--out PATH` — output `.gtp`
- `--template {G40,ORG}` — which template to use
- `--dither {Threshold,"Tile 2×3",Floyd–Steinberg,"Ordered 8×8","Halftone 45°","Halftone 90°","Stucki","Atkinson"}`
- `--threshold INT` — cut-off for Threshold/Floyd/Ordered/Halftone
- `--invert` — invert before dithering
- `--vlines` — draw vertical tile lines on preview PNG
- `--preview PATH` — save a 256×192 preview PNG

Run without arguments to start the GUI.

## How It Works
1. **Crop & scale**: Center crop to 4:3 → resize to 256×192 grayscale
2. **Dither**: Apply algorithm (Tile 2×3 computes mean → fills 0–6 dots)
3. **Shrink**: Downsample to 64×192 dots
4. **Pack tiles**: Each 2×3 tile → 6 bits; encoded with `0xC0` prefix
5. **Transpose**: Arrange as 64×32 transposed tiles → 2048 bytes total
6. **Inject**: Write 2 KB stream at offset 743 inside `.GTP` template; recompute checksum

Reference: [High resolution graphics on Galaksija (archived)](https://web.archive.org/web/20221228104800/https://www.tablix.org/~avian/blog/archives/2009/01/high_resolution_graphics_on_galaksija/)

## Why IM2 and How the Trick Works
On Z80 machines, **Interrupt Mode 2 (IM 2)** allows vectoring via a programmable table.  
On Galaksija, a similar solution is used for video fetch. This requires ~260 bytes for the vector **trampoline**, placed in memory previously reserved for the framebuffer.  
The trampoline feeds the high-resolution video routine while still respecting the Z80’s IM2 logic.

- Extra reading: [Z80 Interrupts (Spectrum FAQ)](https://rk.nvg.ntnu.no/sinclair/faq/tech_z80.html#INTERRUPTS)


## Dithering Details
- **Threshold**: direct binarization (with optional invert)
- **Floyd–Steinberg**: error-diffusion (7/16, 3/16, 5/16, 1/16)
- **Ordered 8×8**: Bayer matrix; good for flat regions
- **Halftone 45°/90°**: rotated halftone matrices, CRT-like look
- **Stucki**: finer error diffusion, smoother than Floyd
- **Atkinson**: softer error diffusion, classic Macintosh style
- **Tile 2×3 (levels)**: per-tile mean → 0–6 dots; vertical fill order matches on-screen geometry
- **Dot (DICT)**: maps directly to the C0–FF tile dictionary
- **Full ASCII**: uses entire dictionary including C0–FF

## Quick Start
Run with sample image:
```bash
python gal_hres_gui.py --image img/gkid.png --out out.gtp --preview preview.png --dither "Tile 2×3" --threshold 140 --vlines
```

Tips:
- Use high-contrast images for best results
- Try Tile 2×3 for photos, Ordered/Halftone for logos/text
- Use Dot (DICT) mode for maximum hardware fidelity

## Author
**Aleksandar Miladinović**  
📧 miladinovic@blu.it
