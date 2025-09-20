# Galaksija Hi-Res IM2 Driver (original)

**Author:** Tomaž Šolc  
**Disassembled, modified and commented by:** Aleksandar Miladinović (University of Trieste, Trieste/Trst, Italy) — <miladinovic@blu.it>

This folder contains a cleaned, commented, **label-based rebuild** of the classic Galaksija hi-resolution graphics driver that uses **Interrupt Mode 2 (IM2)** and a cycle-counted ISR to draw pseudo-hires scanlines.

The source preserves the original timing and binary layout where it matters, but replaces hardcoded numeric addresses with symbols so the code is easier to maintain. Optional features like the “snow” sparkle can be toggled at assemble time. Vertical alignment is configurable for better compatibility across different Galaksijas.


---

## Files

- **`hires_orig.asm`** — main source (IM2 setup, ISR, stream decoder, BASIC trampoline, messages).
- **`image.bin`** — raw picture data included by the driver (unchanged from the original).
---

## Build

You can build this with **z80asm** (standalone) or **zcc (z88dk)**. The source has a small switch for z88dk CRT behavior.


### 1) Build with `zcc` (z88dk download: https://github.com/z88dk/z88dk/releases ) - Easiest way 

```sh
cd galaksija/hires_org_source
zcc +gal -create-app -o hires hires_orig.asm
```

- z88dk’s CRT inserts a short prologue. The source handles this with a `Z88DK` switch and adjusts the BASIC trampoline to call `USR(&2C3A+10)` automatically.
- Output is a Galaksija app you can load and `RUN`.

### 2) Build with `z80asm` or similar Z80 compiler

```sh
cd galaksija/hires_org_source

# Assemble a flat binary
z80asm -o out.bin hires_orig.asm

# If you use a GTP builder **[`gal_gtp_builder`](./gal_gtp_builder/)**:
python3 ../build_gtp.py --bin out.bin --out hires.gtp
```

- The embedded BASIC line calls `USR(&2C3A)` by default (no CRT prologue).
- Run by loading the GTP and typing `RUN` in Galaksija BASIC.

---

## Configuration (assemble-time)

Open `hires_orig.asm` and check these symbols near the top:

```asm
; --- IM2 vector configuration ---
IM2_PAGE:         equ 028h            ; I register page for IM2 (table at 0x28xx)
IM2_VECTOR_BYTE:  equ 029h            ; byte written across 0x28xx table
IM2_TABLE:        equ (IM2_PAGE * 256)
IM2_VECTOR_PTR:   equ (IM2_VECTOR_BYTE * 256 + IM2_VECTOR_BYTE)

; --- Video/scanline seeds ---
VRAM_BASE:        equ 03800h          ; start of hi-res framebuffer
SCAN_INIT_HL:     equ 02038h          ; HL seed used by ISR
SCAN_INIT_DE:     equ 0387Fh          ; DE seed used by ISR

; --- System hooks & runtime switches ---
SYS_KBD_STATUS:   equ 0201Fh          ; key status byte
SYS_TIMING_PARAM: equ 02BA8h          ; vertical timing parameter (BASIC: BYTE &2BA8,n)
ENABLE_SNOW:      equ 1               ; 1 = sparkle effect on, 0 = off
VERT_DELAY:       equ 35              ; default vertical offset (works well on many machines)
VERT_DELAY_ORG:   equ 12              ; original value restored on exit to BASIC

; z88dk compatibility (set to 1 when building with zcc)
Z88DK:            EQU 1               ; or EQU 0 for plain z80asm
```

### Important knobs

- **`VERT_DELAY`** — vertical alignment of the image. Equivalent to `BYTE &2BA8,n` from BASIC.  
  If your display is shifted up/down, adjust this value (typical range ≈ 10–40).
- **`ENABLE_SNOW`** — toggles the intentional “sprinkle” byte that creates a snow/shine visual.  
  Set to `0` to disable without touching timing.
- **`Z88DK`** — when set to `1`, the BASIC trampoline inside the ROM copy uses `USR(&2C3A+10)` to account for the CRT’s small prologue. With `0`, it uses `USR(&2C3A)`.

---

## How it works (quick tour)

- **IM2 setup**  
  The code fills the 0x2800–0x29FF table with a constant byte and writes a `JP isr_entry` at vector `0x2929`. Then it sets `I = 0x28` and enables `IM 2`. From then on, interrupts jump straight to our ISR.

- **Trampoline (BASIC line)**  
  A tiny BASIC line is stored in `rom_copy_src` and copied down into RAM. The addresses at `0x2C36` and `0x2C38` are automatically set to the **start of the BASIC line** and the **first byte after the 0x0D** respectively, so `RUN` will execute:
  - `1 A=USR(&2C3A)` for plain `z80asm`, or
  - `1 A=USR(&2C3A+10)` for `zcc`, depending on the `Z88DK` switch.

- **ISR (Interrupt Mode 2)**  
  The ISR preserves registers, performs a vertical timing wait based on `SYS_TIMING_PARAM` (that’s your `VERT_DELAY`), and then runs a tight per-scanline loop that tickles `R`/`I` and writes timed bytes to VRAM. It exits with `RETI`.

- **Pads (NOP islands)**  
  The blocks of `NOP`s are carefully placed to keep **cycle timing exact** on each scanline. Don’t remove or compress these; the composition matters for stable video.

- **Snow effect**  
  The optional single-byte write in `poke_stream_to_fb` produces a light sparkle effect. It’s guard-toggled by `ENABLE_SNOW` without disturbing the timing.

---

## Running

1. Load the built image (`.gtp`) into your Galaksija (hardware or emulator).
2. From BASIC: `OLD`-->`RUN`.
3. The driver sets up IM2, shows the messages, and displays the image.  
   Press any key to exit back to BASIC. On exit, `SYS_TIMING_PARAM` is restored to `VERT_DELAY_ORG` to keep BASIC happy.

---

## Troubleshooting

- **Image shifted vertically**  
  Rebuild with a different `VERT_DELAY` (e.g. 28, 32, 36…). This maps to `BYTE &2BA8,n`.

- **Snow effect unwanted**  
  Set `ENABLE_SNOW` to `0` and re-assemble.

- **Crashes when built with zcc**  
  Make sure `Z88DK EQU 1` in the source so the BASIC trampoline uses `USR(&2C3A+10)`.

- **Timing glitches after editing**  
  Don’t change instruction sequencing or remove NOP pads in the ISR area. Labels are fine; instruction counts aren’t.

---

## Credits

- **Original:** Tomaz Solc  
- **Rebuild & commentary:** Aleksandar Miladinovic (University of Trieste, Trieste/Trst, Italy) — <miladinovic@blu.it>

If you fork or modify, keep credits and please document any timing changes in the README.

---

## License

Choose a license appropriate for your project. If you’re fine with permissive terms, add an MIT `LICENSE` at repo root. Otherwise detail your chosen license here.
