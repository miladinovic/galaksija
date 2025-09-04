#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Galaksija HIRES Maker — GUI + CLI with background worker
Now with Levels (black/white/gamma), Reset Levels, Invert, optional WAV export,
and mode-aware dictionary encoding/preview:

Encoding:
- Traditional  (packed 2×3 dots -> 0xC0|bits, as before)
- Dot (DICT)   (use dictionary C0–FF on 8×3 tiles; black => 0xC0)
- Full ASCII   (match against ENTIRE CHAR8x3, including C0–FF; black => 0xC0)

IMPORTANT: For DICT/ASCII, the source is matched on a 256×192 binary image in 8×3 tiles.

Author: Aleksandar Miladinovic
"""

import sys
import wave
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from typing import Optional, Dict, Tuple, List
import base64
from io import BytesIO

from PIL import Image, ImageTk
import numpy as np
from pathlib import Path
import argparse
import textwrap
from concurrent.futures import ThreadPoolExecutor, Future
import threading

# -------------------------------------------------------------------
# Put a base64 PNG string here if you want a custom window icon.
_EMBED_PNG_B64 = (  "iVBORw0KGgoAAAANSUhEUgAAANYAAADXCAYAAAERuJ8dAAAACXBIWXMAAAsTAAALEwEAmpwYAAAF92lUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgNi4wLWMwMDIgNzkuMTY0NDg4LCAyMDIwLzA3LzEwLTIyOjA2OjUzICAgICAgICAiPiA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPiA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIiB4bWxuczp4bXA9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC8iIHhtbG5zOmRjPSJodHRwOi8vcHVybC5vcmcvZGMvZWxlbWVudHMvMS4xLyIgeG1sbnM6cGhvdG9zaG9wPSJodHRwOi8vbnMuYWRvYmUuY29tL3Bob3Rvc2hvcC8xLjAvIiB4bWxuczp4bXBNTT0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL21tLyIgeG1sbnM6c3RFdnQ9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZUV2ZW50IyIgeG1wOkNyZWF0b3JUb29sPSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgeG1wOkNyZWF0ZURhdGU9IjIwMjUtMDktMDNUMTQ6MzE6MjgrMDI6MDAiIHhtcDpNb2RpZnlEYXRlPSIyMDI1LTA5LTAzVDE0OjM3OjI5KzAyOjAwIiB4bXA6TWV0YWRhdGFEYXRlPSIyMDI1LTA5LTAzVDE0OjM3OjI5KzAyOjAwIiBkYzpmb3JtYXQ9ImltYWdlL3BuZyIgcGhvdG9zaG9wOkNvbG9yTW9kZT0iMyIgcGhvdG9zaG9wOklDQ1Byb2ZpbGU9InNSR0IgSUVDNjE5NjYtMi4xIiB4bXBNTTpJbnN0YW5jZUlEPSJ4bXAuaWlkOjVhNTZmZGQ0LTQ5ODQtNGNjNi1hMDc1LTM0YWZmMTY0ODA1ZSIgeG1wTU06RG9jdW1lbnRJRD0iYWRvYmU6ZG9jaWQ6cGhvdG9zaG9wOmM0MmM0Y2U2LWE3MGUtMjk0Ny05Y2E3LTljOGRmMjAwNGVkOCIgeG1wTU06T3JpZ2luYWxEb2N1bWVudElEPSJ4bXAuZGlkOmY3OTVmMmM5LTZjYjItNGQ3ZS1iNDc5LWYzZWMwNjg3NzY2NyI+IDx4bXBNTTpIaXN0b3J5PiA8cmRmOlNlcT4gPHJkZjpsaSBzdEV2dDphY3Rpb249ImNyZWF0ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6Zjc5NWYyYzktNmNiMi00ZDdlLWI0NzktZjNlYzA2ODc3NjY3IiBzdEV2dDp3aGVuPSIyMDI1LTA5LTAzVDE0OjMxOjI4KzAyOjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIvPiA8cmRmOmxpIHN0RXZ0OmFjdGlvbj0ic2F2ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6NWE1NmZkZDQtNDk4NC00Y2M2LWEwNzUtMzRhZmYxNjQ4MDVlIiBzdEV2dDp3aGVuPSIyMDI1LTA5LTAzVDE0OjM3OjI5KzAyOjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgc3RFdnQ6Y2hhbmdlZD0iLyIvPiA8L3JkZjpTZXE+IDwveG1wTU06SGlzdG9yeT4gPC9yZGY6RGVzY3JpcHRpb24+IDwvcmRmOlJERj4gPC94OnhtcG1ldGE+IDw/eHBhY2tldCBlbmQ9InIiPz6Q+ezQAAAaKUlEQVR4nO1d6ZLjugpWTmXe/4HTVbk/7qgHEyFAgBaHr6qrO46tDbEj9+P9fpdZ+G9aT9lZdpadZWfZWXaWnWVn2Vl2tmNnjzS/s7PsLDvLzrKz7Cw7y86ys+xsFqaa3zMxdRVnIid2GnJipyEndhpyYqchJ3YacmKnISd2GnJipyEndhpyYqchJ3YacmKn4bYTu2WI+5bUykmdgpzUKbjlpJ7C+15/f/9pXHuWUn7Q/fC+qjN+iO/dwempdynlgT5r8FP+TaC2hdt0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"
)  # placeholder

def set_embedded_icon(root):
    try:
        if not _EMBED_PNG_B64:
            return
        raw = base64.b64decode(_EMBED_PNG_B64)
        img = Image.open(BytesIO(raw))
        tkimg = ImageTk.PhotoImage(img)
        root.iconphoto(True, tkimg)
        root._embedded_icon_ref = tkimg  # keep a reference
    except Exception:
        pass

# ====== PASTE YOUR DICTIONARY HERE ======
# Expected shape:
# CHAR8x3: Dict[int, Tuple[str, str, str]]
# Each tuple holds three 8-character strings composed of '0'/'1' for the 3 rows of an 8×3 tile.
# Include printable ASCII you want AND the graphical C0..FF block you shared earlier.
CHAR8x3: Dict[int, Tuple[str, str, str]] = {
    0x21: ("00010000","00010000","00000000"),  # '!'
    0x22: ("00101000","00000000","00000000"),  # '"'
    0x23: ("00110110","01111110","00000000"),  # '#'
    0x24: ("00001000","01001000","00000000"),  # '$'
    0x25: ("00000000","00000100","00000000"),  # '%'
    0x26: ("00110000","01110000","00000000"),  # '&'
    0x27: ("10000000","10010000","00000000"),  # '''
    0x28: ("00001000","00100000","00000000"),  # '('
    0x29: ("00010000","00000100","00000000"),  # ')'
    0x2A: ("00000000","00111000","00000000"),  # '*'
    0x2B: ("00000000","00010000","00000000"),  # '+'
    0x2C: ("00000000","00000000","00100000"),  # ','
    0x2F: ("00000100","00001000","01000000"),  # '/'
    0x30: ("00111110","01000110","00000000"),  # '0'
    0x33: ("00111100","00000110","00000000"),  # '3'
    0x34: ("00001100","00110110","00000000"),  # '4'  (kept exactly as provided)
    0x35: ("01111110","01111100","00000000"),  # '5'
    0x36: ("00111100","01111100","00000000"),  # '6'
    0x37: ("01111110","00000110","00000000"),  # '7'
    0x38: ("00111100","01111110","00000000"),  # '8'
    0x3B: ("00000000","00010000","00100000"),  # ';'
    0x3D: ("00000000","01111110","00000000"),  # '='
    0x3E: ("00000000","00001000","00000000"),  # '>'
    0x3F: ("00000000","00111100","00000010"),  # '?'
    0x40: ("00011000","01111110","00000100"),  # '@'
    0x41: ("00011000","01000010","00000000"),  # 'A'
    0x44: ("01111100","01100010","00000000"),  # 'D'
    0x46: ("01111110","01000000","00000000"),  # 'F'
    0x47: ("00111100","01000000","00000000"),  # 'G'
    0x49: ("00111000","00010000","00000000"),  # 'I'
    0x4A: ("01111110","00000010","00000000"),  # 'J' (kept as provided)
    0x4B: ("01000010","01010010","00000000"),  # 'K'
    0x4C: ("01000000","01000000","00000000"),  # 'L'
    0x4D: ("01000010","01011010","00000000"),  # 'M'
    0x50: ("01111100","01000010","00000000"),  # 'P'
    0x51: ("00111100","01000010","00000000"),  # 'Q'
    0x52: ("01111101","01000010","00000000"),  # 'R'
    0x53: ("00111101","01000000","00000000"),  # 'S'
    0x54: ("01111110","00010000","00000000"),  # 'T'
    0x55: ("01000010","01000010","00000000"),  # 'U'
    0x56: ("01000011","00100100","00000000"),  # 'V'
    0x57: ("01000011","01000010","00000000"),  # 'W'
    0x58: ("01000010","00100101","00000000"),  # 'X'
    0x59: ("01000010","01000011","00000000"),  # 'Y'
    0x5A: ("01111111","00001001","00000000"),  # 'Z'
    0x5C: ("00111100","01000001","00000000"),  # '\'
    0x5D: ("01111110","00001001","00000000"),  # ']'
    0x5E: ("00111101","01000001","00000000"),  # '^'
    0x5F: ("00000001","00000001","00000000"),  # '_'

    # graphical chars (dot tiles)
    0xC0: ("00000000","00000000","00000000"),
    0xC1: ("01100000","00000000","00000000"),
    0xC2: ("00000110","00000000","00000000"),
    0xC3: ("01100110","00000000","00000000"),
    0xC4: ("00000000","01100000","00000000"),
    0xC5: ("01100000","01100000","00000000"),
    0xC6: ("00000110","01100000","00000000"),
    0xC7: ("01100110","01100000","00000000"),
    0xC8: ("00000000","00000110","00000000"),
    0xC9: ("01100000","00000110","00000000"),
    0xCA: ("00000110","00000110","00000000"),
    0xCB: ("01100110","00000110","00000000"),
    0xCC: ("00000000","01100110","00000000"),
    0xCD: ("01100000","01100110","00000000"),
    0xCE: ("00000110","01100110","00000000"),
    0xCF: ("01100110","01100110","00000000"),
    0xD0: ("00000000","00000000","01100000"),
    0xD1: ("01100000","00000000","01100000"),
    0xD2: ("00000110","00000000","01100000"),
    0xD3: ("01100110","00000000","01100000"),
    0xD4: ("00000000","01100000","01100000"),
    0xD5: ("01100000","01100000","01100000"),
    0xD6: ("00000110","01100000","01100000"),
    0xD7: ("01100110","01100000","01100000"),
    0xD8: ("00000000","00000110","01100000"),
    0xD9: ("01100000","00000110","01100000"),
    0xDA: ("00000110","00000110","01100000"),
    0xDB: ("01100110","00000110","01100000"),
    0xDC: ("00000000","01100110","01100000"),
    0xDD: ("01100000","01100110","01100000"),
    0xDE: ("00000110","01100110","01100000"),
    0xDF: ("01100110","01100110","01100000"),
    0xE0: ("00000000","00000000","00000110"),
    0xE1: ("01100000","00000000","00000110"),
    0xE2: ("00000110","00000000","00000110"),
    0xE3: ("01100110","00000000","00000110"),
    0xE4: ("00000000","01100000","00000110"),
    0xE5: ("01100000","01100000","00000110"),
    0xE6: ("00000110","01100000","00000110"),
    0xE7: ("01100110","01100000","00000110"),
    0xE8: ("00000000","00000110","00000110"),
    0xE9: ("01100000","00000110","00000110"),
    0xEA: ("00000110","00000110","00000110"),
    0xEB: ("01100110","00000110","00000110"),
    0xEC: ("00000000","01100110","00000110"),
    0xED: ("01100000","01100110","00000110"),
    0xEE: ("00000110","01100110","00000110"),
    0xEF: ("01100110","01100110","00000110"),
    0xF0: ("00000000","00000000","01100110"),
    0xF1: ("01100000","00000000","01100110"),
    0xF2: ("00000110","00000000","01100110"),
    0xF3: ("01100110","00000000","01100110"),
    0xF4: ("00000000","01100000","01100110"),
    0xF5: ("01100000","01100000","01100110"),
    0xF6: ("00000110","01100000","01100110"),
    0xF7: ("01100110","01100000","01100110"),
    0xF8: ("00000000","00000110","01100110"),
    0xF9: ("01100000","00000110","01100110"),
    0xFA: ("00000110","00000110","01100110"),
    0xFB: ("01100110","00000110","01100110"),
    0xFC: ("00000000","01100110","01100110"),
    0xFD: ("01100000","01100110","01100110"),
    0xFE: ("00000110","01100110","01100110"),
    0xFF: ("01100110","01100110","01100110"),
}

# -------------------------------------------------------------------
# GTP templates (paste your bytes; keep as placeholders if you don’t need CLI export)
G40HEX = bytearray(b'\x10\x08\x00\x00\x00HRESG40\x00\x00\x0c\x0b\x00\x00\xa56,;7!7;7\xcd\x89,\xf3!\x00(\x16)r#|\xe6\x01(\xf9r!))6\xc3#6\x19#6->(\xedG\xed^\xfb\xcd\xea.!\x1f ~\xe6\x01\xc2],\xedV>\x0c\xe7\x11\xb0,\xcd7\t\x11\xca,\xcd7\t\x11\xe4,\xcd7\t\x11\xfe,\xcd7\t\xc3f\x00!\xa1,"6,!\xb0,"8,! 7\x11\xff?\x01\x00\x08\xed\xb8\xc9\x01\x00A=USR(&2C3D)\rGALAKSIJA HIGH RESOLUTION\r=========================\rTOMAZ SOLC, JAN 2009     \rMOD.ALEKS MILADINOVIC 2025\r\xf5\xc5\xd5\xe5\x06\n\x00\x00\xedW>\n= \xfd\x10\xf5\x00:\xa8+\xd6\x03\x1f8\x00= \xfd!\x7f \x11\x7f8z\xedG\x06\x8c\x0e\x80{\xedOp\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00q>\x00>\x00\x00\x00\x00\x00\x00\x06\x98{\xedOp\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00q>\x00>\x00\x00\x00\x00\x00\x00\x06\xb0{\xedOp\xb7{\x17<<\x1f_\xafG7\x1f\x1f\x1f\x83_x\x8aW{\x17=\x1f_\xb7|\x17G\x17\x00\x00\x00wz\xedG\xa0\xca?->(\xedG\xe1\xd1\xc1\xf1\xfb\xedM!\x008\xafW\x1e\x03\xcb\x11\x177\xcb\x11\x177\xcb\x11\x17\x930\x01\x83\xcb\x11\x17\x930\x01\x83\xcb\x11\x17\x930\x01\x83\xcb\x11\x17\x930\x01\x83\xcb\x11\x17\x930\x01\x83\xcb\x11\x17\x930\x01\x83\xcb\x11\x08y/\x07\x17\x17\xcb\x12\x17\xcb\x12\x17\xcb\x12_\x19\x08XG\x04>@\x07\x07\x10\xfcP\xcb;\xcb;\xcb;0\x01\x07\x19\xc9\xe5\xcd\xd7-F\xe3p#\xb0\xeb\xe1w\xebs#r#\xc9\x00\x80\x01\x06\x00\x00\x00\x00\x02y\x01\xa6\x00\x00\x00\x00\x01\xc0\x01\x8a\x00\x00\x00\x00\x00\x08\x01\x05\x00\x00\x00\x00\x02i\x01K\x00\x00\x00\x00\x01O\x01j\x00\x00\x00\x00\x01\xfa\x01(\x00\x00\x00\x00\x00\xf1\x01\xa6\x00\x00\x00\x00\x01\x1a\x01\x9b\x00\x00\x00\x00\x00\xd5\x01\x9e\x00\x00\x00\x00\x02m\x01=\x00\x00\x00\x00\x02\x98\x01r\x00\x00\x00\x00\x02\xa3\x01o\x00\x00\x00\x00\x02s\x01&\x00\x00\x00\x00\x01\xe2\x01h\x00\x00\x00\x00\x01\xd4\x01|\x00\x00\x00\x00\x01\x01\x01\x98\x00\x00\x00\x00\x02\xf4\x01\x99\x00\x00\x00\x00\x01\x90\x01H\x00\x00\x00\x00\x02\xb9\x01\x08\x00\x00\x00\x00!J.\x06\x14\xc5~#F\x80\xfe\xff8\x01\xafGp#~#N\x81\xfe\xbf8\x01\xafOq#\xcd8.#\xc1\x10\xe0v\x06\x14++V+^+~\x12\x11\xfa\xff\x19\x10\xf4\xc9\xc0\xc0\xc0\xc0\xc0\xde\xc1\xc2\xd0\xc0\xc2\xf7\xfb\xee\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xfa\xc1\xec\xff\xff\xff\xfd\xd0\xef\xd7\xd5\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xea\xc1\xfa\xff\xff\xff\xff\xff\xfd\xe2\xd5\xf5\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xe0\xd7\xfa\xdf\xff\xff\xff\xff\xff\xff\xd4\xee\xea\xcc\xf4\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xde\xea\xfe\xdf\xff\xff\xff\xff\xff\xff\xfd\xc2\xc8\xfc\xfa\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xe8\xc5\xfd\xff\xff\xff\xcf\xcf\xef\xff\xdf\xef\xc4\xe8\xf4\xee\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xde\xf2\xff\xdf\xfe\xe5\xff\xff\xfd\xdb\xff\xd6\xc0\xdd\xff\xfa\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xe0\xd5\xff\xff\xdd\xfd\xff\xff\xff\xff\xff\xfa\xc1\xc0\xc2\xf5\xd0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xe0\xdc\xdc\xfa\xea\xff\xff\xea\xff\xff\xff\xff\xff\xff\xc5\xce\xc0\xe0\xf0\xc3\xeb\xec\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xdc\xe7\xf8\xfc\xd5\xfe\xff\xdd\xff\xff\xff\xff\xff\xff\xd7\xc1\xf8\xfc\xff\xff\xff\xfc\xf2\xeb\xd0\xc0\xc0\xc0\xc0\xc0\xf0\xd7\xf9\xff\xcf\xdf\xe9\xff\xdf\xf6\xff\xff\xff\xff\xff\xdf\xf8\xff\xff\xff\xff\xff\xff\xff\xff\xf4\xeb\xd0\xc0\xc0\xc0\xe8\xc5\xfc\xe7\xf8\xf8\xfc\xfe\xff\xef\xfd\xff\xff\xff\xff\xdf\xc8\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xf4\xcb\xd4\xc0\xe8\xc7\xfe\xe3\xfe\xff\xff\xff\xff\xdf\xff\xee\xff\xff\xd7\xd3\xe1\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xd4\xed\xe0\xd7\xde\xf8\xff\xff\xff\xff\xff\xff\xef\xff\xff\xdf\xd1\xc4\xc8\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfd\xc2\xc7\xc8\xf9\xff\xff\xff\xff\xff\xff\xdf\xff\xfd\xef\xe4\xe0\xde\xfb\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xd4\xc0\xd1\xc2\xff\xff\xff\xff\xdf\xf9\xff\xff\xc7\xe6\xc5\xde\xff\xfb\xef\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xf7\xe0\xe3\xd6\xee\xff\xff\xdf\xfe\xff\xff\xf5\xed\xc7\xfe\xfb\xff\xc4\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xc4\xc4\xff\xfa\xff\xd7\xfe\xff\xff\xff\xe6\xda\xea\xed\xff\xc7\xfa\xff\xf7\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xd5\xc4\xee\xfe\xe7\xfe\xff\xff\xff\xd5\xfb\xe4\xfd\xd3\xdf\xe8\xff\xdf\xea\xff\xf7\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfd\xe2\xe2\xf0\xff\xff\xff\xff\xff\xfe\xd7\xfe\xfe\xd7\xc0\xff\xff\xc3\xfe\xfb\xea\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xc8\xea\xff\xff\xff\xff\xff\xdf\xff\xe4\xf7\xdf\xc0\xff\xf6\xed\xea\xfd\xef\xea\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xd6\xd4\xff\xff\xff\xff\xdf\xf8\xd7\xee\xdb\xe9\xea\xff\xfd\xd5\xfe\xf5\xd5\xff\xdf\xf6\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xd5\xe1\xef\xff\xdf\xe1\xfe\xdf\xe5\xdf\xe8\xd5\xff\xff\xee\xe9\xfb\xed\xd1\xff\xf5\xeb\xff\xdf\xff\xff\xff\xff\xff\xff\xff\xff\xf9\xea\xf6\xf5\xfe\xfb\xc7\xe0\xe8\xe9\xef\xe9\xff\xf7\xd7\xea\xdd\xdb\xe8\xff\xdb\xfa\xff\xd5\xff\xff\xff\xff\xff\xff\xff\xed\xfd\xc8\xff\xff\xef\xd7\xe0\xde\xc0\xd7\xd7\xfe\xf7\xdf\xd0\xff\xef\xdd\xea\xff\xe5\xfb\xff\xed\xff\xdf\xfe\xff\xff\xff\xda\xff\xfd\xc2\xff\xd7\xd7\xe0\xde\xc0\xea\xe1\xd5\xff\xeb\xd5\xe8\xdf\xfe\xd5\xe8\xff\xc4\xff\xff\xea\xff\xd6\xee\xf7\xff\xff\xc9\xfd\xff\xf0\xc0\xc0\xf9\xc7\xc0\xc0\xfb\xea\xea\xf7\xdf\xd4\xea\xf5\xff\xc0\xfb\xfd\xe1\xdf\xff\xfa\xff\xe6\xdb\xfd\xff\xd5\xd7\xff\xff\xc4\xd7\xc3\xc1\xc0\xc0\xc0\xee\xfa\xea\xee\xe9\xd7\xfe\xea\xd7\xc4\xff\xf7\xea\xf7\xd5\xff\xf7\xd6\xee\xdd\xff\xd2\xdd\xff\xff\xd5\xd5\xc0\xc0\xc0\xc0\xc0\xc3\xd5\xdf\xd7\xfa\xd5\xf7\xff\xeb\xc0\xff\xf5\xeb\xfb\xe5\xff\xd5\xdb\xf9\xdf\xfa\xc5\xff\xeb\xff\xc5\xd5\xc0\xc0\xc0\xc0\xc0\xc0\xd5\xf7\xe5\xd5\xe7\xee\xff\xd1\xc0\xff\xf5\xef\xff\xe8\xf3\xeb\xea\xe8\xff\xea\xd5\xff\xea\xff\xd5\xd5\xc0\xc0\xc0\xc0\xc0\xe8\xe5\xcf\xfa\xe8\xe5\xff\xe5\xc5\xe0\xff\xc4\xf7\xdf\xea\xff\xfb\xe0\xe5\xff\xea\xd5\xff\xea\xff\xd5\xd5\xc0\xc0\xc0\xc0\xc0\xea\xea\xd1\xd5\xfa\xe8\xdf\xfa\xf2\xe8\xff\xc1\xff\xd7\xea\xff\xf6\xea\xea\xff\xea\xd5\xff\xd4\xff\xd5\xd5\xc0\xc0\xc0\xc0\xc0\xea\xca\xea\xc1\xdd\xfa\xe5\xf5\xdc\xd5\xdf\xd1\xff\xd5\xea\xdd\xd5\xea\xea\xff\xea\xd5\xff\xe5\xff\xd5\xd5\xc0\xc0\xc0\xc0\xc0\xea\xc0\xd7\xc0\xd5\xea\xee\xea\xff\xca\xf7\xc0\xff\xd1\xfe\xdd\xd5\xea\xca\xff\xea\xd5\xff\xd9\xff\xd5\xd5\xc0\xc0\xc0\xc0\xf8\xea\xe0\xd5\xe8\xc5\xc5\xca\xfb\xff\xd9\xd5\xe2\xff\xc0\xfe\xef\xc4\xea\xe2\xff\xe4\xd5\xfa\xd5\xff\xd5\xd5\xc0\xc0\xc0\xe8\xe5\xea\xea\xc0\xea\xc1\xea\xe8\xc6\xef\xd6\xd5\xc8\xff\xc0\xff\xee\xc0\xea\xc8\xff\xe8\xd5\xee\xf5\xef\xd5\xd5\xc0\xc0\xe0\xd7\xfe\xea\xea\xc0\xea\xc4\xfb\xe2\xdd\xe8\xd5\xd5\xe2\xdd\xc0\xff\xeb\xe0\xea\xc0\xff\xf2\xd5\xfa\xdd\xeb\xe4\xd5\xc0\xc0\xde\xfa\xdf\xea\xea\xc0\xea\xe0\xe5\xee\xd7\xea\xd5\xea\xf4\xd7\xd4\xff\xe9\xe9\xea\xc0\xff\xcc\xd5\xee\xf7\xea\xea\xc0\xc0\xe8\xe5\xff\xe5\xea\xfa\xc0\xde\xe0\xfb\xea\xf5\xea\xf5\xeb\xdd\xd5\xdd\xff\xc0\xff\xea\xe0\xef\xea\xe1\xeb\xd5\xe0\xea\xc0\xe8\xe7\xfe\xdf\xfe\xc0\xd5\xc0\xf7\xc0\xff\xea\xff\xea\xfd\xfb\xf7\xed\xd7\xff\xe8\xff\xd7\xe2\xef\xc2\xd4\xea\xd5\xe4\xea\xe0\xde\xfa\xff\xe9\xff\xc0\xd5\xc0\xd5\xea\xf5\xeb\xf4\xff\xfd\xfb\xfd\xeb\xf7\xef\xee\xff\xf5\xea\xee\xe2\xda\xea\xd5\xdd\xea\xde\xfa\xff\xf7\xfe\xff\xc0\xc0\xc0\xd7\xee\xf7\xca\xff\xff\xff\xff\xff\xea\xf7\xd5\xff\xd6\xcb\xda\xfb\xc8\xea\xea\xd5\xf7\xee\xe9\xff\xff\xe9\xff\xff\xc0\xc0\xc0\xf5\xfb\xed\xea\xf6\xff\xff\xff\xff\xea\xff\xe4\xff\xdf\xf0\xe2\xf7\xca\xf0\xeb\xd5\xff\xf2\xfe\xff\xe7\xfe\xff\xdf\xc0\xc0\xc0\xd5\xef\xf5\xe6\xfd\xff\xff\xff\xff\xfe\xff\xec\xff\xd5\xfd\xc2\xfe\xc2\xd6\xf6\xd5\xfd\xe9\xff\xff\xea\xff\xff\xff\xc0\xc0\xc0\xf5\xff\xd4\xf5\xff\xff\xff\xff\xff\xff\xff\xff\xff\xe5\xc5\xe0\xff\xc2\xd4\xd5\xf5\xe5\xeb\xff\xe5\xff\xff\xff\xff\xc0\xc0\xea\xeb\xf6\xed\xc0\xff\xff\xff\xff\xff\xff\xff\xff\xff\xea\xff\xea\xee\xe8\xc9\xd5\xed\xd1\xff\xdf\xfa\xff\xdf\xff\xff\xc0\xc0\xea\xeb\xd5\xdb\xc0\xff\xff\xff\xff\xff\xff\xff\xff\xff\xe2\xff\xea\xfa\xe2\xc5\xf5\xeb\xe0\xff\xe9\xff\xff\xff\xff\xe5\xc0\xc0\xea\xea\xed\xca\xc0\xef\xff\xff\xd7\xff\xff\xff\xff\xff\xd5\xc5\xff\xfe\xea\xd1\xf7\xc0\xee\xd3\xfe\xff\xff\xff\xdf\xf4\xc0\xc0\xea\xeb\xc5\xc5\xc0\xeb\xff\xff\xd5\xff\xff\xff\xd7\xff\xff\xff\xff\xff\xea\xd4\xc8\xc0\xc0\xca\xff\xff\xff\xff\xdd\xfb\xc0\xc0\xd7\xff\xca\xea\xc0\xda\xff\xff\xff\xff\xff\xff\xff\xff\xef\xff\xff\xff\xea\xd1\xd0\xc2\xd8\xd9\xd0\xef\xff\xff\xf5\xff\xc0\xc0\xdf\xf5\xc5\xfa\xdd\xc1\xff\xff\xff\xff\xff\xff\xff\xff\xee\xfb\xff\xff\xea\xc5\xd4\xc4\xe6\xe6\xe6\xe4\xc3\xdf\xfe\xff\xc0\xc0\xdd\xfd\xe1\xff\xe9\xe0\xeb\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xea\xd1\xfd\xe0\xd9\xf9\xfd\xd9\xd9\xd0\xff\xff\xc0\xc0\xdf\xd5\xea\xdf\xfa\xc0\xea\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xc5\xe2\xd4\xd5\xd4\xe6\xee\xff\xff\xf6\xe4\xea\xed\xc0\xea\xeb\xd5\xee\xe5\xd7\xd0\xc8\xff\xff\xff\xff\xff\xff\xff\xd7\xef\xd7\xe0\xc8\xd5\xfe\xfd\xc0\xc9\xdb\xff\xdd\xd9\xca\xce\xc0\xea\xfb\xc0\xfb\xea\xf5\xc5\xd8\xeb\xff\xff\xff\xff\xff\xdf\xc0\xc2\xe0\xd5\xd6\xd4\xff\xff\xf4\xc0\xc2\xe6\xe7\xc6\xc2\xd5\xc0\xea\xee\xe2\xee\xfa\xff\xc1\xc6\xca\xff\xef\xff\xff\xff\xd1\xc8\xc0\xfe\xd5\xd5\xf7\xee\xff\xff\xfd\xd0\xc0\xc9\xc1\xea\xc4\xc0\xea\xea\xe2\xd6\xfe\xf5\xc5\xe6\xe5\xeb\xfe\xff\xff\xff\xc0\xe0\xfe\xff\xd5\xd4\xdd\xea\xff\xff\xff\xeb\xf4\xc0\xc0\xd7\xc0\xc0\xd7\xe6\xea\xd9\xff\xf7\xc5\xf6\xc7\xd4\xcf\xcf\xcf\xc1\xf8\xfe\xff\xff\xd1\xf5\xcb\xd4\xea\xff\xe5\xff\xff\xfd\xf8\xc5\xc0\xe8\xe5\xc5\xea\xe4\xff\xf5\xc5\xf5\xdf\xfa\xdc\xf0\xf8\xfe\xff\xff\xff\xff\xe0\xda\xda\xd2\xe2\xd7\xfe\xff\xff\xff\xd7\xc0\xc0\xfa\xea\xc0\xee\xe8\xff\xf7\xc0\xd2\xfd\xfd\xff\xff\xff\xff\xff\xff\xff\xff\xc8\xda\xf2\xe8\xd4\xfe\xff\xff\xff\xdf\xc0\xc0\xc0\xd5\xff\xc4\xea\xea\xff\xff\xf2\xe7\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xc0\xd9\xd1\xff\xd5\xff\xff\xff\xef\xc1\xc0\xc0\xc0\xc9\xff\xea\xea\xea\xff\xd5\xff\xd0\xeb\xff\xff\xff\xff\xff\xff\xff\xff\xff\xc0\xd1\xdd\xff\xff\xea\xff\xe7\xd7\xc0\xc0\xc0\xc0\xea\xff\xea\xea\xea\xff\xd5\xff\xdc\xdd\xff\xff\xff\xff\xff\xfd\xef\xff\xdd\xd0\xd0\xdd\xff\xff\xda\xfd\xc7\xc0\xc0\xc0\xc0\xc0\xff\xff\xea\xfa\xea\xff\xf7\xff\xd5\xdd\xff\xff\xff\xff\xc7\xea\xfd\xdb\xd5\xd4\xd5\xdd\xff\xff\xd5\xd7\xc0\xc0\xc0\xc0\xc0\xc0\x01\x00B.&2BA8,35:A=USR(&2C3A)\r]7')
GORG = bytearray(b'\x10\x11\x00\x00\x00HIGHRES-ORIG.GAL\x00\x00\x01\x0b\x00\x00\xa56,07!707\xcd\x89,\xf3!\x00(\x16)r#|\xe6\x01(\xf9r!))6\xc3#6\x19#6->(\xedG\xed^\xfb\xcd\xea.!\x1f ~\xe6\x01\xc2],\xedV>\x0c\xe7\x11\xb0,\xcd7\t\x11\xca,\xcd7\t\x11\xe4,\xcd7\t\x11\xfe,\xcd7\t\xc3f\x00!\xa1,"6,!\xb0,"8,! 7\x11\xff?\x01\x00\x08\xed\xb8\xc9\x01\x00A=USR(&2C3D)\rGALAKSIJA HIGH RESOLUTION\r=========================\rTOMAZ SOLC, JAN 2009     \rMOD.ALEKS MILADINOVIC 2025\r\xf5\xc5\xd5\xe5\x06\n\x00\x00\xedW>\n= \xfd\x10\xf5\x00:\xa8+\xd6\x03\x1f8\x00= \xfd!\x7f \x11\x7f8z\xedG\x06\x8c\x0e\x80{\xedOp\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00q>\x00>\x00\x00\x00\x00\x00\x00\x06\x98{\xedOp\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00q>\x00>\x00\x00\x00\x00\x00\x00\x06\xb0{\xedOp\xb7{\x17<<\x1f_\xafG7\x1f\x1f\x1f\x83_x\x8aW{\x17=\x1f_\xb7|\x17G\x17\x00\x00\x00wz\xedG\xa0\xca?->(\xedG\xe1\xd1\xc1\xf1\xfb\xedM!\x008\xafW\x1e\x03\xcb\x11\x177\xcb\x11\x177\xcb\x11\x17\x930\x01\x83\xcb\x11\x17\x930\x01\x83\xcb\x11\x17\x930\x01\x83\xcb\x11\x17\x930\x01\x83\xcb\x11\x17\x930\x01\x83\xcb\x11\x17\x930\x01\x83\xcb\x11\x08y/\x07\x17\x17\xcb\x12\x17\xcb\x12\x17\xcb\x12_\x19\x08XG\x04>@\x07\x07\x10\xfcP\xcb;\xcb;\xcb;0\x01\x07\x19\xc9\xe5\xcd\xd7-F\xe3p#\xb0\xeb\xe1w\xebs#r#\xc9\x00\x80\x01\x06\x00\x00\x00\x00\x02y\x01\xa6\x00\x00\x00\x00\x01\xc0\x01\x8a\x00\x00\x00\x00\x00\x08\x01\x05\x00\x00\x00\x00\x02i\x01K\x00\x00\x00\x00\x01O\x01j\x00\x00\x00\x00\x01\xfa\x01(\x00\x00\x00\x00\x00\xf1\x01\xa6\x00\x00\x00\x00\x01\x1a\x01\x9b\x00\x00\x00\x00\x00\xd5\x01\x9e\x00\x00\x00\x00\x02m\x01=\x00\x00\x00\x00\x02\x98\x01r\x00\x00\x00\x00\x02\xa3\x01o\x00\x00\x00\x00\x02s\x01&\x00\x00\x00\x00\x01\xe2\x01h\x00\x00\x00\x00\x01\xd4\x01|\x00\x00\x00\x00\x01\x01\x01\x98\x00\x00\x00\x00\x02\xf4\x01\x99\x00\x00\x00\x00\x01\x90\x01H\x00\x00\x00\x00\x02\xb9\x01\x08\x00\x00\x00\x00!J.\x06\x14\xc5~#F\x80\xfe\xff8\x01\xafGp#~#N\x81\xfe\xbf8\x01\xafOq#\xcd8.#\xc1\x10\xe0v\x06\x14++V+^+~\x12\x11\xfa\xff\x19\x10\xf4\xc9\xc0\xc0\xc0\xc0\xc0\xde\xc1\xc2\xd0\xc0\xc2\xf7\xfb\xee\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xfa\xc1\xec\xff\xff\xff\xfd\xd0\xef\xd7\xd5\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xea\xc1\xfa\xff\xff\xff\xff\xff\xfd\xe2\xd5\xf5\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xe0\xd7\xfa\xdf\xff\xff\xff\xff\xff\xff\xd4\xee\xea\xcc\xf4\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xde\xea\xfe\xdf\xff\xff\xff\xff\xff\xff\xfd\xc2\xc8\xfc\xfa\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xe8\xc5\xfd\xff\xff\xff\xcf\xcf\xef\xff\xdf\xef\xc4\xe8\xf4\xee\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xde\xf2\xff\xdf\xfe\xe5\xff\xff\xfd\xdb\xff\xd6\xc0\xdd\xff\xfa\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xe0\xd5\xff\xff\xdd\xfd\xff\xff\xff\xff\xff\xfa\xc1\xc0\xc2\xf5\xd0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xe0\xdc\xdc\xfa\xea\xff\xff\xea\xff\xff\xff\xff\xff\xff\xc5\xce\xc0\xe0\xf0\xc3\xeb\xec\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xc0\xdc\xe7\xf8\xfc\xd5\xfe\xff\xdd\xff\xff\xff\xff\xff\xff\xd7\xc1\xf8\xfc\xff\xff\xff\xfc\xf2\xeb\xd0\xc0\xc0\xc0\xc0\xc0\xf0\xd7\xf9\xff\xcf\xdf\xe9\xff\xdf\xf6\xff\xff\xff\xff\xff\xdf\xf8\xff\xff\xff\xff\xff\xff\xff\xff\xf4\xeb\xd0\xc0\xc0\xc0\xe8\xc5\xfc\xe7\xf8\xf8\xfc\xfe\xff\xef\xfd\xff\xff\xff\xff\xdf\xc8\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xf4\xcb\xd4\xc0\xe8\xc7\xfe\xe3\xfe\xff\xff\xff\xff\xdf\xff\xee\xff\xff\xd7\xd3\xe1\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xd4\xed\xe0\xd7\xde\xf8\xff\xff\xff\xff\xff\xff\xef\xff\xff\xdf\xd1\xc4\xc8\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfd\xc2\xc7\xc8\xf9\xff\xff\xff\xff\xff\xff\xdf\xff\xfd\xef\xe4\xe0\xde\xfb\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xd4\xc0\xd1\xc2\xff\xff\xff\xff\xdf\xf9\xff\xff\xc7\xe6\xc5\xde\xff\xfb\xef\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xf7\xe0\xe3\xd6\xee\xff\xff\xdf\xfe\xff\xff\xf5\xed\xc7\xfe\xfb\xff\xc4\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xc4\xc4\xff\xfa\xff\xd7\xfe\xff\xff\xff\xe6\xda\xea\xed\xff\xc7\xfa\xff\xf7\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xd5\xc4\xee\xfe\xe7\xfe\xff\xff\xff\xd5\xfb\xe4\xfd\xd3\xdf\xe8\xff\xdf\xea\xff\xf7\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfd\xe2\xe2\xf0\xff\xff\xff\xff\xff\xfe\xd7\xfe\xfe\xd7\xc0\xff\xff\xc3\xfe\xfb\xea\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xc8\xea\xff\xff\xff\xff\xff\xdf\xff\xe4\xf7\xdf\xc0\xff\xf6\xed\xea\xfd\xef\xea\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xd6\xd4\xff\xff\xff\xff\xdf\xf8\xd7\xee\xdb\xe9\xea\xff\xfd\xd5\xfe\xf5\xd5\xff\xdf\xf6\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xd5\xe1\xef\xff\xdf\xe1\xfe\xdf\xe5\xdf\xe8\xd5\xff\xff\xee\xe9\xfb\xed\xd1\xff\xf5\xeb\xff\xdf\xff\xff\xff\xff\xff\xff\xff\xff\xf9\xea\xf6\xf5\xfe\xfb\xc7\xe0\xe8\xe9\xef\xe9\xff\xf7\xd7\xea\xdd\xdb\xe8\xff\xdb\xfa\xff\xd5\xff\xff\xff\xff\xff\xff\xff\xed\xfd\xc8\xff\xff\xef\xd7\xe0\xde\xc0\xd7\xd7\xfe\xf7\xdf\xd0\xff\xef\xdd\xea\xff\xe5\xfb\xff\xed\xff\xdf\xfe\xff\xff\xff\xda\xff\xfd\xc2\xff\xd7\xd7\xe0\xde\xc0\xea\xe1\xd5\xff\xeb\xd5\xe8\xdf\xfe\xd5\xe8\xff\xc4\xff\xff\xea\xff\xd6\xee\xf7\xff\xff\xc9\xfd\xff\xf0\xc0\xc0\xf9\xc7\xc0\xc0\xfb\xea\xea\xf7\xdf\xd4\xea\xf5\xff\xc0\xfb\xfd\xe1\xdf\xff\xfa\xff\xe6\xdb\xfd\xff\xd5\xd7\xff\xff\xc4\xd7\xc3\xc1\xc0\xc0\xc0\xee\xfa\xea\xee\xe9\xd7\xfe\xea\xd7\xc4\xff\xf7\xea\xf7\xd5\xff\xf7\xd6\xee\xdd\xff\xd2\xdd\xff\xff\xd5\xd5\xc0\xc0\xc0\xc0\xc0\xc3\xd5\xdf\xd7\xfa\xd5\xf7\xff\xeb\xc0\xff\xf5\xeb\xfb\xe5\xff\xd5\xdb\xf9\xdf\xfa\xc5\xff\xeb\xff\xc5\xd5\xc0\xc0\xc0\xc0\xc0\xc0\xd5\xf7\xe5\xd5\xe7\xee\xff\xd1\xc0\xff\xf5\xef\xff\xe8\xf3\xeb\xea\xe8\xff\xea\xd5\xff\xea\xff\xd5\xd5\xc0\xc0\xc0\xc0\xc0\xe8\xe5\xcf\xfa\xe8\xe5\xff\xe5\xc5\xe0\xff\xc4\xf7\xdf\xea\xff\xfb\xe0\xe5\xff\xea\xd5\xff\xea\xff\xd5\xd5\xc0\xc0\xc0\xc0\xc0\xea\xea\xd1\xd5\xfa\xe8\xdf\xfa\xf2\xe8\xff\xc1\xff\xd7\xea\xff\xf6\xea\xea\xff\xea\xd5\xff\xd4\xff\xd5\xd5\xc0\xc0\xc0\xc0\xc0\xea\xca\xea\xc1\xdd\xfa\xe5\xf5\xdc\xd5\xdf\xd1\xff\xd5\xea\xdd\xd5\xea\xea\xff\xea\xd5\xff\xe5\xff\xd5\xd5\xc0\xc0\xc0\xc0\xc0\xea\xc0\xd7\xc0\xd5\xea\xee\xea\xff\xca\xf7\xc0\xff\xd1\xfe\xdd\xd5\xea\xca\xff\xea\xd5\xff\xd9\xff\xd5\xd5\xc0\xc0\xc0\xc0\xf8\xea\xe0\xd5\xe8\xc5\xc5\xca\xfb\xff\xd9\xd5\xe2\xff\xc0\xfe\xef\xc4\xea\xe2\xff\xe4\xd5\xfa\xd5\xff\xd5\xd5\xc0\xc0\xc0\xe8\xe5\xea\xea\xc0\xea\xc1\xea\xe8\xc6\xef\xd6\xd5\xc8\xff\xc0\xff\xee\xc0\xea\xc8\xff\xe8\xd5\xee\xf5\xef\xd5\xd5\xc0\xc0\xe0\xd7\xfe\xea\xea\xc0\xea\xc4\xfb\xe2\xdd\xe8\xd5\xd5\xe2\xdd\xc0\xff\xeb\xe0\xea\xc0\xff\xf2\xd5\xfa\xdd\xeb\xe4\xd5\xc0\xc0\xde\xfa\xdf\xea\xea\xc0\xea\xe0\xe5\xee\xd7\xea\xd5\xea\xf4\xd7\xd4\xff\xe9\xe9\xea\xc0\xff\xcc\xd5\xee\xf7\xea\xea\xc0\xc0\xe8\xe5\xff\xe5\xea\xfa\xc0\xde\xe0\xfb\xea\xf5\xea\xf5\xeb\xdd\xd5\xdd\xff\xc0\xff\xea\xe0\xef\xea\xe1\xeb\xd5\xe0\xea\xc0\xe8\xe7\xfe\xdf\xfe\xc0\xd5\xc0\xf7\xc0\xff\xea\xff\xea\xfd\xfb\xf7\xed\xd7\xff\xe8\xff\xd7\xe2\xef\xc2\xd4\xea\xd5\xe4\xea\xe0\xde\xfa\xff\xe9\xff\xc0\xd5\xc0\xd5\xea\xf5\xeb\xf4\xff\xfd\xfb\xfd\xeb\xf7\xef\xee\xff\xf5\xea\xee\xe2\xda\xea\xd5\xdd\xea\xde\xfa\xff\xf7\xfe\xff\xc0\xc0\xc0\xd7\xee\xf7\xca\xff\xff\xff\xff\xff\xea\xf7\xd5\xff\xd6\xcb\xda\xfb\xc8\xea\xea\xd5\xf7\xee\xe9\xff\xff\xe9\xff\xff\xc0\xc0\xc0\xf5\xfb\xed\xea\xf6\xff\xff\xff\xff\xea\xff\xe4\xff\xdf\xf0\xe2\xf7\xca\xf0\xeb\xd5\xff\xf2\xfe\xff\xe7\xfe\xff\xdf\xc0\xc0\xc0\xd5\xef\xf5\xe6\xfd\xff\xff\xff\xff\xfe\xff\xec\xff\xd5\xfd\xc2\xfe\xc2\xd6\xf6\xd5\xfd\xe9\xff\xff\xea\xff\xff\xff\xc0\xc0\xc0\xf5\xff\xd4\xf5\xff\xff\xff\xff\xff\xff\xff\xff\xff\xe5\xc5\xe0\xff\xc2\xd4\xd5\xf5\xe5\xeb\xff\xe5\xff\xff\xff\xff\xc0\xc0\xea\xeb\xf6\xed\xc0\xff\xff\xff\xff\xff\xff\xff\xff\xff\xea\xff\xea\xee\xe8\xc9\xd5\xed\xd1\xff\xdf\xfa\xff\xdf\xff\xff\xc0\xc0\xea\xeb\xd5\xdb\xc0\xff\xff\xff\xff\xff\xff\xff\xff\xff\xe2\xff\xea\xfa\xe2\xc5\xf5\xeb\xe0\xff\xe9\xff\xff\xff\xff\xe5\xc0\xc0\xea\xea\xed\xca\xc0\xef\xff\xff\xd7\xff\xff\xff\xff\xff\xd5\xc5\xff\xfe\xea\xd1\xf7\xc0\xee\xd3\xfe\xff\xff\xff\xdf\xf4\xc0\xc0\xea\xeb\xc5\xc5\xc0\xeb\xff\xff\xd5\xff\xff\xff\xd7\xff\xff\xff\xff\xff\xea\xd4\xc8\xc0\xc0\xca\xff\xff\xff\xff\xdd\xfb\xc0\xc0\xd7\xff\xca\xea\xc0\xda\xff\xff\xff\xff\xff\xff\xff\xff\xef\xff\xff\xff\xea\xd1\xd0\xc2\xd8\xd9\xd0\xef\xff\xff\xf5\xff\xc0\xc0\xdf\xf5\xc5\xfa\xdd\xc1\xff\xff\xff\xff\xff\xff\xff\xff\xee\xfb\xff\xff\xea\xc5\xd4\xc4\xe6\xe6\xe6\xe4\xc3\xdf\xfe\xff\xc0\xc0\xdd\xfd\xe1\xff\xe9\xe0\xeb\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xea\xd1\xfd\xe0\xd9\xf9\xfd\xd9\xd9\xd0\xff\xff\xc0\xc0\xdf\xd5\xea\xdf\xfa\xc0\xea\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xc5\xe2\xd4\xd5\xd4\xe6\xee\xff\xff\xf6\xe4\xea\xed\xc0\xea\xeb\xd5\xee\xe5\xd7\xd0\xc8\xff\xff\xff\xff\xff\xff\xff\xd7\xef\xd7\xe0\xc8\xd5\xfe\xfd\xc0\xc9\xdb\xff\xdd\xd9\xca\xce\xc0\xea\xfb\xc0\xfb\xea\xf5\xc5\xd8\xeb\xff\xff\xff\xff\xff\xdf\xc0\xc2\xe0\xd5\xd6\xd4\xff\xff\xf4\xc0\xc2\xe6\xe7\xc6\xc2\xd5\xc0\xea\xee\xe2\xee\xfa\xff\xc1\xc6\xca\xff\xef\xff\xff\xff\xd1\xc8\xc0\xfe\xd5\xd5\xf7\xee\xff\xff\xfd\xd0\xc0\xc9\xc1\xea\xc4\xc0\xea\xea\xe2\xd6\xfe\xf5\xc5\xe6\xe5\xeb\xfe\xff\xff\xff\xc0\xe0\xfe\xff\xd5\xd4\xdd\xea\xff\xff\xff\xeb\xf4\xc0\xc0\xd7\xc0\xc0\xd7\xe6\xea\xd9\xff\xf7\xc5\xf6\xc7\xd4\xcf\xcf\xcf\xc1\xf8\xfe\xff\xff\xd1\xf5\xcb\xd4\xea\xff\xe5\xff\xff\xfd\xf8\xc5\xc0\xe8\xe5\xc5\xea\xe4\xff\xf5\xc5\xf5\xdf\xfa\xdc\xf0\xf8\xfe\xff\xff\xff\xff\xe0\xda\xda\xd2\xe2\xd7\xfe\xff\xff\xff\xd7\xc0\xc0\xfa\xea\xc0\xee\xe8\xff\xf7\xc0\xd2\xfd\xfd\xff\xff\xff\xff\xff\xff\xff\xff\xc8\xda\xf2\xe8\xd4\xfe\xff\xff\xff\xdf\xc0\xc0\xc0\xd5\xff\xc4\xea\xea\xff\xff\xf2\xe7\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xc0\xd9\xd1\xff\xd5\xff\xff\xff\xef\xc1\xc0\xc0\xc0\xc9\xff\xea\xea\xea\xff\xd5\xff\xd0\xeb\xff\xff\xff\xff\xff\xff\xff\xff\xff\xc0\xd1\xdd\xff\xff\xea\xff\xe7\xd7\xc0\xc0\xc0\xc0\xea\xff\xea\xea\xea\xff\xd5\xff\xdc\xdd\xff\xff\xff\xff\xff\xfd\xef\xff\xdd\xd0\xd0\xdd\xff\xff\xda\xfd\xc7\xc0\xc0\xc0\xc0\xc0\xff\xff\xea\xfa\xea\xff\xf7\xff\xd5\xdd\xff\xff\xff\xff\xc7\xea\xfd\xdb\xd5\xd4\xd5\xdd\xff\xff\xd5\xd7\xc0\xc0\xc0\xc0\xc0\xc0\x01\x00A=USR(&2C3A)\r\xc47')
# -------------------------------------------------------------------

# ---- IM2 constants ----
W, H = 64, 192                 # internal 2×3 grid size
TW, TH = 2, 3
COLS_T, ROWS_T = 32, 64        # 32 tiles wide, 64 tall (8×3 tiles at 256×192)
INJ_OFF, INJ_LEN = 743, 2048

# ---- Preview size ----
PREVIEW_W, PREVIEW_H = 256, 192

# ---- Debounce ----
DEBOUNCE_MS = 120

# ---- Dither options ----
DITHER_OPTS = [
    "Threshold",
    "Tile 2×3",
    "Floyd–Steinberg",
    "Ordered 8×8",
    "Halftone 45°",
    "Halftone 90°",
]

# ---- Encoding options ----
ENC_TRAD   = "Traditional"
ENC_DICT   = "Dot (DICT)"
ENC_ASCII  = "Full ASCII"
ENC_OPTS   = [ENC_TRAD, ENC_DICT, ENC_ASCII]

# ---- Ordered matrices ----
BAYER_8x8 = np.array([
 [ 0,48,12,60, 3,51,15,63],
 [32,16,44,28,35,19,47,31],
 [ 8,56, 4,52,11,59, 7,55],
 [40,24,36,20,43,27,39,23],
 [ 2,50,14,62, 1,49,13,61],
 [34,18,46,30,33,17,45,29],
 [10,58, 6,54, 9,57, 5,53],
 [42,26,38,22,41,25,37,21]], dtype=np.float32)

HALFTONE_8 = np.array([
 [24,10,12,26,35,47,49,37],
 [ 8, 0, 2,14,45,59,61,51],
 [22, 6, 4,16,43,57,63,53],
 [30,20,18,28,41,55,57,39],
 [34,46,48,36,25,11,13,27],
 [44,58,60,50, 9, 1, 3,15],
 [42,56,62,52,23, 7, 5,17],
 [32,54,40,38,31,21,19,29]], dtype=np.float32)

# ---- WAV defaults (for export) ----
WAV_DEFAULT_SR = 44100
WAV_DEFAULT_BITS = 16

# ---------- levels helper ----------
def apply_levels_u8(arr_u8: np.ndarray, black: int, white: int, gamma: float) -> np.ndarray:
    """y = clip((x-b)/(w-b),0,1) ** (1/gamma) * 255, applied to uint8 grayscale."""
    b = int(np.clip(black, 0, 255))
    w = int(np.clip(white, 0, 255))
    if w <= b:
        w = b + 1
    x = arr_u8.astype(np.float32) / 255.0
    y = (x - (b/255.0)) / ((w-b)/255.0)
    y = np.clip(y, 0.0, 1.0)
    g = max(1e-4, float(gamma))
    y = np.power(y, 1.0/g)
    return np.clip(y * 255.0, 0, 255).astype(np.uint8)

# ---------- dither helpers ----------
def ordered_dither(imgL: np.ndarray, matrix: np.ndarray) -> np.ndarray:
    m = (matrix - matrix.min())
    m = (m / (m.max() if m.max() else 1.0)) * 255.0
    h, w = imgL.shape
    mh, mw = m.shape
    tiled = np.tile(m, ((h+mh-1)//mh, (w+mw-1)//mw))[:h, :w]
    return (imgL >= tiled).astype(np.uint8)

def floyd_steinberg(imgL: np.ndarray, thresh: int) -> np.ndarray:
    a = imgL.astype(np.float32).copy()
    h, w = a.shape
    for y in range(h):
        for x in range(w):
            old = a[y, x]
            new = 255 if old >= thresh else 0
            err = old - new
            a[y, x] = new
            if x+1 < w:                 a[y,   x+1] += err * 7/16
            if y+1 < h and x > 0:       a[y+1, x-1] += err * 3/16
            if y+1 < h:                 a[y+1, x  ] += err * 5/16
            if y+1 < h and x+1 < w:     a[y+1, x+1] += err * 1/16
    return (a >= 128).astype(np.uint8)

def tile23_levels(gray_256x192: np.ndarray) -> np.ndarray:
    """Tile-based levels dither, fills per 2×3 tile in vertical order."""
    small = Image.fromarray(gray_256x192, mode="L").resize((W, H), Image.BICUBIC)
    dot = np.array(small, dtype=np.float32)
    bw = np.zeros((H, W), dtype=np.uint8)
    order = [(0,0),(1,0),(2,0),(0,1),(1,1),(2,1)]
    for tx in range(COLS_T):
        for tr in range(ROWS_T):
            y0, x0 = tr*TH, tx*TW
            block = dot[y0:y0+TH, x0:x0+TW]
            level = int(np.clip(round(block.mean()/255.0 * 6), 0, 6))
            for k in range(level):
                ry, rx = order[k]
                bw[y0+ry, x0+rx] = 1
    return bw

# ---------- dictionary helpers ----------
def _parse_char8x3_dict(char_map: Dict[int, Tuple[str,str,str]]) -> Dict[int, np.ndarray]:
    """Convert CHAR8x3 into code -> (3×8) uint8 array of 0/1."""
    out: Dict[int, np.ndarray] = {}
    for code, rows in char_map.items():
        if not isinstance(rows, (tuple, list)) or len(rows) != 3:
            continue
        ok = True
        acc = np.zeros((3, 8), dtype=np.uint8)
        for r, s in enumerate(rows):
            if not isinstance(s, str) or len(s) != 8 or any(c not in "01" for c in s):
                ok = False; break
            acc[r, :] = np.frombuffer(bytes(s, "ascii"), dtype=np.uint8) - ord('0')
        if ok:
            out[int(code) & 0xFF] = acc
    # Ensure we always have a blank (C0) tile
    if 0xC0 not in out:
        out[0xC0] = np.zeros((3, 8), dtype=np.uint8)
    return out

PAT8: Dict[int, np.ndarray] = _parse_char8x3_dict(CHAR8x3)

# Fast sets for lookups
C0_FF: List[int] = [c for c in sorted(PAT8.keys()) if 0xC0 <= c <= 0xFF]
ALL_CODES: List[int] = sorted(PAT8.keys())  # Full ASCII includes C0–FF as well

def _bits6_from_8x3(tile8: np.ndarray) -> int:
    """
    Collapse an 8×3 binary tile to 2×3 (6 bits) by averaging each 4-pixel column band.
    Bit order matches hardware: row-major (r0c0,r0c1,r1c0,r1c1,r2c0,r2c1) => bits 0..5.
    """
    # left/right columns are 4 pixels wide each
    b = 0
    for ry in range(3):
        left_on  = tile8[ry, 0:4].mean() >= 0.5
        right_on = tile8[ry, 4:8].mean() >= 0.5
        if left_on:  b |= (1 << (ry*2 + 0))
        if right_on: b |= (1 << (ry*2 + 1))
    return b & 0x3F

def _render_c0ff_to_8x3(bits6: int) -> np.ndarray:
    """Synthesize an 8×3 preview from a 2×3 pattern by widening each column to 4 pixels."""
    out = np.zeros((3, 8), dtype=np.uint8)
    for ry in range(3):
        l = 1 if (bits6 & (1 << (ry*2+0))) else 0
        r = 1 if (bits6 & (1 << (ry*2+1))) else 0
        out[ry, 0:4] = l
        out[ry, 4:8] = r
    return out

# ---------- core encode/decode ----------
def center_crop_4_3_box(src_w, src_h, cx, cy, zoom):
    target_ratio = 4/3
    if src_w/src_h >= target_ratio:
        max_h = src_h; max_w = int(round(max_h*target_ratio))
    else:
        max_w = src_w; max_h = int(round(max_w/target_ratio))
    w = max(32, int(round(max_w/zoom)))
    h = int(round(w/target_ratio))
    halfw, halfh = w//2, h//2
    L = max(0, min(src_w - w, cx - halfw))
    T = max(0, min(src_h - h, cy - halfh))
    return (L, T, L+w, T+h)

def _make_bw_256(im_cropped: Image.Image, thresh: int, dmode: str,
                 levels: Optional[tuple], invert: bool) -> np.ndarray:
    """
    Produce a 256×192 binary image (uint8 0/1), after levels + chosen dithering.
    """
    gray_big = im_cropped.convert("L").resize((256, 192), Image.BICUBIC)
    arr = np.array(gray_big, dtype=np.uint8)
    # levels
    if levels is not None:
        b, w, g = levels
        arr = apply_levels_u8(arr, int(b), int(w), float(g))
    m = dmode.lower()
    if m.startswith("floyd"):
        bw_big = floyd_steinberg(arr, thresh)
    elif m.startswith("ordered"):
        bw_big = ordered_dither(arr, BAYER_8x8)
    elif "90" in m:
        bw_big = ordered_dither(arr, np.rot90(HALFTONE_8))
    elif "45" in m:
        bw_big = ordered_dither(arr, HALFTONE_8)
    elif m.startswith("tile"):
        # “levels-by-tile” dither creates 64×192 — convert up to 256×192 to continue in tile-space
        bw64 = tile23_levels(arr)  # 64×192
        bw_big = np.array(Image.fromarray((bw64*255).astype(np.uint8), "L").resize((256,192), Image.NEAREST)) >= 128
        bw_big = bw_big.astype(np.uint8)
    else:
        bw_big = (arr >= thresh).astype(np.uint8)
    if invert:
        bw_big = 1 - bw_big
    return bw_big.astype(np.uint8)

def encode_tiles_transposed(bw64: np.ndarray) -> bytes:
    """
    Traditional (2×3) flow: consume a 64×192 0/1 array, emit 2048 bytes using 0xC0|bits,
    first in (x*64 + r) layout, then transposed to IM2 stream.
    """
    out = bytearray(COLS_T * ROWS_T)  # 32*64
    for x in range(COLS_T):
        for r in range(ROWS_T):
            y0, x0 = r*TH, x*TW
            t = bw64[y0:y0+TH, x0:x0+TW]
            b = (int(t[0,0])<<0) | (int(t[0,1])<<1) | (int(t[1,0])<<2) | (int(t[1,1])<<3) | (int(t[2,0])<<4) | (int(t[2,1])<<5)
            out[x*ROWS_T + r] = 0xC0 | (b & 0x3F)  # blank is 0xC0
    return bytes(out)

def inverse_transpose(bufT: bytes) -> bytes:
    """Transpose 32×64 <-> 64×32 memory layout."""
    out = bytearray(64*32)
    for x in range(64):
        for r in range(32):
            out[x*32 + r] = bufT[r*64 + x]
    return bytes(out)

def encode_dict_dot_from_bw256(bw256: np.ndarray) -> bytes:
    """
    Dot (DICT): select C0–FF by collapsing each 8×3 tile to a 2×3 code (bits6), then 0xC0|bits.
    Always use 0xC0 if the tile is completely black (avoid 0x00 artefacts).
    """
    out = bytearray(COLS_T * ROWS_T)
    for tx in range(COLS_T):
        for tr in range(ROWS_T):
            y0, x0 = tr*3, tx*8
            tile8 = bw256[y0:y0+3, x0:x0+8]  # shape (3,8)
            if tile8.sum() == 0:
                code = 0xC0
            else:
                bits = _bits6_from_8x3(tile8)
                code = 0xC0 | bits
            out[tx*ROWS_T + tr] = code
    return bytes(out)

def encode_full_ascii_from_bw256(bw256: np.ndarray) -> bytes:
    """
    Full ASCII: match each 8×3 tile to the closest glyph in the entire CHAR8x3 (including C0–FF).
    If a tile is completely black OR the best code is 0x00, force code 0xC0 (avoid artefacts).
    """
    out = bytearray(COLS_T * ROWS_T)
    # Prebundle patterns for speed
    codes = ALL_CODES
    pats  = [PAT8[c] for c in codes]
    # Flatten patterns to (N, 24)
    patsF = np.stack(pats, axis=0).reshape(len(codes), 24).astype(np.uint8)

    for tx in range(COLS_T):
        for tr in range(ROWS_T):
            y0, x0 = tr*3, tx*8
            tile8 = bw256[y0:y0+3, x0:x0+8]
            if tile8.sum() == 0:
                code = 0xC0
            else:
                tF = tile8.reshape(24).astype(np.uint8)
                # Hamming distance to all codes (vectorized)
                # XOR then popcount -> sum since 0/1
                diffs = np.abs(patsF - tF).sum(axis=1)
                best_idx = int(np.argmin(diffs))
                code = codes[best_idx] & 0xFF
                if code == 0x00:  # hard rule to avoid control/artefacts
                    code = 0xC0
            out[tx*ROWS_T + tr] = code
    return bytes(out)

def build_stream_from_image(im: Image.Image, crop_box, thresh, dmode,
                            levels: Optional[tuple], invert: bool,
                            encoding: str) -> bytes:
    """
    Build the 2048-byte IM2 stream according to selected encoding.
    - Traditional: use 64×192 2×3 pack
    - Dot (DICT): 256×192 -> 8×3 tiles -> C0–FF packed (still transposed)
    - Full ASCII: 256×192 -> match 8×3 tiles vs full dict (including C0–FF)
    """
    cropped = im.crop(crop_box)
    # Always prepare a 256×192 0/1 image (so DICT/ASCII are consistent)
    bw256 = _make_bw_256(cropped, thresh, dmode, levels, invert)

    if encoding == ENC_TRAD:
        # Downscale to 64×192 for 2×3 packing
        small = Image.fromarray((bw256*255).astype(np.uint8), mode="L").resize((W, H), Image.NEAREST)
        bw64 = (np.array(small) >= 128).astype(np.uint8)
        bufT = encode_tiles_transposed(bw64)  # 32×64 layout
    elif encoding == ENC_DICT:
        bufT = encode_dict_dot_from_bw256(bw256)  # 32×64 bytes
    else:  # ENC_ASCII
        bufT = encode_full_ascii_from_bw256(bw256)  # 32×64 bytes

    # Transpose to 64×32 IM2 stream
    return inverse_transpose(bufT)

def decode_preview_from_stream(stream: bytes, encoding: str, vlines=False) -> Image.Image:
    """
    Mode-aware preview:
    - Traditional: expand 2×3 bits into 256×192
    - Dot (DICT): expand using dictionary’s C0–FF (or synthesize 2×3->8×3 if not present)
    - Full ASCII: expand using CHAR8x3 for *all* codes (C0–FF included)
    """
    if len(stream) != 2048:
        raise ValueError("Stream must be 2048 bytes")

    # transpose 64×32 -> 32×64 (T holds tile bytes in (x*64 + r) order)
    T = bytearray(32*64)
    for x in range(64):
        for r in range(32):
            T[r*64 + x] = stream[x*32 + r]

    # Build 256×192 image
    img = np.zeros((PREVIEW_H, PREVIEW_W), dtype=np.uint8)

    def draw_tile8(y0, x0, pat8):
        img[y0+0, x0:x0+8] = (pat8[0]*255)
        img[y0+1, x0:x0+8] = (pat8[1]*255)
        img[y0+2, x0:x0+8] = (pat8[2]*255)

    # Iterate tiles
    for x in range(32):
        for r in range(64):
            b = T[x*64 + r]
            y0, x0 = r*3, x*8

            if encoding == ENC_TRAD:
                bits = b & 0x3F
                pat8 = _render_c0ff_to_8x3(bits)
                draw_tile8(y0, x0, pat8)
            elif encoding == ENC_DICT:
                # Prefer dictionary’s version of C0–FF; if missing, synthesize from bits.
                if b in PAT8:
                    draw_tile8(y0, x0, PAT8[b])
                else:
                    bits = (b & 0x3F) if (0xC0 <= b <= 0xFF) else 0
                    pat8 = _render_c0ff_to_8x3(bits)
                    draw_tile8(y0, x0, pat8)
            else:  # ENC_ASCII
                code = b
                # Force 0x00 to 0xC0 in preview as well (matches encoder rule)
                if code == 0x00:
                    code = 0xC0
                pat = PAT8.get(code, PAT8.get(0xC0, np.zeros((3,8), np.uint8)))
                draw_tile8(y0, x0, pat)

    out = Image.fromarray(img, mode="L")
    if vlines:
        arr = np.array(out)
        tile_w = 8
        for x in range(tile_w, arr.shape[1], tile_w):
            arr[:, x-1] = 0
        out = Image.fromarray(arr, mode="L")
    return out

# ---------- GTP helpers ----------
def find_a5(buf: bytes) -> int:
    i = buf.find(b'\xA5')
    if i < 0:
        raise ValueError("A5 not found in template")
    return i

def payload_start_after_ext_header(a5_idx: int) -> int:
    return a5_idx + 1 + 8

def recompute_checksum_wholefile(mut: bytearray):
    a5 = find_a5(mut)
    s = sum(mut[a5:-2]) & 0xFF
    mut[-2] = (0xFF - s) & 0xFF

def inject_stream(template: bytes, stream2k: bytes) -> bytes:
    if len(stream2k) != INJ_LEN:
        raise ValueError("IM2 stream must be exactly 2048 bytes")
    mut = bytearray(template)
    a5  = find_a5(mut)
    p0  = payload_start_after_ext_header(a5)
    start = p0 + INJ_OFF
    end   = start + INJ_LEN
    if end > len(mut) - 2:
        raise ValueError(f"template too short: need {end}, have {len(mut)}")
    mut[start:end] = stream2k
    recompute_checksum_wholefile(mut)
    return bytes(mut)

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

# ======================
# GUI
# ======================
class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Galaksija HIRES Maker")
        set_embedded_icon(self)
        self.configure(bg="#222")
        self.resizable(False, False)

        # Worker (single) to serialize heavy jobs
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="worker")
        self._preview_job: Optional[Future] = None
        self._job_token = 0
        self._lock = threading.Lock()

        # State
        self.src_path = None
        self.src_img  = None
        self.view_zoom = 1.0
        self.view_cx = 0
        self.view_cy = 0
        self.drag_last = None
        self.tk_img = None
        self._pending = None
        self._last_stream = None
        self._last_encoding = ENC_TRAD

        # UI
        self.canvas = tk.Canvas(self, bg="#000", width=PREVIEW_W, height=PREVIEW_H,
                                highlightthickness=0)
        self.canvas.grid(row=0, column=0, rowspan=12, padx=6, pady=6)

        right = ttk.Frame(self); right.grid(row=0, column=1, sticky="ns", padx=8, pady=8)

        top = ttk.Frame(right); top.pack(fill="x")
        self.btn_open = ttk.Button(top, text="Open Image…", command=self.open_image)
        self.btn_open.pack(side="left")
        self.btn_gtp  = ttk.Button(top, text="Generate GTP…", command=self.make_gtp, state="disabled")
        self.btn_gtp.pack(side="right")

        opts = ttk.LabelFrame(right, text="Options"); opts.pack(fill="x", pady=(8,6))
        ttk.Label(opts, text="Threshold").grid(row=0, column=0, sticky="w")
        self.th_slider = ttk.Scale(opts, from_=0, to=255, orient="horizontal",
                                   command=lambda e: self.schedule_update())
        self.th_slider.set(128)
        opts.columnconfigure(1, weight=1)
        self.th_slider.grid(row=0, column=1, sticky="ew", padx=6)

        ttk.Label(opts, text="Dither").grid(row=1, column=0, sticky="w")
        self.dither = tk.StringVar(value=DITHER_OPTS[0])
        self.dmenu = ttk.OptionMenu(opts, self.dither, DITHER_OPTS[0], *DITHER_OPTS,
                                    command=lambda *_: self.schedule_update())
        self.dmenu.grid(row=1, column=1, sticky="ew", padx=6)

        # Encoding group
        encf = ttk.LabelFrame(right, text="Encoding"); encf.pack(fill="x", pady=(6,6))
        self.encoding = tk.StringVar(value=ENC_TRAD)
        for i, label in enumerate(ENC_OPTS):
            ttk.Radiobutton(encf, text=label, value=label, variable=self.encoding,
                            command=self.schedule_update).grid(row=0, column=i, sticky="w", padx=(0,8))

        # Invert
        self.invert = tk.BooleanVar(value=False)
        ttk.Checkbutton(opts, text="Invert", variable=self.invert,
                        command=self.schedule_update).grid(row=2, column=0, columnspan=2, sticky="w", pady=(4,0))

        # Levels group
        lvl = ttk.LabelFrame(right, text="Levels"); lvl.pack(fill="x", pady=(6,6))
        ttk.Label(lvl, text="Black").grid(row=0, column=0, sticky="w")
        self.lv_black_scale = ttk.Scale(lvl, from_=0, to=255, orient="horizontal",
                                        command=lambda e: self.schedule_update())
        self.lv_black_scale.set(0)
        lvl.columnconfigure(1, weight=1)
        self.lv_black_scale.grid(row=0, column=1, sticky="ew", padx=6)

        ttk.Label(lvl, text="White").grid(row=1, column=0, sticky="w")
        self.lv_white_scale = ttk.Scale(lvl, from_=0, to=255, orient="horizontal",
                                        command=lambda e: self.schedule_update())
        self.lv_white_scale.set(255)
        self.lv_white_scale.grid(row=1, column=1, sticky="ew", padx=6)

        ttk.Label(lvl, text="Gamma").grid(row=2, column=0, sticky="w")
        self.lv_gamma_scale = ttk.Scale(lvl, from_=0.10, to=3.00, orient="horizontal",
                                        command=lambda e: self.schedule_update())
        self.lv_gamma_scale.set(1.00)
        self.lv_gamma_scale.grid(row=2, column=1, sticky="ew", padx=6)

        self.btn_reset_levels = ttk.Button(lvl, text="Reset Levels",
                                           command=self.reset_levels)
        self.btn_reset_levels.grid(row=3, column=0, columnspan=2, pady=(6,0))

        templ = ttk.LabelFrame(right, text="Template"); templ.pack(fill="x", pady=(6,6))
        self.tpl_sel = tk.StringVar(value="G40")
        ttk.Radiobutton(templ, text="Galaksija 40", value="G40", variable=self.tpl_sel,
                        command=self.on_template_change).pack(anchor="w")
        ttk.Radiobutton(templ, text="Original", value="ORG", variable=self.tpl_sel,
                        command=self.on_template_change).pack(anchor="w")

        # WAV export (Original only)
        self.export_wav = tk.BooleanVar(value=False)
        self.chk_wav = ttk.Checkbutton(templ, text="Also export WAV (Experimental)",
                                       variable=self.export_wav)
        self.chk_wav.pack(anchor="w")

        self.vlines = tk.BooleanVar(value=False)
        ttk.Checkbutton(right, text="Vertical separators", variable=self.vlines,
                        command=self.schedule_update).pack(anchor="w", pady=(6,0))

        self.status = tk.StringVar(value="Open an image…")
        # ttk.Label(right, textvariable=self.status).pack(fill="x", pady=(8,0))

        # Mouse
        self.canvas.bind("<ButtonPress-1>", self.on_drag_start)
        self.canvas.bind("<B1-Motion>", self.on_drag_move)
        self.canvas.bind("<ButtonRelease-1>", self.on_drag_end)
        self.canvas.bind("<MouseWheel>", self.on_wheel)     # Windows/Mac
        self.canvas.bind("<Button-4>", self.on_wheel_up)    # Linux
        self.canvas.bind("<Button-5>", self.on_wheel_down)  # Linux

        # Window geometry
        self.update_idletasks()
        w = PREVIEW_W + 320
        h = max(PREVIEW_H + 20, self.winfo_reqheight())
        self.geometry(f"{w}x{h}")
        self.minsize(w, h)

        # Initialize controls state
        self._update_wav_checkbox()

    # ---- helpers ----
    def reset_levels(self):
        self.lv_black_scale.set(0)
        self.lv_white_scale.set(255)
        self.lv_gamma_scale.set(1.0)
        self.schedule_update()

    def on_template_change(self):
        self._update_wav_checkbox()
        self.schedule_update()

    def _update_wav_checkbox(self):
        if self.tpl_sel.get() == "ORG":
            self.chk_wav.state(["!disabled"])
        else:
            self.export_wav.set(False)
            self.chk_wav.state(["disabled"])

    # Debounce
    def schedule_update(self):
        if self._pending is not None:
            self.after_cancel(self._pending)
        self._pending = self.after(DEBOUNCE_MS, self.kick_preview_job)

    # Mouse panning/zoom
    def on_drag_start(self, e): self.drag_last = (e.x, e.y)
    def on_drag_move(self, e):
        if not self.src_img or not self.drag_last: return
        dx = e.x - self.drag_last[0]; dy = e.y - self.drag_last[1]
        sw, sh = self.src_img.size
        box = center_crop_4_3_box(sw, sh, self.view_cx, self.view_cy, self.view_zoom)
        cw = box[2]-box[0]; ch = box[3]-box[1]
        self.view_cx = int(np.clip(self.view_cx - dx * (cw/PREVIEW_W), 0, sw-1))
        self.view_cy = int(np.clip(self.view_cy - dy * (ch/PREVIEW_H), 0, sh-1))
        self.drag_last = (e.x, e.y)
        self.schedule_update()
    def on_drag_end(self, e): self.drag_last = None
    def on_wheel(self, e):
        if not self.src_img: return
        self.zoom_adjust(1.1 if e.delta > 0 else 0.9)
    def on_wheel_up(self, e):
        if not self.src_img: return
        self.zoom_adjust(1.1)
    def on_wheel_down(self, e):
        if not self.src_img: return
        self.zoom_adjust(0.9)
    def zoom_adjust(self, factor):
        self.view_zoom = float(np.clip(self.view_zoom * factor, 0.2, 8.0))
        self.schedule_update()

    # File ops
    def open_image(self):
        p = filedialog.askopenfilename(
            title="Open image",
            filetypes=[("Images", "*.png *.jpg *.jpeg *.bmp *.gif *.webp"),
                       ("PNG", "*.png"), ("JPEG", "*.jpg *.jpeg"), ("All files", "*.*")]
        )
        if not p: return
        self.src_path = Path(p)
        try:
            self.src_img = Image.open(self.src_path).convert("RGB")
        except Exception as ex:
            messagebox.showerror("Error", f"Failed to open image:\n{ex}")
            return
        sw, sh = self.src_img.size
        self.view_cx, self.view_cy = sw//2, sh//2
        self.view_zoom = 1.0
        self.btn_gtp.config(state="normal")
        self.kick_preview_job()

    # Background preview job
    def kick_preview_job(self):
        self._pending = None
        if not self.src_img:
            self.canvas.delete("all")
            self.status.set("Open an image…")
            return

        with self._lock:
            self._job_token += 1
            token = self._job_token

        self.status.set("Rendering preview…")
        self.btn_open.config(state="disabled")
        self.btn_gtp.config(state="disabled")

        im = self.src_img
        sw, sh = im.size
        box = center_crop_4_3_box(sw, sh, self.view_cx, self.view_cy, self.view_zoom)
        thresh = int(self.th_slider.get())
        dmode  = self.dither.get()
        vlines = self.vlines.get()
        black = int(self.lv_black_scale.get())
        white = int(self.lv_white_scale.get())
        gamma = float(self.lv_gamma_scale.get())
        invert = bool(self.invert.get())
        levels = (black, white, gamma)
        enc    = self.encoding.get()

        def work():
            stream = build_stream_from_image(im, box, thresh, dmode, levels, invert, enc)
            disp   = decode_preview_from_stream(stream, enc, vlines=vlines)
            return (token, stream, disp, levels, invert, enc)

        future = self.executor.submit(work)
        future.add_done_callback(self._on_preview_done)

    def _on_preview_done(self, fut: Future):
        try:
            token, stream, disp, levels, invert, enc = fut.result()
        except Exception as ex:
            self.after(0, lambda: messagebox.showerror("Error", f"Preview failed:\n{ex}"))
            self.after(0, lambda: (self.btn_open.config(state="normal"),
                                   self.btn_gtp.config(state="normal")))
            return

        def apply_result():
            with self._lock:
                if token != self._job_token:
                    return
            self.canvas.delete("all")
            self.tk_img = ImageTk.PhotoImage(disp)
            self.canvas.create_image(0, 0, image=self.tk_img, anchor="nw")
            src = self.src_path.name if self.src_path else "(none)"
            b,w,g = levels
            inv_txt = " | INV" if invert else ""
            self.status.set(f"{src} | {self.dither.get()} | {enc} | thr {int(self.th_slider.get())} "
                            f"| L:{b}/{w} γ:{g:.2f}{inv_txt} | zoom {self.view_zoom:.2f}")
            self.btn_open.config(state="normal")
            self.btn_gtp.config(state="normal")
            self._last_stream = stream
            self._last_encoding = enc

        self.after(0, apply_result)

    def make_gtp(self):
        if not self.src_img:
            messagebox.showinfo("No image", "Open an image first.")
            return

        tpl_name = self.tpl_sel.get()
        tpl = G40HEX if tpl_name == "G40" else GORG
        if not tpl:
            messagebox.showerror("Missing template", f"{tpl_name} template bytes are empty. Paste them into the script.")
            return

        self.btn_gtp.config(state="disabled")
        self.status.set("Building GTP…")

        enc = self._last_encoding
        stream = getattr(self, "_last_stream", None)
        if stream is None:
            sw, sh = self.src_img.size
            box = center_crop_4_3_box(sw, sh, self.view_cx, self.view_cy, self.view_zoom)
            thresh = int(self.th_slider.get())
            dmode  = self.dither.get()
            levels = (int(self.lv_black_scale.get()),
                      int(self.lv_white_scale.get()),
                      float(self.lv_gamma_scale.get()))
            invert = bool(self.invert.get())
            def build(): return build_stream_from_image(self.src_img, box, thresh, dmode, levels, invert, enc)
            fut = self.executor.submit(build)
            fut.add_done_callback(lambda f: self._finish_gtp(f, tpl))
        else:
            fut = self.executor.submit(lambda: inject_stream(tpl, stream))
            fut.add_done_callback(lambda f: self._finish_gtp_injected(f))

    def _finish_gtp(self, fut: Future, tpl):
        try:
            stream = fut.result()
            data = inject_stream(tpl, stream)
        except Exception as ex:
            self.after(0, lambda: (messagebox.showerror("Error", f"GTP build failed:\n{ex}"),
                                   self.btn_gtp.config(state="normal")))
            return
        self._save_gtp_on_main(data)

    def _finish_gtp_injected(self, fut: Future):
        try:
            data = fut.result()
        except Exception as ex:
            self.after(0, lambda: (messagebox.showerror("Error", f"GTP injection failed:\n{ex}"),
                                   self.btn_gtp.config(state="normal")))
            return
        self._save_gtp_on_main(data)

    def _save_gtp_on_main(self, data: bytes):
        def go():
            savep = filedialog.asksaveasfilename(defaultextension=".gtp",
                filetypes=[("Galaksija tape","*.gtp"),("All files","*.*")],
                initialfile="out.gtp")
            if not savep:
                self.btn_gtp.config(state="normal")
                self.status.set("Canceled.")
                return
            Path(savep).write_bytes(data)
            a5 = find_a5(data); p0 = payload_start_after_ext_header(a5)
            msg = (f"Saved {savep}\nA5@{a5}, payload_start={p0}, "
                   f"injected @{p0+INJ_OFF}..{p0+INJ_OFF+INJ_LEN-1}\n"
                   f"checksum=0x{data[-2]:02X}")

            # If Original template and WAV export requested, save WAV too
            if self.tpl_sel.get() == "ORG" and self.export_wav.get():
                wav_path = filedialog.asksaveasfilename(defaultextension=".wav",
                    filetypes=[("WAV audio","*.wav"),("All files","*.*")],
                    initialfile=str(Path(savep).with_suffix(".wav").name))
                if wav_path:
                    try:
                        save_wav_from_gtp(data, Path(wav_path),
                                          sr=WAV_DEFAULT_SR, bits=WAV_DEFAULT_BITS)
                        msg += f"\nWAV saved: {wav_path} @ {WAV_DEFAULT_SR} Hz / {WAV_DEFAULT_BITS}-bit"
                    except Exception as ex:
                        messagebox.showerror("WAV export failed", f"Could not write WAV:\n{ex}")

            messagebox.showinfo("Done", msg)
            self.btn_gtp.config(state="normal")
            self.status.set("Done.")
        self.after(0, go)

# ======================
# CLI mode
# ======================
def run_cli():
    epilog = textwrap.dedent(f"""
        Examples:
          # Basic (default Threshold)
          python gal_hres_gui.py --image in.jpg --out out.gtp --template G40

          # With Levels + tile dither + invert and a preview PNG
          python gal_hres_gui.py --image in.png --out out.gtp \\
                                 --template ORG --dither "Tile 2×3" \\
                                 --threshold 140 --black 10 --white 245 --gamma 0.9 \\
                                 --invert --preview preview.png

          # DICT encoding (C0–FF)
          python gal_hres_gui.py --image in.png --out out.gtp --template ORG \\
                                 --encoding "{ENC_DICT}" --dither "Ordered 8×8" --threshold 132

          # Full ASCII (entire CHAR8x3, includes C0–FF)
          python gal_hres_gui.py --image in.png --out out.gtp --template G40 \\
                                 --encoding "{ENC_ASCII}" --dither "Floyd–Steinberg" --threshold 128
    """).strip()

    ap = argparse.ArgumentParser(
        description="Convert an image to a Galaksija IM2 2KB stream and inject into a GTP (GUI if no args).",
        epilog=epilog,
        formatter_class=argparse.RawTextHelpFormatter
    )
    ap.add_argument("--image", type=Path, help="Input image file (png/jpg/…)")
    ap.add_argument("--out", type=Path, help="Output GTP path")
    ap.add_argument("--template", choices=["G40","ORG"], default="G40",
                    help="GTP template to use (Galaksija 40 or Original).")
    ap.add_argument("--encoding", choices=ENC_OPTS, default=ENC_TRAD,
                    help="Encoding mode.")
    ap.add_argument("--dither", choices=[o for o in DITHER_OPTS], default="Threshold",
                    help="Dithering method (default: Threshold).")
    ap.add_argument("--threshold", type=int, default=128,
                    help="Threshold for Threshold/Floyd/Ordered/Halftone (default: 128).")
    ap.add_argument("--black", type=int, default=0, help="Levels black point (0..255).")
    ap.add_argument("--white", type=int, default=255, help="Levels white point (0..255).")
    ap.add_argument("--gamma", type=float, default=1.0, help="Levels gamma (>0).")
    ap.add_argument("--invert", action="store_true", help="Invert final 1-bit bitmap.")
    ap.add_argument("--vlines", action="store_true",
                    help="Draw vertical tile separators in preview PNG.")
    ap.add_argument("--preview", type=Path,
                    help="Optional preview PNG to write (256×192).")
    ap.add_argument("--wav", type=Path,
                    help="Optional WAV output (only valid with --template ORG)")
    args = ap.parse_args()

    if not args.image or not args.out:
        App().mainloop()
        return

    # Template presence check if saving a GTP
    try:
        tpl = G40HEX if args.template == "G40" else GORG
    except NameError:
        tpl = None
    if tpl is None or len(tpl) == 0:
        sys.exit(f"Error: {args.template} template is empty. Paste the bytes into the script.")

    im = Image.open(args.image).convert("RGB")
    sw, sh = im.size
    cx, cy, zoom = sw//2, sh//2, 1.0
    crop = center_crop_4_3_box(sw, sh, cx, cy, zoom)

    stream = build_stream_from_image(
        im, crop, int(args.threshold), args.dither,
        (int(args.black), int(args.white), float(args.gamma)),
        bool(args.invert), args.encoding
    )
    out = inject_stream(tpl, stream)
    args.out.write_bytes(out)

    if args.preview:
        prev = decode_preview_from_stream(stream, args.encoding, vlines=args.vlines)
        prev.save(args.preview)

    print(f"OK: {args.out} (template={args.template}, encoding={args.encoding}, dither={args.dither}, "
          f"threshold={args.threshold}, levels={args.black}/{args.white}, "
          f"gamma={args.gamma}, invert={args.invert})")
    if args.preview:
        print(f"Preview: {args.preview}")

    if args.wav:
        if args.template != "ORG":
            sys.exit("--wav is only supported with --template ORG")
        save_wav_from_gtp(out, args.wav, sr=WAV_DEFAULT_SR, bits=WAV_DEFAULT_BITS)
        print(f"WAV: {args.wav} ({WAV_DEFAULT_SR} Hz, {WAV_DEFAULT_BITS}-bit)")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        run_cli()
    else:
        App().mainloop()
