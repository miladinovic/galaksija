# Galaksija High-Resolution Maker (hires_maker)

Turn any image into a 2 KB graphics stream for the Yugoslav 8-bit computer **Galaksija**. The app ships with several dithering modes tailored to Galaksija’s **2×3-dot tile raster**.

This tool targets enthusiasts working with real hardware or emulators that support **Tomaz Šolc’s high-resolution hires routine**.

## Features
- Live preview GUI (pan/zoom with mouse wheel + drag)
- Dithering modes:
  - Threshold (with adjustable slider)
  - Tile 2×3 (levels) — mimics Galaksija’s native tile layout
  - Floyd–Steinberg
  - Ordered 8×8 (Bayer)
  - Halftone 45° / 90°
- Threshold slider + Invert checkbox
- Level correction sliders (black/white/midpoint)
- Vertical separators overlay (to see 2×3 tile boundaries)
- Template injection into two `.GTP` variants (Galaksija 40 and Original) with automatic checksum fixup
- Background worker keeps UI responsive while rendering and encoding

## Examples

Original → Processed preview → Display on Galaksija

<img src="img/gkidorg.png?raw=true" alt="Logo" width=320/>
Izvor: "Računari u vašoj kući" br. 1, jan. 1984



**Dithering Ordered 8×8**

<img src="img/gkid1sc.png?raw=true" alt="Logo" height=420/>

Result on Galaksija

![On Galaksija 1](img/gkid1.png?raw=true)

**No Dithering**

<img src="img/gkid2sc.png?raw=true" alt="Logo" height=420/>

Result on Galaksija

![On Galaksija 2](img/gkid2.png?raw=true)

## Installation
```bash
pip install pillow numpy
```

Clone the repository:
```bash
git clone https://github.com/miladinovic/galaksija.git
cd galaksija/hires_maker
```

Or download as ZIP file:
https://github.com/miladinovic/galaksija/archive/refs/heads/main.zip

## GUI Usage
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

## CLI Usage
Basic example:
```bash
python gal_hres_gui.py \
  --image in.jpg \
  --out out.gtp \
  --template G40 \
  --dither "Tile 2×3" \
  --threshold 140 \
  --preview preview.png \
  --vlines
```

Options:
- `--image PATH` — input image
- `--out PATH` — output `.gtp`
- `--template {G40,ORG}` — which template to use
- `--dither {Threshold,"Tile 2×3",Floyd–Steinberg,"Ordered 8×8","Halftone 45°","Halftone 90°"}`
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
On Z80 machines, **Interrupt Mode 2 (IM 2)** allows vectoring via a programmable table. From the Spectrum FAQ:

> “The other mode that is commonly used on the Spectrum is IM 2. In IM 2, the processor builds the interrupt vector by taking I as the high byte, while the interrupting device effectively supplies the low byte via the data bus. The normal Spectrum **contains no hardware to place a byte on the bus**, and the bus will therefore always read **FF** (because the ULA also doesn't read the screen if it generates an interrupt), so the resulting index address is 256*I+255. However, some not-so-neat hardware devices put things on the data bus when they shouldn't, so later programs didn't assume the low index byte was FF. These programs contain a 257 byte table of equal bytes starting at 256*I, and the interrupt routine is placed at an address that is a multiple of 257. A useful but not so much used trick on the Spectrum is to make the table contain FF's (or use the ROM for this) and put a byte 18 hex, the opcode for JR, at FFFF. The first byte of the ROM is a DI, F3 hex, so the JR will jump to FFF4, where a long JP to the actual interrupt routine is put.”

On Galaksija, a similar solution is used for video fetch. This requires ~260 bytes for the vector **trampoline**, placed in memory previously reserved for the framebuffer.

- Extra reading: [Z80 Interrupts (Spectrum FAQ)](https://rk.nvg.ntnu.no/sinclair/faq/tech_z80.html#INTERRUPTS)

## Dithering Details
- **Threshold**: direct binarization (with optional invert)
- **Floyd–Steinberg**: error-diffusion (7/16, 3/16, 5/16, 1/16)
- **Ordered 8×8**: Bayer matrix; good for flat regions
- **Halftone 45°/90°**: rotated halftone matrices, CRT-like look
- **Tile 2×3 (levels)**: per-tile mean → 0–6 dots; vertical fill order matches on-screen geometry

## Quick Start
Run with sample image:
```bash
python gal_hres_gui.py --image img/gkid.png --out out.gtp --preview preview.png --dither "Tile 2×3" --threshold 140 --vlines
```

Tips:
- Use high-contrast images for best results
- Try Tile 2×3 for photos, Ordered/Halftone for logos/text

## Credits
- **Tomaž Šolc** — original Galaksija IM2 routine and article
- **Community** resources on Z80 IM2 & Spectrum interrupts
- **Galaksija** preservation projects
