# Galaksija

Open-source tools, notes, and demos for the **Galaksija** home computer (1983, Yugoslavia).  
This monorepo hosts multiple subprojects — the first is **`hires_maker`**, a GUI + CLI pipeline to convert modern images into the 2 KB IM2 stream used by Tomaž Šolc’s high-resolution video driver and then inject that stream into `.gtp` tapes ready for loading on real hardware.

## What’s inside

- **[`hires_maker`](./hires_maker/)** — Python/Tk app and CLI that:
- crops/zooms to 4:3
- supports multiple dithers (threshold, ordered, Floyd–Steinberg, halftones)
- provides a Galaksija-style **Tile 2×3 “levels”** mode
  - optional **invert**, **vertical tile separators**, and **Reset to defaults**
  - generates a 2 KB IM2 stream and injects it into your chosen GTP template
  - generates a 2 KB binary stream and injects it into your chosen GTP template
- **[`hires_org_source`](./hires_org_source/)** — original disassembled and commented Galaksija hi-res IM2 driver source with build instructions
- **[`gal_gtp_builder`](./gal_gtp_builder/)** — script to build Galaksija `.GTP` files from Z80 binaries
- **[`gal_tapetool`](./gal_tapetool/)** — bidirectional converter between `.GTP` (tape images) and `.WAV` (tape audio) 

## Why this exists

Tomaž Šolc demonstrated a **64×192** “high-resolution” mode by driving video via Z80 **interrupt mode 2 (IM 2)** and timing, reading 3 scanlines per character row and packing pixels as 2×3 tiles (6 bits/byte) into a 2 KB framebuffer. See his excellent write-up for the architecture, memory map, and constraints.  [1]

Background on Z80 IM 2 (how the CPU gets a 16-bit vector from `I` + data bus and why machines like the ZX Spectrum used a vector table / bus tricks) is summarized in the classic Sinclair FAQ.  [2]

## Subprojects

- **[`hires_maker`](./hires_maker/)** — image→hres 2048KB image→GTP toolchain with live preview
- **[`hires_org_source`](./hires_org_source/)** — original disassembled and commented Galaksija hi-res IM2 driver source with build instructions
- **[`gal_gtp_builder`](./gal_gtp_builder/)** — CLI to wrap Z80 binaries into `.GTP` tapes (and optional experimental `.wav`)
- **[`gal_tapetool`](./gal_tapetool/)** — convert `.GTP` ↔ `.WAV` with debug, sync detection, and A5 wrapping

## License

- Code in this repository is provided under the MIT License (unless noted).
- Linked articles retain their original copyrights.

## Acknowledgments

- Tomaž Šolc for the pioneering Galaksija high-res work and documentation.  [1](https://web.archive.org/web/20221228104800/https%3A//www.tablix.org/~avian/blog/archives/2009/01/high_resolution_graphics_on_galaksija/)
- The Sinclair FAQ for a clear explanation of Z80 interrupt modes.  [2](https://rk.nvg.ntnu.no/sinclair/faq/tech_z80.html)
