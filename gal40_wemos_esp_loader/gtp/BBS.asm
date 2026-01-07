; ============================================================
; Galaksija BBS client (G40) – 2KB page buffer + ROM INPUT line editor
; Authored by Aleksandar Miladinovic, 2026
; ------------------------------------------------------------
; - Sends "__BBS__" (padded with SPACES, not 0x1E)
; - Uses standard G40 frames:
;      preamble (1x00), 0xFF, 0xD6, body[16], checksum
; - Reimplements GO_RX using your disassembly:
;      RxFLAG     = 0x2BB5
;      rxbyte_rt  = 0xB838
;      rxbyte2_rt = 0xB83B
;      chs        = 0x9DFE
;      BREAK      = (0x2031)
; - Frame handling:
;      * 0x16 (SYN)  -> ignore (no ACK)
;      * 0x05 (ENQ)  -> ACK + flush page buffer (paged) + keyboard input
;      * 0x01 (SOH)  -> ACK + clear screen + clear buffer
;      * 0x06 (ACK)  -> ignore
;      * 0x00        -> ignore
;      * otherwise   -> ACK + append XBUF[0..15] to PAGEBUF
;
; - PAGEBUF: 2 KB at 0x6030–0x67FF
;      * initially filled with 0x04 (sentinel)
;      * APPEND_XBUF writes sequentially from PAGEBUF, up to PAGEBUF_END
;      * FLUSH_PAGEBUF scans from PAGEBUF until 0x04 or PAGEBUF_END
;      * padding 0x1E is ignored
;      * split on 0x0D (CR) into lines
;      * each line printed via ROMPRINT with paging (every 14 lines: " --MORE--")
;      * after flush, PAGEBUF is refilled with 0x04 and pointer reset
;
; - INPUT:
;      * uses ROM INPUT editor core at Z8FC (0x07BD)
;      * buffer BUF at 0x2BB6
;      * before each input: first 64 bytes of BUF are cleared to 0x1E
;      * after ENTER:
;           - we SCAN BUF for CR (0x0D), up to 48 chars
;           - enforce a CR there
;           - length = chars_before_CR + 1 (CR)
;           - whole line is split into 16-byte frames
;           - ALL frames are sent back-to-back (no RX in between)
;           - small delay between frames
;           - then returns to MAIN_LOOP (RX)
;
; - ACK frame body: 0x06 + 15 * 0x1E
; - zcc-compatible entry: _main at 0x2C3A
; ============================================================

        ORG     0x2C3A
        PUBLIC  _main

; -------- ROM routines / system addresses --------
TXBYTE      EQU     0xB77A      ; serial TX byte @19200
RXBYTE_RT   EQU     0xB838      ; rxbyte_rt
RXBYTE2_RT  EQU     0xB83B      ; rxbyte2_rt
ROMPRINT    EQU     0x0937      ; DE -> 0-terminated string
TASTAT      EQU     0x0CF5      ; read keyboard, A=0 if no key
RST20       EQU     0x20        ; RST 20h: print A

RxFLAG      EQU     0x2BB5      ; clr bit 0 by INT on RX
CHS         EQU     0x9DFE      ; checksum accumulator used by ROM
BREAKPORT   EQU     0x2031      ; keyboard/BREAK check (bit via rrca)

; -------- BASIC INPUT editor hook --------
BUF         EQU     0x2BB6      ; BASIC line buffer used by Z8FC
Z8FC        EQU     0x07BD      ; ROM line editor (INPUT core)

; -------- Frame buffers --------
XBUF        EQU     0x2A70      ; 16-byte G40 body (RX)
PRINTBUF    EQU     0x2A80      ; TX body

G40_PAD     EQU     0x1E        ; RS filler

; -------- Page buffering / buffers --------
PAGEBUF     EQU     0x6030      ; 2KB page buffer start
PAGEBUF_END EQU     0x6800      ; end (exclusive, i.e. first byte *after* buffer)

LINEBUF     EQU     0x6000      ; line buffer for ROMPRINT (0-terminated)

MAX_LINE_LEN EQU    48          ; max chars per printed line

; ============================================================
; Debug macro
; ============================================================

DEBUG       EQU     0

DBG MACRO ch
        IF DEBUG
            LD      A,ch
            RST     RST20
        ENDIF
ENDM

; ============================================================
; Entry
; ============================================================
_main:
        DBG     'S'             ; start

        ; init page buffer pointer = PAGEBUF
        LD      HL,PAGEBUF
        LD      A,L
        LD      (PAGEPTR_LO),A
        LD      A,H
        LD      (PAGEPTR_HI),A

        ; fill PAGEBUF with 0x04 at startup
        CALL    CLEAR_PAGEBUF

        ; Send __BBS__ (padded with spaces, not 0x1E)
        LD      HL, MSG_BBS
        CALL    SEND_FRAME16

        DBG     'B'             ; after __BBS__

; ============================================================
; Main loop
; ============================================================
MAIN_LOOP:
        DBG     'L'             ; loop top
        DBG     'R'             ; before GO_RX_LOCAL

        ; --- receive one frame into XBUF ---
        CALL    GO_RX_LOCAL     ; HL = 0 if OK, 0xFFFF if CHS/BREAK error

        DBG     'G'             ; after GO_RX_LOCAL

        ; If CHS error or BREAK: skip this frame and continue
        LD      A,H
        OR      L
        CP      0FFh            ; HL == 0xFFFF ?
        JR      Z, MAIN_LOOP

        DBG     'N'             ; "normal" frame candidate

        ; First byte of body:
        LD      A,(XBUF)

        ; 0x16 = SYN (heartbeat) → ignore (no ACK, no print)
        CP      0x16
        JR      Z, MAIN_LOOP

        ; 0x05 = ENQ → ACK + flush page + keyboard input
        CP      0x05
        JR      Z, DO_ENQ

        ; 0x01 = SOH → ACK + clear screen + clear buffer
        CP      0x01
        JR      Z, DO_CLEAR

        ; 0x06 = ACK from ESP → ignore completely
        CP      0x06
        JR      Z, MAIN_LOOP

        ; 0x00 = “empty / weird” frame → ignore completely
        CP      0x00
        JR      Z, MAIN_LOOP

        ; Normal text frame: ACK + append body to PAGEBUF
        DBG     'B'
        CALL    SEND_ACK

        DBG     'A'             ; ACK sent

        CALL    APPEND_XBUF_TO_PAGEBUF

        JR      MAIN_LOOP

; ------------------------------------------------------------
; ENQ 0x05: ACK + flush PAGEBUF + get line from keyboard
; ------------------------------------------------------------
DO_ENQ:
        CALL    SEND_ACK
        DBG     'E'             ; ENQ detected

        ; Flush everything we buffered so far, line-by-line
        CALL    FLUSH_PAGEBUF

        ; Now prompt user (ROM INPUT-style)
        JP      GET_LINE_FROM_KEYBOARD     ; no extra stack frame

; ------------------------------------------------------------
; SOH 0x01: ACK + clear screen + clear buffer
; ------------------------------------------------------------
DO_CLEAR:
        CALL    SEND_ACK
        LD      A,12
        RST     RST20           ; ROM CLS

        ; little "loading" marker at 0x281F
        LD      HL,0x281F
        LD      (HL),0xFF

        ; refill PAGEBUF with 0x04 and reset pointer
        CALL    CLEAR_PAGEBUF

        JP      MAIN_LOOP

; ============================================================
; APPEND_XBUF_TO_PAGEBUF
;   - Add current 16-byte XBUF to PAGEBUF at current pointer.
;   - Pointer starts at PAGEBUF and moves forward.
;   - If pointer >= PAGEBUF_END, do nothing (drop extra text).
; ============================================================
APPEND_XBUF_TO_PAGEBUF:
        ; DE = current page pointer
        LD      A,(PAGEPTR_LO)
        LD      E,A
        LD      A,(PAGEPTR_HI)
        LD      D,A

        ; if DE >= PAGEBUF_END, ignore
        LD      HL,PAGEBUF_END
        LD      A,D
        CP      H
        JR      C,AP_GO
        JR      NZ,AP_RET
        LD      A,E
        CP      L
        JR      NC,AP_RET

AP_GO:
        LD      HL,XBUF
        LD      B,16

AP_COPY:
        LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    AP_COPY

        ; store updated pointer back
        LD      A,E
        LD      (PAGEPTR_LO),A
        LD      A,D
        LD      (PAGEPTR_HI),A

AP_RET:
        RET

; ============================================================
; CLEAR_PAGEBUF
;   - Fill the whole 2KB PAGEBUF with 0x04, reset pointer
; ============================================================
CLEAR_PAGEBUF:
        DI
        LD      HL,PAGEBUF
        LD      DE,PAGEBUF_END

CPB_LOOP:
        LD      A,4
        LD      (HL),A
        INC     HL

        LD      A,H
        CP      D
        JR      C,CPB_LOOP
        JR      NZ,CPB_LOOP
        LD      A,L
        CP      E
        JR      C,CPB_LOOP

        ; reset pointer = PAGEBUF
        LD      HL,PAGEBUF
        LD      A,L
        LD      (PAGEPTR_LO),A
        LD      A,H
        LD      (PAGEPTR_HI),A

        EI
        RET

; ============================================================
; FLUSH_PAGEBUF  (paging + sentinel)
;   - Interpret PAGEBUF as:
;        * scan from PAGEBUF until 0x04 or PAGEBUF_END
;        * ignore 0x1E padding and 0x00
;        * split on 0x0D (CR) into lines
;   - For each line:
;        * LINEBUF = [chars .. CR?, 0x00]
;        * PRINT_LINE_PAGED(LINEBUF)
;   - At end: PAGEBUF filled with 0x04 and pointer reset
; ============================================================
FLUSH_PAGEBUF:
        ; HL = PAGEBUF (source pointer)
        LD      HL,PAGEBUF

        ; DE = LINEBUF (destination for current line)
        LD      DE,LINEBUF

        ; LINELEN = 0, ROWCOUNT = 0
        XOR     A
        LD      (LINELEN),A
        LD      (ROWCOUNT),A

FP_NEXT_CHAR:
        ; check end-of-buffer
        LD      A,H
        CP      0x68
        JR      C,FP_CHECK_SENT
        JR      NZ,FP_DONE
        LD      A,L
        CP      0x00
        JR      NC,FP_DONE

FP_CHECK_SENT:
        LD      A,(HL)
        CP      4               ; sentinel 0x04?
        JR      Z,FP_DONE

        ; ignore padding 0x1E
        CP      G40_PAD
        JR      Z,FP_ADVANCE

        ; ignore zeros
        OR      A
        JR      Z,FP_ADVANCE

        ; CR (end of line)?
        CP      13
        JR      Z,FP_EOL

        ; normal character
        LD      (T_CHAR),A
        LD      A,(LINELEN)
        CP      MAX_LINE_LEN
        JR      NC,FP_ADVANCE   ; drop extra chars if too long

        LD      A,(T_CHAR)
        LD      (DE),A
        INC     DE

        LD      A,(LINELEN)
        INC     A
        LD      (LINELEN),A

FP_ADVANCE:
        INC     HL
        JR      FP_NEXT_CHAR

FP_EOL:
        ; append CR if space left
        LD      A,(LINELEN)
        CP      MAX_LINE_LEN
        JR      NC,FP_EOL_TRUNC

        LD      A,13
        LD      (DE),A
        INC     DE

        LD      A,(LINELEN)
        INC     A
        LD      (LINELEN),A

FP_EOL_TRUNC:
        ; terminator
        XOR     A
        LD      (DE),A

        ; print this line with paging
        LD      DE,LINEBUF
        CALL    PRINT_LINE_PAGED

        ; reset line buffer
        LD      DE,LINEBUF
        XOR     A
        LD      (LINELEN),A

        INC     HL
        JR      FP_NEXT_CHAR

FP_DONE:
        ; flush partial line if any
        LD      A,(LINELEN)
        OR      A
        JR      Z,FP_DONE2

        LD      A,13
        LD      (DE),A
        INC     DE
        XOR     A
        LD      (DE),A

        LD      DE,LINEBUF
        CALL    PRINT_LINE_PAGED

FP_DONE2:
        ; refill PAGEBUF with 0x04 and reset pointer
        CALL    CLEAR_PAGEBUF
        RET

; ============================================================
; PRINT_LINE_PAGED
;   - Input: DE = pointer to 0-terminated string
;   - Behaviour:
;       * ROMPRINT(line)
;       * short WAIT between lines
;       * ROWCOUNT++ and every 14 lines → PAGE_WAIT
;   - PRESERVES AF/BC/DE/HL
; ============================================================
PRINT_LINE_PAGED:
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL

        CALL    ROMPRINT
        CALL    WAIT0_5S

        ; Update row count
        LD      A,(ROWCOUNT)
        INC     A
        LD      (ROWCOUNT),A
        CP      14              ; pause every 14 lines
        CALL    Z,PAGE_WAIT

        POP     HL
        POP     DE
        POP     BC
        POP     AF
        RET

; ============================================================
; PAGE_WAIT – pause after 14 lines, show " --MORE--" and wait
;   PRESERVES AF/BC/DE/HL
; ============================================================
PAGE_WAIT:
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL

        ; newline before prompt
        LD      A,13
        RST     RST20

        ; print " --MORE--"
        LD      DE,MSG_MORE
PW_STR:
        LD      A,(DE)
        OR      A
        JR      Z,PW_WAIT_KEY
        RST     RST20
        INC     DE
        JR      PW_STR

PW_WAIT_KEY:
PW_K1:
        CALL    TASTAT
        OR      A
        JR      Z,PW_K1

        ; after key, move to next line
        LD      A,13
        RST     RST20

        ; reset row counter
        XOR     A
        LD      (ROWCOUNT),A

        POP     HL
        POP     DE
        POP     BC
        POP     AF
        RET

; ============================================================
; GET_LINE_FROM_KEYBOARD
;  - Uses ROM INPUT core (Z8FC)
;  - Reads line into BUF
;  - Max 48 chars + CR
;  - Sends as 16-byte frames, padded with 0x1E
; ============================================================

GET_LINE_FROM_KEYBOARD:
        DBG     'I'

; ------------------------------------------------------------
; Clear BUF[0..63] with 0x1E
; ------------------------------------------------------------
        LD      HL,BUF
        LD      B,64
        LD      A,G40_PAD
GLF_CLR:
        LD      (HL),A
        INC     HL
        DJNZ    GLF_CLR

; ------------------------------------------------------------
; ROM line editor
; ------------------------------------------------------------
        LD      A,'?'
        CALL    Z8FC

; ------------------------------------------------------------
; Scan BUF for CR (max 48 chars)
; ------------------------------------------------------------
        LD      HL,BUF
        LD      B,0              ; count before CR

GLF_SCAN:
        LD      A,(HL)
        CP      13
        JR      Z,GLF_SCAN_END

        INC     HL
        INC     B
        LD      A,B
        CP      48
        JR      C,GLF_SCAN

        LD      A,13
        LD      (HL),A           ; force CR

GLF_SCAN_END:
        INC     B                ; include CR

        LD      A,B
        OR      A
        JR      Z,GLF_EXIT

; ------------------------------------------------------------
; Init runtime state
; ------------------------------------------------------------
        LD      HL,BUF
        LD      (GLF_SRC_PTR),HL

        LD      A,B
        LD      (GLF_REMAIN),A

; ------------------------------------------------------------
; Frame loop
; ------------------------------------------------------------
GLF_FRAME:
        LD      A,(GLF_REMAIN)
        OR      A
        JR      Z,GLF_EXIT

        ; K = min(GLF_REMAIN, 16)
        CP      16
        JR      C,GLF_K_OK
        LD      A,16
GLF_K_OK:
        LD      (GLF_K),A

; ------------------------------------------------------------
; Pad PRINTBUF
; ------------------------------------------------------------
        LD      HL,PRINTBUF
        LD      B,16
        LD      A,G40_PAD
GLF_PAD:
        LD      (HL),A
        INC     HL
        DJNZ    GLF_PAD

; ------------------------------------------------------------
; Copy K bytes BUF -> PRINTBUF
; ------------------------------------------------------------
        LD      HL,(GLF_SRC_PTR)
        LD      DE,PRINTBUF

        LD      A,(GLF_K)
        LD      B,A

GLF_COPY:
        LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    GLF_COPY

        ; save updated source pointer
        LD      (GLF_SRC_PTR),HL

; ------------------------------------------------------------
; Update remaining byte count
;   A little trick:
;       C = old remain
;       A = K
;       SUB C
;       NEG  -> remain - K
; ------------------------------------------------------------
        LD      A,(GLF_REMAIN)
        LD      C,A
        LD      A,(GLF_K)
        SUB     C
        NEG
        LD      (GLF_REMAIN),A

; ------------------------------------------------------------
; Send frame
; ------------------------------------------------------------
        LD      HL,PRINTBUF
        CALL    SEND_FRAME16

        JR      GLF_FRAME

; ------------------------------------------------------------
; Exit
; ------------------------------------------------------------
GLF_EXIT:
        JP      MAIN_LOOP

; ============================================================
; GO_RX_LOCAL: reimplementation of ROM GO_RX
; ============================================================
GO_RX_LOCAL:
        LD      BC,XBUF         ; BC points to X$

skr_R:
        LD      A,1
        LD      (RxFLAG),A

wait_Rx:
        ; Check BREAK
        LD      A,(BREAKPORT)   ; 0x2031
        RRCA                    ; move BREAK bit into carry
        JP      NC, GO_RX_BREAK ; if BREAK pressed, treat as error

        ; Check RxFLAG bit0 (set by INT when RX present)
        LD      A,(RxFLAG)
        AND     1
        JR      NZ, wait_Rx     ; if no RX yet, loop

        DI

getD6:
        CALL    RXBYTE_RT       ; rxbyte_rt
        CP      0xD6
        JR      NZ, getD6

        XOR     A
        LD      (CHS),A         ; chs = 0

getXstring:
        CALL    RXBYTE2_RT      ; rxbyte2_rt
        LD      (BC),A
        INC     BC
        LD      A,C
        AND     0x0F
        JP      NZ, getXstring  ; until low 4 bits of C == 0 (multiple of 16)

        LD      A,(CHS)
        LD      C,A

        CALL    RXBYTE_RT       ; checksum byte
        CP      C

        LD      HL,0FFFFh       ; assume CHS error
        JR      NZ, go_rx_badchs

        INC     HL              ; HL=0 if checksum OK

go_rx_badchs:
        EI
        RET

GO_RX_BREAK:
        LD      HL,0FFFFh       ; BREAK -> error
        EI
        RET

; ============================================================
; SEND_ACK: send ACK frame with body 0x06 + 15 * 0x1E
; ============================================================
SEND_ACK:
        LD      HL, ACK_BODY
        JP      SEND_FRAME16

; ============================================================
; SEND_FRAME16: HL -> 16-byte body
; Sends: 1x00, FF, D6, body[16], checksum=sum(body)&0xFF
; ============================================================
SEND_FRAME16:
        DI
        PUSH    HL

        ; Preamble zeros (you had B=1 tuned)
        LD      B,1
SF_ZLP:
        XOR     A
        PUSH    BC
        CALL    TXBYTE
        POP     BC
        DJNZ    SF_ZLP

        ; FF, D6
        LD      A,0FFh
        CALL    TXBYTE
        LD      A,0D6h
        CALL    TXBYTE

        POP     HL              ; HL -> body
        XOR     A
        LD      C,A             ; checksum accumulator

        LD      B,16
SF_BLOOP:
        LD      A,(HL)
        LD      D,A             ; D = original byte

        ; If body contains 0x00, FORCE 0x1E on the wire and in checksum
        OR      A
        JR      NZ, SF_NZ1
        LD      D,G40_PAD       ; substitute 0x1E
SF_NZ1:
        LD      A,D
        ADD     A,C
        LD      C,A             ; C += D

        LD      A,D
        PUSH    BC
        PUSH    HL
        CALL    TXBYTE
        POP     HL
        POP     BC

        INC     HL
        DJNZ    SF_BLOOP

        ; send checksum
        LD      A,C
        CALL    TXBYTE

        EI
        RET

; ============================================================
; WAIT0_5S: crude ~half-second delay, PRESERVES AF/BC/DE/HL
; ============================================================
WAIT0_5S:
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL

        LD      B,0x01          ; tweak for longer/shorter waits
W05_L1:
        LD      C,0xFF
W05_L2:
        DEC     C
        JR      NZ, W05_L2
        DEC     B
        JR      NZ, W05_L1

        POP     HL
        POP     DE
        POP     BC
        POP     AF
        RET

; ============================================================
; Data
; ============================================================

; "__BBS__" padded with SPACES (only here, as requested)
MSG_BBS:
        DB "__BBS__"
        DB "         "          ; 9 spaces -> total 16 bytes

; "--MORE--" prompt for paging
MSG_MORE:
        DB " --MORE--",0

; ACK frame body: 0x06 + 15 * 0x1E (unchanged)
ACK_BODY:
        DB 0x06
        DB G40_PAD,G40_PAD,G40_PAD,G40_PAD,G40_PAD
        DB G40_PAD,G40_PAD,G40_PAD,G40_PAD,G40_PAD
        DB G40_PAD,G40_PAD,G40_PAD,G40_PAD,G40_PAD

; ============================================================
; Runtime variables (allocated after code, like GLF_*)
; ============================================================

ROWCOUNT:     DB 0      ; number of printed lines in current flush/page
T_CHAR:       DB 0      ; temp char for FLUSH_PAGEBUF
LINELEN:      DB 0      ; current line length
PAGEPTR_LO:   DB 0      ; low byte of PAGEBUF write pointer
PAGEPTR_HI:   DB 0      ; high byte of PAGEBUF write pointer

GLF_SRC_PTR:  DW 0      ; current BUF pointer for input send
GLF_REMAIN:   DB 0      ; bytes remaining to send
GLF_K:        DB 0      ; bytes in current frame

; ============================================================
; End
; ============================================================