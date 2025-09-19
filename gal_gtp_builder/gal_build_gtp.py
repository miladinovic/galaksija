#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Build a Galaksija .GTP file from a flat Z80 binary (and optional BASIC tail).

Author: Aleksandar Miladinovic (miladinovic@blu.it) September 2025

File format (as implemented here):

  [00]
  [len_lo len_hi]                 # length of everything that follows (from the two 00s up to the final byte)
  [00 00]
  [A5]
  [load_lo load_hi]
  [endp1_lo endp1_hi]             # end address + 1 (first free)
  [payload bytes ...]             # If BASIC present: [basic_start][basic_end+1][machine code][BASIC]; else: [machine code]
  [checksum]                      # 0xFF - (sum(bytes from A5 .. byte before checksum) & 0xFF)
  [00]                            # trailing terminator

Usage examples:
  python build_gtp.py --bin out.bin --out out.gtp
  # Default: BASIC tail on, block starts at 0x2C36, code at 0x2C3A
  # No BASIC (code only) starting at 0x2C3A by default:
  python build_gtp.py --bin out.bin --out out.gtp --no-basic

  # Also write a WAV (Tomaz Šolc timings):
  python build_gtp.py --bin out.bin --out out.gtp --wav out.wav
"""

from pathlib import Path
import argparse
import math
import wave
import struct

A5 = 0xA5

def u16le(x: int) -> bytes:
    return bytes((x & 0xFF, (x >> 8) & 0xFF))

def compute_checksum(a5_and_after: bytes) -> int:
    """
    Checksum is computed over bytes from A5 up to (but not including) the checksum byte.
    Here we pass the slice starting at A5 through the byte before checksum.
    """
    s = sum(a5_and_after) & 0xFF
    return (0xFF - s) & 0xFF

def build_basic_tail_from_text(text: str) -> bytes:
    """
    Galaksija BASIC ASCII tail: raw ASCII with CR (0x0D) at end.
    You can pass something like: '10 A=USR(&2C3A)'
    We'll ensure it ends with CR. No tokenization is done (Galaksija stores ASCII).
    """
    b = text.encode("ascii", errors="strict")
    if not b.endswith(b"\r"):
        b += b"\r"
    return b

def build_default_basic_tail(usr_addr: int, line_no: int = 1) -> bytes:
    """
    Default BASIC tail with binary line header:
      [line_lo line_hi] + ASCII("A=USR(&" + UPPERCASE_HEX(usr_addr, 4) + ")") + 0x0D
    Example (usr=0x2C3A): 01 00 41 3D 55 53 52 28 26 32 43 33 41 29 0D
    """
    line_lo = line_no & 0xFF
    line_hi = (line_no >> 8) & 0xFF
    hex4 = "{0:04X}".format(usr_addr).upper().encode("ascii")
    return bytes([line_lo, line_hi]) + b"A=USR(&" + hex4 + b")\r"

def build_gtp(bin_bytes: bytes, load_addr: int, basic_tail: bytes) -> bytes:
    """
    Construct a full .GTP file with the mandatory pre-A5 header,
    short or long header (depending on BASIC presence), payload,
    checksum, and trailing 0x00.
    """
    # Build payload
    if basic_tail:
        # PAYLOAD = [basic_start][basic_end+1][compiled_code][basic_tail]
        # basic_start points to the first byte of the basic tail (0x01 of line header)
        # Addresses are relative to memory start (load_addr)
        basic_start = load_addr + 4 + len(bin_bytes)
        basic_endp1 = basic_start + len(basic_tail)

        payload = bytearray()
        payload += u16le(basic_start)
        payload += u16le(basic_endp1)
        payload += bin_bytes
        payload += basic_tail
        endp1_after_all = load_addr + len(payload)
    else:
        # No BASIC: payload is just the machine code
        payload = bytearray(bin_bytes)
        endp1_after_all = load_addr + len(payload)

    # Build the A5..body (everything from A5 up to but not including checksum and final 0x00)
    a5_section = bytearray()
    a5_section.append(A5)
    a5_section += u16le(load_addr)
    a5_section += u16le(endp1_after_all)

    a5_section += payload

    # Compute checksum over A5..(last payload byte)
    chk = compute_checksum(bytes(a5_section))

    # Now build the full file:
    out = bytearray()
    out.append(0x00)

    # Length is of the block starting at the two 0x00s prior to A5 and ending with the final 0x00
    # That block is: [00 00][A5 ... payload][chk][00]
    # So length = 2 + len(a5_section) + 1 + 1
    block_len = 2 + len(a5_section) + 1 + 1
    out += u16le(block_len)

    # The two 0x00 bytes before A5
    out += b"\x00\x00"

    # A5 section
    out += a5_section

    # Checksum and final
    out.append(chk)
    out.append(0x00)

    return bytes(out)

# ---------- WAV synth from GTP (Tomaz Šolc timings) ----------
PULSE_WIDTH_MS      = 0.6
PERIOD_BASE_MS      = 3.0
PERIOD_0_MS         = PERIOD_BASE_MS
PERIOD_1_MS         = PERIOD_BASE_MS/2.0
INTERBYTE_PAUSE_MS  = 4.5
INTERBLOCK_PAUSE_MS = 2000.0
SYNCBYTES           = 100

def _ms_to_samples(ms: float, sr: int) -> int:
    return max(1, int(round(ms * 1e-3 * sr)))

def _wav_write_mono(path: Path, sr: int, x: bytes, bits: int = 16):
    # x is int16 PCM bytes
    with wave.open(str(path), 'wb') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2 if bits == 16 else 1)
        wf.setframerate(sr)
        wf.writeframes(x)

class _TapeSynth:
    def __init__(self, sr: int, bits: int, amp: float = 1.0):
        self.sr = sr
        self.bits = bits
        self.amp = float(max(0.0, min(1.0, amp)))
        self.buf = []  # float64 samples in [-1,1]

    def _impulse(self, value: float, ms: float):
        n = _ms_to_samples(ms, self.sr)
        if n > 0:
            self.buf.extend([value] * n)

    def interbyte_pause(self):   self._impulse(0.0, INTERBYTE_PAUSE_MS)
    def interblock_pause(self):  self._impulse(0.0, INTERBLOCK_PAUSE_MS)

    def _pulse_train(self, period_ms: float):
        self._impulse(-1.0, PULSE_WIDTH_MS)
        self._impulse( 1.0, PULSE_WIDTH_MS)
        rem = max(0.0, period_ms - 2.0*PULSE_WIDTH_MS)
        self._impulse(0.0, rem)

    def bit0(self): self._pulse_train(PERIOD_0_MS)
    def bit1(self): self._pulse_train(PERIOD_1_MS); self._pulse_train(PERIOD_1_MS)

    def byte(self, b: int):
        for i in range(8):
            if (b >> i) & 1: self.bit1()
            else:            self.bit0()

    def leader(self, nbytes: int = SYNCBYTES):
        for i in range(nbytes):
            if i: self.interbyte_pause()
            self.byte(0x00)

    def block(self, data: bytes):
        for i, b in enumerate(data):
            if i: self.interbyte_pause()
            self.byte(b)

    def render_pcm16(self) -> bytes:
        import numpy as _np
        x = _np.array(self.buf, dtype=_np.float64)
        x = _np.clip(x * self.amp, -1.0, 1.0)
        return (_np.round(x * 32767.0).astype(_np.int16)).tobytes()

def gtp_to_wav_pcm(gtp_bytes: bytes, sr: int = 44100, bits: int = 16, amp: float = 0.95) -> bytes:
    ts = _TapeSynth(sr, bits, amp)
    ts.interblock_pause()
    ts.leader(SYNCBYTES)
    ts.interbyte_pause()
    ts.block(gtp_bytes)
    ts.interblock_pause()
    return ts.render_pcm16()

def save_wav_from_gtp(gtp_bytes: bytes, out_path: Path, sr: int = 44100, bits: int = 16, amp: float = 0.95):
    pcm = gtp_to_wav_pcm(gtp_bytes, sr=sr, bits=bits, amp=amp)
    _wav_write_mono(out_path, sr, pcm, bits=bits)

def main():
    ap = argparse.ArgumentParser(description="Build a Galaksija .GTP from a flat Z80 binary.")
    ap.add_argument("--bin", required=True, type=Path, help="Input flat Z80 binary (e.g. out.bin)")
    ap.add_argument("--out", required=True, type=Path, help="Output .gtp file")
    ap.add_argument("--load", type=lambda s:int(s,0), default=0x2C36,
                    help="Load address for block start (default: 0x2C36 when BASIC tail is present)")
    ap.add_argument("--usr",  type=lambda s:int(s,0), default=0x2C3A,
                    help="Code start address / USR address (default: 0x2C3A)")
    ap.add_argument("--basic", type=str,
                    help="Optional BASIC ASCII line(s) to append (e.g. '10 A=USR(&2C3A)'); "
                         "Carriage return will be added automatically.")
    ap.add_argument("--basic-file", type=Path,
                    help="Optional file containing BASIC ASCII to append (raw ASCII; will add CR if missing).")
    ap.add_argument("--basic-auto", action="store_true",
                    help="Append a default BASIC line '10 A=USR(&XXXX)' using --usr address.")
    ap.add_argument("--no-basic", action="store_true",
                    help="Do not append BASIC tail; load only machine code starting at --usr (default 0x2C3A)")
    ap.add_argument("--wav", type=Path,
                    help="Optional path to also export an audio .wav using Tomaz Šolc timings")
    args = ap.parse_args()

    # Read the BIN
    with open(str(args.bin), "rb") as f:
        bin_data = f.read()

    # Prepare BASIC tail (precedence: --basic-file > --basic > --basic-auto > default)
    basic_tail = None
    if args.basic_file:
        with open(str(args.basic_file), "rb") as f:
            b = f.read()
        if not b.endswith(b"\r"):
            b += b"\r"
        basic_tail = b
    elif args.basic:
        basic_tail = build_basic_tail_from_text(args.basic)
    elif args.basic_auto:
        basic_tail = build_basic_tail_from_text("10 A=USR(&{0:04X})".format(args.usr))
    else:
        basic_tail = build_default_basic_tail(args.usr)

    # Build payload according to mode
    if args.no_basic:
        # No BASIC: load only code at --usr
        load_addr = int(args.usr)
        bin_for_payload = bin_data  # no pointers, no padding, no BASIC
        tail = None
    else:
        # With BASIC: start at --load (default 0x2C36), pointers first, then optional padding up to --usr, then code, then BASIC
        load_addr = int(args.load)
        code_start_min = load_addr + 4
        usr_addr = int(args.usr)
        if usr_addr < code_start_min:
            raise SystemExit("--usr must be >= load+4 (0x{0:04X})".format(code_start_min))
        pad_len = usr_addr - code_start_min
        if pad_len > 0:
            bin_for_payload = b"\x00" * pad_len + bin_data
        else:
            bin_for_payload = bin_data
        tail = basic_tail  # default or provided

    # Build
    gtp = build_gtp(bin_for_payload, load_addr, tail)

    # Write
    with open(str(args.out), "wb") as f:
        f.write(gtp)

    # Report
    total_len = len(gtp)
    print("[OK] Wrote {} ({} bytes)".format(args.out, total_len))
    if args.no_basic:
        print("     Mode: no BASIC; Start=0x{0:04X}, Code size={1}".format(int(args.usr), len(bin_data)))
    else:
        code_start_min = int(args.load) + 4
        usr_addr = int(args.usr)
        pad_len = max(0, usr_addr - code_start_min)
        print("     Mode: BASIC; Start=0x{0:04X}, Code start=0x{1:04X}, Pad={2}, Code size={3}".format(int(args.load), usr_addr, pad_len, len(bin_data)))
        print("     BASIC tail length={}".format(len(basic_tail)))
    # Quick peek at header fields:
    print("     Header: 00, len={} bytes, 00 00, A5 at offset 5, checksum 0x{:02X}".format(gtp[1] | (gtp[2]<<8), gtp[-2]))

    # Optional WAV export of the exact .GTP bytes (Tomaz Šolc timings)
    if args.wav:
        save_wav_from_gtp(gtp, args.wav, sr=44100, bits=16, amp=0.95)
        print("     WAV: wrote {} (Tomaz Šolc timings, 44100 Hz, 16-bit)".format(args.wav))

if __name__ == "__main__":
    main()
