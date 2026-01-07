; ============================================================
; Galaksija Serial RX/TX Demo (documentation example)
; ------------------------------------------------------------
; This example shows how to:
;   - send bytes over the Galaksija serial line using the ROM
;   - receive bytes using the ROM's interrupt-driven RxFLAG
;   - implement a simple "G40-style" frame:
;         FF D6 [16 data bytes] [checksum]
;     where checksum = sum(data bytes) & 0xFF
;   - print received bytes on screen
;
; The code is deliberately small and well-commented, intended
; as a reference for other people who want to use serial I/O
; in their own Galaksija programs.
;
; Assembled for address 0x2C3A and zcc-style entry "_main",
; but you can adapt the ORG and entry label as needed.
; ============================================================

        ORG     0x2C3A
        PUBLIC  _main

; ------------------------------------------------------------
; ROM / system entry points and data locations
; ------------------------------------------------------------

TXBYTE      EQU     0xB77A      ; ROM: send one byte over serial (19200 bps)
RXBYTE_RT   EQU     0xB838      ; ROM: "rxbyte_rt" (reads one received byte)
RXBYTE2_RT  EQU     0xB83B      ; ROM: "rxbyte2_rt" (used by G40)
ROMPRINT    EQU     0x0937      ; ROM: print 0-terminated string (DE points to it)
TASTAT      EQU     0x0CF5      ; ROM: read keyboard, A=0 if no key
RST20       EQU     0x20        ; RST 20h: print char in A

RxFLAG      EQU     0x2BB5      ; RAM: ROM sets bit0=0 when a char arrives (interrupt)
CHS         EQU     0x9DFE      ; RAM: checksum accumulator used by G40
BREAKPORT   EQU     0x2031      ; I/O: BREAK / keyboard check (bit via RRCA)

; ------------------------------------------------------------
; Local buffers
; ------------------------------------------------------------

XBUF        EQU     0x2A70      ; 16-byte RX buffer for one frame
TXBUF       EQU     0x2A80      ; 16-byte TX buffer for one frame
LINEBUF     EQU     0x6000      ; 0-terminated text for ROMPRINT

; ------------------------------------------------------------
; Some constants
; ------------------------------------------------------------

FRAME_PAD   EQU     0x1E        ; filler byte for unused frame positions
FRAME_TAG   EQU     0xD6        ; "G40" frame tag used in this protocol

; ============================================================
; Entry point
; ============================================================

_main:
        ; Print greeting
        LD      DE,MSG_HELLO
        CALL    ROMPRINT

        ; Main loop: alternates between
        ;   - checking for incoming frame
        ;   - checking keyboard and sending a frame with that text
MAIN_LOOP:
        CALL    TRY_RECV_FRAME          ; if a frame arrives, print its data
        CALL    TRY_KEYBOARD_AND_SEND   ; if user types something, send it
        JR      MAIN_LOOP

; ============================================================
; TRY_RECV_FRAME
;   - Non-blocking frame reception
;   - If there is a full frame on serial:
;        FF D6 [16 data bytes] [checksum]
;     then:
;        - data is stored in XBUF
;        - a line "RX: <hex bytes>" is printed on screen
; ============================================================

TRY_RECV_FRAME:
        ; We use RxFLAG to detect if *any* byte is waiting.
        ; If nothing comes in, we just return quickly.

        LD      A,(RxFLAG)
        AND     1
        RET     NZ               ; bit0=1 => no data yet, return

        ; At least one byte is waiting; try to parse a frame.
        CALL    RECV_FRAME16
        ; If checksum or format were wrong, we just silently ignore.
        RET

; ============================================================
; RECV_FRAME16
;   - Blocking, low-level frame receiver:
;       1) waits for preamble FF
;       2) waits for tag D6
;       3) reads 16 data bytes into XBUF
;       4) reads checksum and validates
;   - On success, XBUF[0..15] contain the data
;   - On any error, returns without modifying XBUF (best effort)
; ============================================================

RECV_FRAME16:
        ; Wait for 0xFF
RF_WAIT_FF:
        CALL    SER_RX_BYTE
        CP      0xFF
        JR      NZ,RF_WAIT_FF

        ; Wait for 0xD6 (frame tag)
RF_WAIT_TAG:
        CALL    SER_RX_BYTE
        CP      FRAME_TAG
        JR      NZ,RF_WAIT_FF      ; if not D6, we restart from waiting FF

        ; Now read 16 data bytes into XBUF and accumulate checksum in CHS.
        LD      HL,XBUF
        XOR     A
        LD      (CHS),A            ; CHS = 0

        LD      B,16
RF_GET_DATA:
        CALL    SER_RX_BYTE
        LD      (HL),A

        ; CHS += A
        LD      E,A
        LD      A,(CHS)
        ADD     A,E
        LD      (CHS),A

        INC     HL
        DJNZ    RF_GET_DATA

        ; Read checksum byte
        CALL    SER_RX_BYTE
        LD      E,A                ; received checksum

        LD      A,(CHS)            ; computed checksum
        CP      E
        RET     NZ                 ; checksum mismatch -> ignore frame

        ; If we reach here, the frame is good. For demo, we
        ; show it as hex on screen.
        CALL    PRINT_XBUF_HEX
        RET

; ============================================================
; SER_RX_BYTE
;   - Waits (blocks) until a character is received over serial.
;   - Uses the ROM's RxFLAG mechanism:
;       * ROM interrupt handler clears bit0 when a byte arrives
;   - On return, A = received byte.
; ============================================================

SER_RX_BYTE:
        ; Arm RxFLAG
        LD      A,1
        LD      (RxFLAG),A

SRX_WAIT:
        ; Optional: BREAK key abort (user can press BREAK to stop)
        LD      A,(BREAKPORT)
        RRCA
        JR      NC,SRX_BREAK      ; carry clear => BREAK pressed

        ; Check RxFLAG bit0
        LD      A,(RxFLAG)
        AND     1
        JR      NZ,SRX_WAIT       ; still waiting

        ; Now it's safe to read data from RXBYTE_RT.
        DI
        CALL    RXBYTE_RT
        EI
        RET

SRX_BREAK:
        ; Here you might want to handle BREAK; for this demo
        ; just read anyway and return that byte.
        DI
        CALL    RXBYTE_RT
        EI
        RET

; ============================================================
; PRINT_XBUF_HEX
;   - Print "RX:" and then the 16 bytes in XBUF as hex pairs.
;   - Very simple, purely for demonstration.
; ============================================================

PRINT_XBUF_HEX:
        LD      DE,MSG_RX
        CALL    ROMPRINT

        LD      HL,XBUF
        LD      B,16
PX_LOOP:
        LD      A,(HL)
        CALL    PRINT_HEX_BYTE
        INC     HL
        DJNZ    PX_LOOP

        ; newline
        LD      A,13
        RST     RST20
        RET

; ------------------------------------------------------------
; PRINT_HEX_BYTE
;   - Input: A = byte
;   - Output: prints two hex digits using RST 20
; ------------------------------------------------------------

PRINT_HEX_BYTE:
        PUSH    AF
        PUSH    BC

        ; upper nibble
        SRL     A
        SRL     A
        SRL     A
        SRL     A
        CALL    NIBBLE_TO_ASCII
        RST     RST20

        ; lower nibble
        POP     BC        ; BC unused, we only pop stack balance
        POP     AF

        AND     0x0F
        CALL    NIBBLE_TO_ASCII
        RST     RST20

        RET

NIBBLE_TO_ASCII:
        ; nibble in A (0..15)
        CP      10
        JR      C,NTA_DIGIT
        ADD     A,('A' - 10)
        RET
NTA_DIGIT:
        ADD     A,'0'
        RET

; ============================================================
; TRY_KEYBOARD_AND_SEND
;   - Non-blocking:
;       * if user typed anything on keyboard, gather a short line
;         (up to 15 chars) and send it as one 16-byte frame
;   - Frame contents:
;       FF D6 [16 bytes] checksum
;     with unused data bytes filled by 0x1E.
; ============================================================

TRY_KEYBOARD_AND_SEND:
        CALL    TASTAT
        OR      A
        RET     Z                 ; no key

        ; We got some key; build a short line in TXBUF
        ; 1) clear TXBUF with FRAME_PAD
        LD      HL,TXBUF
        LD      B,16
        LD      A,FRAME_PAD
TKS_CLR:
        LD      (HL),A
        INC     HL
        DJNZ    TKS_CLR

        ; 2) put first key into TXBUF[0]
        LD      HL,TXBUF
        LD      (HL),A           ; A still holds key from TASTAT

        ; 3) read more keys until CR or buffer full
        LD      B,15             ; we already used slot 0
        INC     HL               ; next position

TKS_GET_MORE:
        CALL    TASTAT
        OR      A
        JR      Z,TKS_SEND       ; no new key -> send what we have

        CP      13
        JR      Z,TKS_SEND       ; CR -> end of line, send

        LD      (HL),A
        INC     HL
        DJNZ    TKS_GET_MORE

TKS_SEND:
        ; finally, send TXBUF as one G40-style frame
        LD      HL,TXBUF
        CALL    SEND_FRAME16

        ; small courtesy delay (optional)
        CALL    SMALL_DELAY
        RET

; ============================================================
; SEND_FRAME16
;   - HL -> 16-byte data body (already prepared by caller)
;   - Sends:
;       00 (one zero as preamble)
;       FF
;       D6
;       data[0..15]
;       checksum = sum(data[0..15]) & 0xFF
; ============================================================

SEND_FRAME16:
        DI
        PUSH    HL

        ; One zero byte as preamble
        XOR     A
        CALL    TXBYTE

        ; FF, D6
        LD      A,0FFh
        CALL    TXBYTE
        LD      A,FRAME_TAG
        CALL    TXBYTE

        ; Now send 16 data bytes and accumulate checksum
        POP     HL
        XOR     A
        LD      C,A      ; checksum in C

        LD      B,16
SF_BLOOP:
        LD      A,(HL)
        LD      D,A      ; D = data byte

        ; C += D
        LD      A,C
        ADD     A,D
        LD      C,A

        LD      A,D
        CALL    TXBYTE

        INC     HL
        DJNZ    SF_BLOOP

        ; send checksum
        LD      A,C
        CALL    TXBYTE

        EI
        RET

; ============================================================
; SMALL_DELAY: very short delay between transmissions
; ============================================================

SMALL_DELAY:
        PUSH    AF
        PUSH    BC

        LD      B,0x02
SD_L1:  LD      C,0xFF
SD_L2:  DEC     C
        JR      NZ,SD_L2
        DEC     B
        JR      NZ,SD_L1

        POP     BC
        POP     AF
        RET

; ============================================================
; Messages / data
; ============================================================

MSG_HELLO:
        DB 13,"Galaksija Serial RX/TX Demo",13
        DB " - Press keys to send a frame",13
        DB " - Incoming frames are shown as hex",13,0

MSG_RX:
        DB "RX: ",0

; ============================================================
; End of file
; ============================================================
