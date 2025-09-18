; ============================================================================
; Author: Tomaz Solc
; Disassembled, modified and commented by: 
; Aleksandar Miladinovic (University of Trieste, Trieste/Trst, Italy) 
; <miladinovic@blu.it>
;
; Galaksija Hi-Res IM2 Driver (readable, label-based)
; ----------------------------------------------------------------------------
; This source is a cleaned, commented reconstruction of the original
; `z80dasm` output. It keeps the binary layout compatible while removing
; hard-coded addresses in favor of symbols.
;
; IMPORTANT about the old `;2cxx` disassembly comments in the right margin:
;   • They reflect byte positions from the *original* dump and may no longer
;     be accurate if you add/remove code.  Logic is now label-driven so the
;     correctness does NOT depend on these offsets.
;   • Leave them as archaeological notes or delete them if you confuse you.
;
; Highlights
;   • IM2 vector table and ISR entry are bound by labels (no magic numbers).
;   • Vertical position is configured via VERT_DELAY (equivalent to
;     BASIC `BYTE &2BA8,n`).
;   • Optional "snow" (sprinkle) effect is controlled by ENABLE_SNOW.
;   • Messages stored as 0-terminated strings for use with ROM print.
;
; Call graph (high level)
;   _main -> init_im2_and_copy -> (copies ROM stub and seeds timing)
;         -> sets up IM2 and vector table -> enables IM2
;         -> main_idle_loop: decode_stream_and_blit forever
;
; ISR flow (IM2)
;   isr_entry -> small vertical wait using SYS_TIMING_PARAM
;              -> per-scanline loop (programs R, I and pokes VRAM)
;              -> exits with RETI
;
; Configuration knobs (see symbols below):
;   IM2_PAGE, IM2_VECTOR_BYTE, IM2_TABLE, IM2_VECTOR_PTR
;   VRAM_BASE, SCAN_INIT_HL, SCAN_INIT_DE
;   SYS_KBD_STATUS, SYS_TIMING_PARAM, ENABLE_SNOW, VERT_DELAY
; ============================================================================
Z88DK:  EQU 1 ; Define 1 for Z88DK assembly compatibility mode (zcc +gal -create-app -o out hres.asm)
; --- IM2 vector configuration -------------------------------------------------
IM2_PAGE: equ 028h  ; I register page for IM2

IM2_VECTOR_BYTE: equ 029h                 ; byte filled in 0x28xx table
IM2_TABLE: equ (IM2_PAGE * 256)     ; 0x2800 by default
IM2_VECTOR_PTR: equ (IM2_VECTOR_BYTE * 256 + IM2_VECTOR_BYTE) ; 0x2929

; --- Video/scanline seeds -----------------------------------------------------
VRAM_BASE: equ 03800h               ; start of hi-res framebuffer
SCAN_INIT_HL: equ 02038h              ; HL seed used by ISR
SCAN_INIT_DE: equ 0387Fh               ; DE seed used by ISR

; --- System hooks and runtime switches ---------------------------------------
SYS_KBD_STATUS: equ 0201Fh               ; key status byte
SYS_TIMING_PARAM: equ 02BA8h               ; timing parameter used by ISR
ENABLE_SNOW:     equ 1      ; set to 1 for sprinkle effect, 0 to disable
VERT_DELAY:       equ 35                 ; desired vertical timing value (what BYTE &2BA8,35 sets)
VERT_DELAY_ORG:       equ 12                 ; original vertical timing value for correct return to basic (what BYTE &2BA8,12 sets)
; -----------------------------------------------------------------------------

    org 02c3ah
IF Z88DK
PUBLIC _main
_main:
ENDIF
  call init_im2_and_copy
  di
  ld hl,IM2_TABLE
  ld d,IM2_VECTOR_BYTE
im2_vector_fill:
  ld (hl),d
  inc hl
  ld a,h
  and 001h
  jr z,im2_vector_fill
  ld (hl),d
  ld hl,IM2_VECTOR_PTR
  ld (hl),0c3h    ;2c4e ; opcode for JP nn in vector cell
  inc hl
    ld (hl), isr_entry & 0FFh        ; vector low  byte -> points to isr_entry
  inc hl                           ; advance to high byte cell
    ld (hl), isr_entry >> 8          ; vector high byte
  ld a,IM2_PAGE
  ld i,a
  im 2
  ei
main_idle_loop:
  call decode_stream_and_blit
  ld hl,SYS_KBD_STATUS
  ld a,(hl)
  and 001h
  jp nz,main_idle_loop
  im 1
  ld a,00ch
  rst 20h
  ld a, VERT_DELAY_ORG                 ; place back original vertical alignment (like BYTE &2BA8,n)
  ld (SYS_TIMING_PARAM), a
  ld de,MSG_0
  call 00937h ; print message
  ld de,MSG_1
  call 00937h ; print message
  ld de,MSG_2
  call 00937h ; print message
  ld de,MSG_3
  call 00937h ; print message
  jp 00066h
init_im2_and_copy:
  ld hl,BASIC_START
  ld (02c36h),hl      ; beginning of BASIC line (01h)
  ld hl,BASIC_END
  ld (02c38h),hl      ; first byte after 0Dh
  ld hl,rom_copy_src
  ld de,03fffh
  ; copy 0x800 bytes from rom_copy_src to 0x3800-1 (downwards)
  ld bc,00800h
  lddr                              ; copy 0x800 bytes from rom_copy_src to 0x3800-1 (downwards)
    ld a, VERT_DELAY                  ; program vertical alignment (like BYTE &2BA8,n)
    ld (SYS_TIMING_PARAM), a
  ret
isr_timing_slot_a:
  ld c,(hl)
  ld b,c
  ld c,h
  jr nz,isr_pad_a
  ld c,l
  ld b,c
  ld b,a
isr_timing_slot_b2:
  ld b,l
  jr nz,isr_pad_b
  ld d,d
  ld b,l
  ld b,h
  ld b,c
isr_timing_slot_b:
isr_setup_a:
  ld d,d
  ld d,h
  ld l,043h
  ld c,a
  ld c,l
  dec c
; ----------------------------------------------------------------------------
; isr_entry: IM2 interrupt service routine
;   • Preserves AF/BC/DE/HL
;   • Waits vertically based on SYS_TIMING_PARAM (tunes image Y position)
;   • Outputs three timing bytes per scanline into VRAM (via (hl))
;   • Uses I and R registers to steer the hardware timings
; ----------------------------------------------------------------------------
isr_entry:
  push af
isr_entry_pushbc:
  push bc
  push de
isr_entry_pushhl:
  push hl
  ld b,00ah
isr_vert_delay_loop:
  nop
  nop
  ld a,i
  ld a,00ah
isr_spin_deca:
  dec a
  jr nz,isr_spin_deca
  djnz isr_vert_delay_loop
  nop
  ld a,(SYS_TIMING_PARAM)
  sub 003h
  rra
  jr c,isr_small_wait
isr_small_wait:                        ; spin for A ticks (derived from SYS_TIMING_PARAM)
  dec a
  jr nz,isr_small_wait
  ld hl,SCAN_INIT_HL
  ld de,SCAN_INIT_DE
  ld a,d
  ld i,a
; --- Per-scanline timing core: updates R/I, pokes two bytes, computes next HL/DE ---
isr_scanline_loop:
  ld b,08ch
  ld c,080h
  ld a,e
  ld r,a
  ld (hl),b
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
isr_pad_a:
  nop
  nop
  nop
isr_pad_b:
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  ld (hl),c
  ld a,000h
  ld a,000h
  nop
  nop
  nop
  nop
  nop
  ld b,098h
  ld a,e
  ld r,a
  ld (hl),b
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  ld (hl),c
  ld a,000h
  ld a,000h
  nop
  nop
  nop
  nop
  nop
  ld b,0b0h
  ld a,e
  ld r,a
  ld (hl),b
  or a
  ld a,e
  rla
  inc a
  inc a
  rra
  ld e,a
  xor a
  ld b,a
  scf
  rra
  rra
  rra
  add a,e
  ld e,a
  ld a,b
  adc a,d
  ld d,a
  ld a,e
  rla
  dec a
  rra
  ld e,a
  or a
  ld a,h
  rla
  ld b,a
  rla
  nop
  nop
  nop
  ld (hl),a
  ld a,d
  ld i,a
  and b
  jp z,isr_scanline_loop
  ld a,IM2_PAGE
  ld i,a
  pop hl
  pop de
  pop bc
  pop af
  ei
  reti
; calc_fb_addr_from_xy: convert (B as row fragment, C as bit-packed X) -> HL address in hi-res VRAM
calc_fb_addr_from_xy:
  ld hl,VRAM_BASE
  xor a
  ld d,a
  ld e,003h
  rl c
  rla
  scf
  rl c
  rla
  scf
  rl c
  rla
  sub e
  jr nc,calc_step1_ok
  add a,e
calc_step1_ok:
  rl c
  rla
  sub e
  jr nc,calc_step2_ok
  add a,e
calc_step2_ok:
  rl c
  rla
  sub e
  jr nc,calc_step3_ok
  add a,e
calc_step3_ok:
  rl c
  rla
  sub e
  jr nc,calc_step4_ok
  add a,e
calc_step4_ok:
  rl c
  rla
  sub e
  jr nc,calc_step5_ok
  add a,e
calc_step5_ok:
  rl c
  rla
  sub e
  jr nc,calc_step6_ok
  add a,e
calc_step6_ok:
  rl c
  ex af,af'
  ld a,c
  cpl
  rlca
  rla
  rla
  rl d
  rla
  rl d
  rla
  rl d
  ld e,a
  add hl,de
  ex af,af'
  ld e,b
  ld b,a
  inc b
  ld a,040h
calc_shift_loop:
  rlca
  rlca
  djnz calc_shift_loop
  ld d,b
  srl e
  srl e
  srl e
  jr nc,calc_final_add
  rlca
calc_final_add:
  add hl,de
  ret
; ----------------------------------------------------------------------------
; poke_stream_to_fb
;   Input: HL -> stream cursor (A,B,C taken from stream by caller)
;          B  = merged attribute from stream (used as temp
;          C  = X coordinate byte (bit-packed)
;          A  = sprinkle byte (optional visual noise when ENABLE_SNOW=1)
;   Effect: computes VRAM address from (B,C) and stores two bytes, with
;           optional single-byte sprinkle write controlled by ENABLE_SNOW.
; ----------------------------------------------------------------------------
poke_stream_to_fb:
    
  push hl
  call calc_fb_addr_from_xy
  ld b,(hl)
  ex (sp),hl
  ld (hl),b
  inc hl
  or b
  ex de,hl
  pop hl
IF ENABLE_SNOW
    ld (hl),a            ;2e43  ; sprinkle write enabled
ELSE
    nop                  ;2e43  ; sprinkle disabled
ENDIF
  ex de,hl
  ld (hl),e
  inc hl
  ld (hl),d
  inc hl
  ret
draw_table_stream:
  nop
  add a,b
  ld bc,00006h
  nop
  nop
  nop
  ld (bc),a
  ld a,c
  ld bc,000a6h
  nop
  nop
  nop
  ld bc,001c0h
  adc a,d
  nop
  nop
  nop
  nop
  nop
  ex af,af'
  ld bc,00005h
  nop
  nop
  nop
  ld (bc),a
  ld l,c
  ld bc,0004bh
  nop
  nop
  nop
  ld bc,0014fh
  ld l,d
  nop
  nop
  nop
  nop
  ld bc,001fah
  jr z,draw_table_here
draw_table_here:
  nop
  nop
  nop
  nop
  pop af
  ld bc,000a6h
  nop
  nop
  nop
  ld bc,0011ah
  sbc a,e
  nop
  nop
  nop
  nop
  nop
  push de
  ld bc,0009eh
  nop
  nop
  nop
  ld (bc),a
  ld l,l
  ld bc,0003dh
  nop
  nop
  nop
  ld (bc),a
  sbc a,b
  ld bc,00072h
  nop
  nop
  nop
  ld (bc),a
  and e
  ld bc,0006fh
  nop
  nop
  nop
  ld (bc),a
  ld (hl),e
  ld bc,00026h
  nop
  nop
  nop
  ld bc,001e2h
  ld l,b
  nop
  nop
  nop
  nop
  ld bc,001d4h
  ld a,h
  nop
  nop
  nop
  nop
  ld bc,00101h
  sbc a,b
  nop
  nop
  nop
  nop
  ld (bc),a
  call p,09901h
  nop
  nop
  nop
  nop
  ld bc,00190h
  ld c,b
  nop
  nop
  nop
  nop
  ld (bc),a
  cp c
  ld bc,00008h
  nop
  nop
  nop
decode_stream_and_blit:
  ld hl,draw_table_stream
  ld b,014h
decode_loop:
  push bc
  ld a,(hl)
  inc hl
  ld b,(hl)
  add a,b
  cp 0ffh
  jr c,decode_a_ok
  xor a
decode_a_ok:
  ld b,a
  ld (hl),b
  inc hl
  ld a,(hl)
  inc hl
  ld c,(hl)
  add a,c
  cp 0bfh
  jr c,decode_c_ok
  xor a
decode_c_ok:
  ld c,a
  ld (hl),c
  inc hl
  call poke_stream_to_fb
  inc hl
  pop bc
  djnz decode_loop
  halt
  ld b,014h
  dec hl
  dec hl
decode_copyback_loop:
  ld d,(hl)
  dec hl
  ld e,(hl)
  dec hl
  ld a,(hl)
  ld (de),a
  ld de,0fffah
  add hl,de
  djnz decode_copyback_loop
  ret
;defs 2048, 0C1h    ;
incbin "image.bin"

rom_copy_src:
BASIC_START:
  ; BASIC: 1 A=USR(&xxxx) + CR
  ; BYTES: 01 00 41 3D 55 53 52 28 26 32 43 >>3x<< 41 29 0D
  db 01h,00h,041h,03Dh,055h,053h,052h,028h,026h,032h,043h
IF Z88DK
  db 034h ; A=USR(&2C4A) for Z88DK compatibility due to CRT header (+10 bytes)
ELSE
  db 033h ; A=USR(&2C3A) for other assemblers i.e. z80asm
ENDIF
  db 041h,029h,00Dh
BASIC_END:
  ret nz
  ld bc,04100h
  dec a
  ld d,l
  ld d,e
  ld d,d
  jr z,$+40
  ld (03343h),a
  ld b,c
  add hl,hl
  dec c
  dec bc
; ============================================================================
; Messages (0-terminated, for ROM print routine at 0x0937)
; ============================================================================
MSG_0:  DB "GALAKSIJA PSEDUO-HIGH RESOLUTION================================AUTHOR: TOMA] ^OLC, JAN 2009     ",13,0
MSG_1:  DB "DISASSEMBLED, MODIFIED AND",13,0
MSG_2:  DB "COMMENTED BY:                     ",13,0
MSG_3:  DB "ALEKSANDAR MILADINOVI\\,         UNIV. TRIESTE/TRST ITALY,       SEP 2025",13,0
