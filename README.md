# Galaksija

Open-source tools, notes, and demos for the **Galaksija** home computer (1983, Yugoslavia). This monorepo hosts multiple subprojects

## Subprojects

- **[`hires_maker app`](./hires_maker/)** — Python/Tk app and CLI that:
- crops/zooms to 4:3
- supports multiple dithers (threshold, ordered, Floyd–Steinberg, halftones)
- provides a Galaksija-style **Tile 2×3 “levels”** mode
  - generates a 2 KB binary stream and injects it into your chosen GTP template
- **[`hires_org_source`](./hires_org_source/)** — original disassembled and commented Galaksija hi-res IM2 driver source with build instructions
- **[`gal_gtp_builder`](./gal_gtp_builder/)** — script to build Galaksija `.GTP` files from Z80 binaries
- **[`gal_tapetool`](./gal_tapetool/)** — bidirectional converter between `.GTP` (tape images) and `.WAV` (tape audio) 

## License

- Code in this repository is provided under the MIT License (unless noted).
- Linked articles retain their original copyrights.

## Acknowledgments

- Tomaž Šolc for the pioneering Galaksija high-res work and documentation.  [1](https://web.archive.org/web/20221228104800/https%3A//www.tablix.org/~avian/blog/archives/2009/01/high_resolution_graphics_on_galaksija/)
- The Sinclair FAQ for a clear explanation of Z80 interrupt modes.  [2](https://rk.nvg.ntnu.no/sinclair/faq/tech_z80.html)
