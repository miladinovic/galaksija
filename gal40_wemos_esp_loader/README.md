# Serial Communication on the Galaksija  
### 19200 bps, ROM routines, timing limits, and practical design patterns

The Galaksija has no UART hardware.  
Everything — transmission *and* reception — is implemented in software, using:

- tight assembly loops  
- interrupts  
- carefully timed delay loops  
- simple handshaking conventions

This document explains **how that works**, what the real limits are, and why our BBS client and tools use specific patterns like ENQ-based input requests.

---

## 1️⃣ How the ROM serial routines work

Galaksija uses two key ROM routines:

| Purpose | Symbol | Address |
|--------|--------|--------|
| Send byte over serial | `TXBYTE` | `0xB77A` |
| Receive byte (with interrupt) | `rxbyte_rt / rxbyte2_rt` | `0xB838 / 0xB83B` |

### TX (transmit)

`TXBYTE`:

1. **Bit-bangs** the TX line  
2. Sets / clears the output port bit at the exact timing for each bit  
3. Sends:  
   - start bit  
   - 8 data bits  
   - stop bit

Because there is **no hardware buffering**, the CPU is 100% busy while transmitting.

---

### RX (receive, via interrupt + polling)

The ROM interrupt handler is wired so that:

- when a bit sequence arrives,
- the CPU is interrupted,
- a small routine samples the line at the correct times,
- and stores the received byte into an internal latch.

Then it sets:

```
RxFLAG bit0 = 0   (byte ready)
```

The ROM receive routines (`rxbyte_rt`, `rxbyte2_rt`) then:

- pre-load `RxFLAG` to 1 before waiting,
- sit in a loop until the interrupt logic toggles bit 0 of `RxFLAG` to 0 when a full byte has just been received (typically after seeing a 0 start bit and timing the rest of the bits),
- immediately read the latched byte from the internal buffer.

`RxFLAG` itself is **not a stable state** you maintain in software. The interrupt routine *continuously updates* it on every received byte. You usually do **not** write it back yourself: if you are not watching it at the moment the bit goes 1→0, the transition is simply missed — and that byte is effectively lost. So, in practice, **watching RxFLAG means “don’t look away while bytes are arriving”.**

---

## 2️⃣ How Galaksija reaches 19200 baud (bit banging + interrupt)

Galaksija’s CPU runs at **3.072 MHz**.

A single bit at **19200 bps** lasts:

```
1 / 19200 ≈ 52 microseconds
```

At ~3 MHz, that means:

```
≈ 160 CPU cycles per bit
```

That’s *just barely enough* to:

- decode the incoming data bit  
- adjust timers  
- return from interrupt  
- and continue BASIC / other tasks  

That’s why the interrupt handler is tightly optimized — **not a single wasted instruction**.

---

## 3️⃣ Is 19200 baud realistic?

Yes — but **only under constraints**:

✔ RX timing relies on interrupts  
✔ CPU must not disable interrupts during reception  
✔ Long routines (graphics, floating-point, scrolling) risk losing bits  

The ROM receiver works because:

- it samples mid-bit  
- it uses minimal CPU inside the ISR  
- it immediately signals `RxFLAG` for BASIC / custom code to read  

But **the system is operating near its limit**.

---

## 4️⃣ Why this baudrate is “tight” (and what happens at lower rates)

At **19200 bps**:

- every missed interrupt = **lost byte**  
- prolonged `DI` sections = data corruption  
- background tasks (like drawing) easily outrun the buffer  

At **9600 bps**:

```
≈ 104 µs per bit  
≈ 320 CPU cycles per bit
```

That’s **twice the breathing room**.  

Often you can:

- poll keyboard  
- do small logic  
- occasionally disable interrupts safely  

…without losing data.

So:

> 19200 bps requires discipline.  
> 9600 bps is far more forgiving.

---

## 5️⃣ Why RxFLAG becomes “blocking” at 19200 bps

A typical BASIC-style approach:

```
wait until RxFLAG == 0
read byte
repeat
```

At 19200 bps:

- you must check constantly  
- you cannot wander off to do work  
- especially not to scan the keyboard  

### Keyboard scanning cost

Keyboard scanning:

- walks the matrix  
- debounces  
- updates cursor / screen  

This can easily take **hundreds of microseconds** — *multiple serial bit periods.*

Result:

❌ bytes lost  
❌ framing errors  
❌ corrupted buffers  

So at 19200 bps, `RxFLAG` acts like a **blocking call** even though it looks like polling.

---

## Standard Galaksija serial protocol (and reserved opcodes)

The “G40‑style” serial protocol that most Galaksija tools follow is intentionally simple.  
Every transmission is made of **fixed‑size 16‑byte frames**, preceded by a small preamble and a sync byte:

```
[00..00] FF D6  <16‑byte body>  <checksum>
```

- `00..00`  — optional idle preamble
- `FF`      — start marker
- `D6`      — protocol sync byte
- **body**  — application payload (padded if shorter)
- **checksum** — `sum(body) & 0xFF`

⚠️ **Important for developers**

Two special sync bytes are historically reserved:

| Byte | Meaning |
|------|--------|
| **D6h** | Standard G40 framed data (what we use here) |
| **A5h** | Used by the ROM for `OLD#` / `SAVE#` tape‑over‑serial loaders |

If you are writing new software:

- **use `D6h`** for framed traffic (text, protocol messages, bulk data)
- **do not repurpose `A5h`** unless you are intentionally emulating the `OLD#` / `SAVE#` mechanisms

Reusing `A5h` in a generic protocol can confuse loaders, BASIC extensions, and tools that expect tape‑compatible behavior.

With those conventions respected, different pieces of Galaksija software can safely interoperate.

### Example: sending one 16‑byte framed block from ASM

A typical transmitter on Galaksija uses a helper like `SEND_FRAME16`, which expects `HL` to point to a 16‑byte body buffer and takes care of wrapping it in `FF D6` + checksum. For example (simplified from the BBS client):

```asm
; HL -> 16‑byte body to send
SEND_FRAME16:
        DI
        PUSH    HL

        ; Preamble: 1x 00 (can be raised to ~50 zeros if needed)
        LD      B,1
SF_ZLP:
        XOR     A            ; A = 0
        PUSH    BC
        CALL    TXBYTE       ; send one zero byte
        POP     BC
        DJNZ    SF_ZLP

        ; Sync bytes
        LD      A,0FFh
        CALL    TXBYTE
        LD      A,0D6h       ; "G40" sync
        CALL    TXBYTE

        POP     HL           ; HL = body
        XOR     A
        LD      C,A          ; checksum = 0
        LD      B,16

SF_BLOOP:
        LD      A,(HL)
        LD      D,A          ; D = original byte
        OR      A
        JR      NZ, SF_NZ1
        LD      D,1Eh        ; avoid 00 in body, send 0x1E instead
SF_NZ1:
        LD      A,D
        ADD     A,C
        LD      C,A          ; checksum += D
        LD      A,D
        PUSH    BC
        PUSH    HL
        CALL    TXBYTE
        POP     HL
        POP     BC
        INC     HL
        DJNZ    SF_BLOOP

        ; checksum
        LD      A,C
        CALL    TXBYTE

        EI
        RET
```

On the receiver side you read bytes until you see `FF D6`, then you read the next 16 bytes as the frame body and the following byte as checksum, mirroring the ROM pattern.

### Example: minimal RX loop using `GO_RX_LOCAL`

```asm
MAIN_LOOP:
        ; receive one frame into XBUF
        CALL    GO_RX_LOCAL      ; HL = 0 on success, 0xFFFF on error/BREAK
        LD      A,H
        OR      L
        CP      0FFh            ; error / BREAK?
        JR      Z, MAIN_LOOP    ; skip and wait again

        LD      A,(XBUF)        ; first byte of 16‑byte body
        CP      05h             ; ENQ?
        JR      Z, HANDLE_ENQ
        CP      01h             ; SOH?
        JR      Z, HANDLE_CLEAR
        ; ... handle normal text, SYN, ACK, etc. ...
        JR      MAIN_LOOP
```

This is the pattern used by the BBS client: frames are always 16 bytes, and control codes like `ENQ`/`SOH`/`ACK` live in the first byte of each frame body.

---

## 5️⃣bis Why we need at least ~50 zero bytes before sending (preamble)

When sending to Galaksija, it helps to begin with a burst of:

```
00 00 00 00 ...
```

Why?

Because Galaksija:

- may currently be drawing the screen  
- could be spending time in BASIC rendering routines  
- might not yet have switched into RECEIVE state  

Screen redraw can take longer than a frame worth of bytes.

Therefore the preamble:

### ✔ gives enough time for Galaksija to sync  
### ✔ ensures its ISR stabilizes on timing  
### ✔ prevents losing the first frame  

50 zeros ≈ **2.6 ms of idle line**, which is long enough to cover:

- worst-case BASIC drawing  
- interrupt scheduling  
- context switching into G40 receiver logic  

---

## 6️⃣ Why we cannot use the ROM `GO_RX` / `GO_TX` directly

In the ROM listing:

https://github.com/miladinovic/galaksija/blob/main/gal40_rom_listing/galaxya.txt

`GO_RX` and `GO_TX` are part of the **BASIC system flow**.

They:

- assume stack layout BASIC uses  
- return into BASIC interpreter  
- may call PRINT / error handlers  
- clear interpreter state  

In short:

> They are not “drivers” — they are pieces of the BASIC runtime.

Our assembly code needs:

- control to stay inside *our* program  
- direct buffer management  
- no BASIC side-effects  

So we must:

✔ *reimplement the core logic*  
✘ avoid the interpreter’s wrappers  

This is exactly what our custom `GO_RX_LOCAL` & `SEND_FRAME16` do.

---

## 7️⃣ Why ENQ-based input request is ideal (bidirectional communication)

In a duplex protocol, we want:

- the host to send data  
- Galaksija to reply  
- **without both talking at the same time**  

A clean solution:

### Use ASCII `ENQ` (0x05) as a *request-to-send* signal.

Flow:

1️⃣ Host sends data  
2️⃣ Host sends **ENQ**  
3️⃣ Galaksija sees ENQ  
4️⃣ Galaksija:
   - flushes screen buffer  
   - waits for keyboard input  
   - sends reply frames  
   - returns to receive mode  

This guarantees:

- Galaksija is NOT receiving while user types  
- replies are transmitted intentionally  
- buffers remain consistent  
- protocol remains simple  

This is the same principle used in the BBS implementation.

---

# Summary

| Concept | Key takeaway |
|--------|--------------|
| ROM serial driver | Bit-banging + interrupt sampling |
| 19200 bps | Possible, but operating at the CPU’s timing edge |
| RxFLAG | Effectively blocking at high speeds |
| Preamble zeros | Allow display + interrupt logic to stabilize |
| ROM GO_RX/TX | Not usable directly in custom ASM (they return to BASIC) |
| ENQ handshaking | Safest way to coordinate request/response communication |

---
