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
import numpy as np
from scipy.io import wavfile

def _hexdump(b: bytes, width: int = 16) -> str:
    lines = []
    for i in range(0, len(b), width):
        chunk = b[i:i+width]
        hexpart = " ".join("{:02X}".format(x) for x in chunk)
        lines.append("{:04X}: {}".format(i, hexpart))
    return "\n".join(lines)

def _wrap_a5_to_gtp(a5_section: bytes) -> bytes:
    """
    Given a section that starts at 0xA5 (A5 .. [payload] .. [checksum?]),
    build a full GTP block: [00][len_lo len_hi][00 00][A5..][chk][00].
    If the provided a5_section is missing a checksum or it doesn't match,
    compute and append the proper checksum.
    """
    if not a5_section or a5_section[0] != 0xA5:
        raise ValueError("A5 section must start with 0xA5")
    # If last byte looks like checksum, validate; otherwise we'll recompute/append
    if len(a5_section) >= 6:
        chk_idx = len(a5_section) - 1
        s = sum(a5_section[0:chk_idx]) & 0xFF
        expected = (0xFF - s) & 0xFF
        has_valid_chk = (a5_section[chk_idx] == expected)
    else:
        has_valid_chk = False

    if not has_valid_chk:
        chk = compute_checksum(a5_section)
        a5_full = bytes(a5_section) + bytes((chk,))
    else:
        a5_full = bytes(a5_section)

    block_len = 2 + len(a5_full) + 1  # [00 00] + [A5..chk] + [00]
    out = bytearray()
    out.append(0x00)
    out += u16le(block_len)
    out += b"\x00\x00"
    out += a5_full
    out.append(0x00)
    return bytes(out)

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
WAV_DEFAULT_SR   = 44100
WAV_DEFAULT_BITS = 16

PULSE_WIDTH_MS      = 0.6
PERIOD_BASE_MS      = 3.0
PERIOD_0_MS         = PERIOD_BASE_MS
PERIOD_1_MS         = PERIOD_BASE_MS/2.0
INTERBYTE_PAUSE_MS  = 4.5
INTERBLOCK_PAUSE_MS = 2000.0
SYNCBYTES           = 100

def _ms_to_samples(ms: float, sr: int) -> int:
    return max(1, int(round(ms * 1e-3 * sr)))

def _wav_write_mono(path: Path, sr: int, x: np.ndarray, bits: int = 16):
    x = np.asarray(x, dtype=np.float64)
    x = np.clip(x, -1.0, 1.0)
    sampwidth = 2 if bits == 16 else 1
    if bits == 16:
        data = (x * 32767.0).astype(np.int16).tobytes()
    elif bits == 8:
        data = ((x * 127.0) + 128.0).astype(np.uint8).tobytes()
    else:
        raise ValueError("bits must be 8 or 16")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(sampwidth)
        w.setframerate(sr)
        w.writeframes(data)

class _TapeSynth:
    def __init__(self, sr: int, bits: int):
        self.sr = sr
        self.bits = bits
        self.buf = []

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

    def render(self) -> np.ndarray:
        return np.array(self.buf, dtype=np.float64)

def gtp_to_wav_bytes(gtp_bytes: bytes, sr: int = WAV_DEFAULT_SR, bits: int = WAV_DEFAULT_BITS) -> np.ndarray:
    ts = _TapeSynth(sr, bits)
    ts.interblock_pause()
    ts.leader(SYNCBYTES)
    ts.interbyte_pause()
    ts.block(gtp_bytes)
    ts.interblock_pause()
    return ts.render()

def save_wav_from_gtp(gtp_bytes: bytes, out_path: Path, sr: int = WAV_DEFAULT_SR, bits: int = WAV_DEFAULT_BITS):
    samples = gtp_to_wav_bytes(gtp_bytes, sr=sr, bits=bits)
    _wav_write_mono(out_path, sr, samples, bits=bits)


def _is_valid_gtp(buf: bytes) -> bool:
    # Must be at least 8 bytes header-ish + 2 trailers
    if len(buf) < 8:
        return False
    if buf[0] != 0x00:
        return False
    if len(buf) < 4:
        return False
    total_len = buf[1] | (buf[2] << 8)
    if total_len <= 0 or total_len > len(buf) - 1:
        return False
    if buf[3] != 0x00 or buf[4] != 0x00:
        return False
    if buf[5] != 0xA5:
        return False
    end_idx = 1 + total_len - 1  # last byte index of the described block
    if end_idx >= len(buf):
        return False
    # checksum is penultimate byte within the block: [ ... chk ][00]
    chk_idx = end_idx - 1
    a5_off = 5  # position of A5
    a5_slice = buf[a5_off:chk_idx]
    s = sum(a5_slice) & 0xFF
    expected = (0xFF - s) & 0xFF
    return buf[chk_idx] == expected and buf[end_idx] == 0x00

def _extract_first_valid_gtp_block(buf: bytes) -> bytes | None:
    # Fast path: already valid from start
    if _is_valid_gtp(buf):
        total_len = buf[1] | (buf[2] << 8)
        return buf[0:1+total_len]
    # Search for start 0x00 then 0x00 0x00 A5 pattern
    n = len(buf)
    i = 0
    while i + 6 < n:
        if buf[i] == 0x00 and i + 5 < n and buf[i+3] == 0x00 and buf[i+4] == 0x00 and buf[i+5] == 0xA5:
            cand = buf[i:]
            if _is_valid_gtp(cand):
                L = cand[1] | (cand[2] << 8)
                return cand[0:1+L]
        i += 1
    return None


def decode_pcm_bytes(
    filename,
    pulse_width_ms=0.6,
    period_0_ms=3.0,
    period_1_ms=1.5,
    interbyte_pause_ms=4.5,
    min_distance_factor=1.9,
    save_to=None
):
    """
    Decode PCM-encoded data from a WAV file.

    Parameters:
        filename (str): Path to input WAV file.
        pulse_width_ms (float): Approx pulse width (ms).
        period_0_ms (float): Bit-0 period (ms).
        period_1_ms (float): Bit-1 period (ms).
        interbyte_pause_ms (float): Gap between bytes (ms).
        min_distance_factor (float): Debounce multiplier for pulse detection.
        save_to (str or None): Optional filename to save decoded bytes.

    Returns:
        (sync_count, decoded_bytes, stats) where:
            sync_count: number of leading 0x00 sync bytes
            decoded_bytes: list of decoded byte values (ints) with sync removed
            stats: dict with samplerate, threshold, impulses, etc.
    """

    # Load WAV
    fs, data = wavfile.read(filename)
    if data.ndim > 1:
        data = data.mean(axis=1)  # mono
    data = data.astype(np.float32)
    data /= np.max(np.abs(data))  # normalize to -1..+1

    # Auto amplitude threshold (75% of range)
    min_val, max_val = np.min(data), np.max(data)
    amplitude_threshold = min_val + 0.75 * (max_val - min_val)

    # Convert timing to samples
    pulse_width_samples = int(pulse_width_ms * 1e-3 * fs)
    period_0_samples = int(period_0_ms * 1e-3 * fs)
    period_1_samples = int(period_1_ms * 1e-3 * fs)
    interbyte_pause_samples = int(interbyte_pause_ms * 1e-3 * fs)
    min_distance = int(pulse_width_samples * min_distance_factor)

    # Detect impulses
    impulses = np.where(data > amplitude_threshold)[0]
    filtered = []
    last = -min_distance
    for idx in impulses:
        if idx - last > min_distance:
            filtered.append(idx)
            last = idx
    impulses = np.array(filtered)

    bits = []
    bytes_out = []
    i = 0
    while i < len(impulses):
        if i+1 < len(impulses):
            gap = impulses[i+1] - impulses[i]
        else:
            gap = interbyte_pause_samples

        # Bit decision
        if i+1 < len(impulses) and gap < (period_1_samples * 1.5):
            bits.append(1)
            i += 2
        else:
            bits.append(0)
            i += 1

        # Detect end of byte
        if i < len(impulses):
            next_gap = impulses[i] - impulses[i-1]
            if next_gap > interbyte_pause_samples:
                while len(bits) % 8 != 0:
                    bits.append(0)
                for b in range(0, len(bits), 8):
                    value = sum((bit << j) for j, bit in enumerate(bits[b:b+8]))
                    bytes_out.append(value)
                bits.clear()

    # Handle trailing bits
    if bits:
        while len(bits) % 8 != 0:
            bits.append(0)
        for b in range(0, len(bits), 8):
            value = sum((bit << j) for j, bit in enumerate(bits[b:b+8]))
            bytes_out.append(value)

    # Count and strip sync bytes
    sync_count = 0
    for b in bytes_out:
        if b == 0x00:
            sync_count += 1
        else:
            break
    payload = bytes_out[sync_count:]

    stats = {
        "fs": fs,
        "amplitude_threshold": float(amplitude_threshold),
        "impulses": int(len(impulses)),
        "pulse_width_samples": int(pulse_width_samples),
        "period_0_samples": int(period_0_samples),
        "period_1_samples": int(period_1_samples),
        "interbyte_pause_samples": int(interbyte_pause_samples),
    }

    # Save if requested
    if save_to:
        with open(save_to, "wb") as f:
            f.write(bytes(payload))

    return sync_count, payload, stats


def cli_gtp2wav(inp: Path, outp: Path, sr: int, bits: int):
    data = inp.read_bytes()
    samples = gtp_to_wav_bytes(data, sr=sr, bits=bits)
    _wav_write_mono(outp, sr, samples, bits=bits)
    print("OK: {} -> {}  ({} Hz / {}-bit, leader {}×0x00)".format(inp, outp, sr, bits, SYNCBYTES))

def cli_wav2gtp(inp: Path, outp: Path, debug: bool = False):
    sync_count, payload, stats = decode_pcm_bytes(str(inp))
    print("Leader sync bytes detected: {}".format(sync_count))
    raw = bytes(payload)

    if debug:
        print("[debug] WAV stats:")
        for k, v in stats.items():
            print("  {}: {}".format(k, v))
        print("[debug] payload bytes: {}".format(len(raw)))
        print("[debug] first 256 bytes (hex):")
        print(_hexdump(raw[:256]))

    # Try full GTP block present
    blk = _extract_first_valid_gtp_block(raw)
    if blk is not None:
        outp.write_bytes(blk)
        print("OK: {} -> {} (decoded {} bytes; found full GTP block)".format(inp, outp, len(blk)))
        if debug:
            print("[debug] GTP block hexdump (first 256):")
            print(_hexdump(blk[:256]))
        return

    # If not, but looks like A5-started block, wrap it
    if raw.startswith(b"\xA5"):
        try:
            # If the decoded already includes checksum as last byte, _wrap_a5_to_gtp will accept it;
            # otherwise it will compute and append the proper checksum.
            gtp = _wrap_a5_to_gtp(raw)
            if not _is_valid_gtp(gtp):
                print("WARNING: Wrapped A5 data but resulting GTP did not validate; writing anyway.")
            outp.write_bytes(gtp)
            print("OK: {} -> {} (wrapped A5 stream into GTP; {} bytes)".format(inp, outp, len(gtp)))
            if debug:
                print("[debug] wrapped GTP (first 256 bytes):")
                print(_hexdump(gtp[:256]))
            return
        except Exception as ex:
            print("WARNING: Failed to wrap A5 stream into GTP: {}".format(ex))

    # Fall back: write raw decoded for inspection
    outp.write_bytes(raw)
    print("WARNING: No valid GTP or A5-start stream found. Wrote raw decoded ({} bytes).".format(len(raw)))

def main():
    ap = argparse.ArgumentParser(description="Galaksija GTP & WAV converter")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_g2w = sub.add_parser("gtp2wav", help="Convert .gtp to .wav (Tomaz Šolc timings)")
    p_g2w.add_argument("--in",  dest="inp",  required=True, type=Path)
    p_g2w.add_argument("--out", dest="outp", required=True, type=Path)
    p_g2w.add_argument("--sr", type=int, default=WAV_DEFAULT_SR, help="Sample rate (default 44100)")
    p_g2w.add_argument("--bits", type=int, default=WAV_DEFAULT_BITS, choices=[8,16], help="Bit depth (default 16)")
    p_g2w.add_argument("--debug", action="store_true", help="Extra debug prints")

    p_w2g = sub.add_parser("wav2gtp", help="Decode .wav back to .gtp (PCM pulse decoder)")
    p_w2g.add_argument("--in",  dest="inp",  required=True, type=Path)
    p_w2g.add_argument("--out", dest="outp", required=True, type=Path)
    p_w2g.add_argument("--debug", action="store_true", help="Extra debug prints and hex dumps")

    args = ap.parse_args()
    if args.cmd == "gtp2wav":
        cli_gtp2wav(args.inp, args.outp, args.sr, args.bits)
        if args.debug:
            print("[debug] wrote WAV from {}, sample rate={}, bits={}, leader={}".format(args.inp, args.sr, args.bits, SYNCBYTES))
    elif args.cmd == "wav2gtp":
        cli_wav2gtp(args.inp, args.outp, debug=args.debug)

if __name__ == "__main__":
    main()
