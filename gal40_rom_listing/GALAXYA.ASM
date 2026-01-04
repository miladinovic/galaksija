;***********************************************************
;*             MALI RACUNAR "GALAKSIJA"                    *
;*                                     VOJA ANTONIC        *
;*                                Verzija 42, Mart 2024.    *
;***********************************************************

HOR             EQU     22	; hor pos
latadr          EQU     0x203f  ; Latch Address
IXPOS           EQU     0x2AAC
stack           EQU     0x2BA8
RxFLAG		EQU	0x2BB5	; clr bit 0 if Rx present (tested during INT)
BUF             EQU     0x2BB6
BASPTR          EQU     0x2C36	; BASIC-4
BASEND          EQU     0x2C38	; BASIC-2
BASIC           EQU     0x2C3A	; BASIC starts herelf
FlBuf           EQU     0x9E00  ; Flash Buffer 512 by
chs		EQU	0x9DFE	; checksum (lo calculated, hi received)

; stack+8	Smooth Scroll 
; 2a6ch		Scroll Window Len (blokiranje dela video mem)
; stack+1	Link

	org	0

        DI
        SUB     A
        JP      Z18E
ZAREZ   RST     Z8      ; IF (DE)<>","  GO "WHAT"
        DEFB    ','     ; ELSE RST Z807
        DEFB    GO8C9-$-1  ; this is WHAT? ept
; 0x08 =================
Z807    CALL    Z24     ; PRETVORI SLEDECI ASCII NIZ U INTEGER I SMESTI GA U HL
        JP      ZC0B
FAST    DI              ; FAST FLAG
        RET
; 0x10 =================
Z32     LD      A,H     ; CP HL-DE Z & C FLAGS VALID
        CP      D
        RET     NZ
        LD      A,L
        CP      E
        RET
SLOW    EI              ; SLOW FLAG
        RET
; 0x18 =================

; if (DE) = ($+1) then skip ($+2) and  PC <---- $+3
; else  PC <---- PC+$+2

; In pseudo-code:
;
; If (**SP) == (EAT_SPACE(DE)) Then
;	*SP=*SP+2
; 	DE=DE+1
; Else
;	*SP=*SP+2+(*(*SP+1))		
; End

; Parameters:
;	DE: Pointer to a string.
; Returns:
;	DE: Skips leading space and increments DE, if there is a match.
;	A: First non-space character in DE.
;	Zf: Set if character matches, reset if not.
; Destroys: 
;	flags.


Z8      EX      (SP),HL ; IF ((SP))=(DE) THEN (SP)=(SP)+2
                        ; ELSE (SP)=((SP)+1)+(SP)+2
        CALL    Z40     ; skip blanks, pointer de
        CP      (HL)
        JP      Z98

; 0x20 =================
Z16     EXX             ; PRINT CHAR IN A ON SCREEN
        CP      20H
        CALL    ZACB
        EXX
        RET
; 0x28 =================
HL0     LD      HL,0
        RET
ZEB9    DEFW    0CCCCH  ; RND CONST
        DEFW    7ECCH
; 0x30 =================
Z48     POP     AF      ; GO NEXT INSTRUCTION
        CALL    Z8B3
GO8C9   JP      WHAT
NUMBER  DEFB    42      ;       VERZIJA 42

	org	0x38

; -------------------- INTERRUPT -----------------------
; B = Value with bit 7 set/res for R reg adjustment
; C = current line number 80h - 8Fh
; D = char gen Row addr 0 - 11
; E = scan line counter 12 - 1 
; HL = latadr

        PUSH    AF	; \   I N T   V I D E O
        PUSH    BC	; \\
        PUSH    DE	; \\\
        PUSH    HL	; \\\\

; -------------------- SMOOTH SCROLL --------------------- 

        LD      HL,stack+8   ; SCROLL COUNT (ini 3, scroll je u 3 faze)
        LD      A,0b0H
        SUB     (HL)
        SUB     (HL)
        SUB     (HL)		; Subtract 3 * SCROLL_CNT from A
				; (jer preskace po 3 linije)
        LD      E,A		; smooth scroll counter to E
        LD      A,(HL)
        RRCA
        RRCA
        RRCA                    ; same as 5x SLA, which is x32
        LD      B,A		; for DJNZ loop
        OR      A
        JR      Z,$+2
        JR      Z,Scr
        DEC     (HL)            ; decremenf offset to animate smooth scroll
        XOR     A
SPECL   RET     C               ; C is never set, used for timing only!
        DJNZ    SPECL
Scr     INC     HL		; Load SCROLL_FLAG address to HL
        LD      (HL),A  	; set/reset scroll flag (scroll done, if any)
        LD      B,E		; multiscroll cycle counter to B

        jp      hor_loop        ; go to hor pos service

; \\\\\\\\\\\\\\\\\\\\\\\\\
	org	0x0066
	 DI			; -------- NMI (HARD BREAK)
SP1C9	 LD      SP,stack	; reini SP
	 JP      Z1C9		; Z1C9 = Break ept
; /////////////////////////

	nop
	nop

hor_loop_back
        LD      HL,latadr	; LATCH @ 203Fh
 	ld	BC,0xFDC0	; B=-3, C=12*16

; * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *

ROWS16
; ------------- BACK PORCH --------- OUTER LOOP START (TEXT ROWS)

 ; flag serial signal
	ld	HL,RxFLAG		; 10
	ld	A,(0x203A)	; 13   RX signal is here in bit 0
	and	(HL)		; 7
	ld	(HL),A		; 7    clr bit 0 if serial signal was present
 ; read from table
        INC     B		; 4    B = current scan line 00h...0Fh
        INC     B		; 4    B = current scan line 00h...0Fh
        INC     B		; 4    B = current scan line 00h...0Fh
        push    BC              ; 11     \\\\\\\\\\\\\\\\\\\\\\    to save B

	ld	HL,r_tab        ; 10
        ld      D,0             ; 7   d <--- 0
        ld      E,B             ; 4   de = table offset
        add     hl,de           ; 11  now HL points to <DeltaR,I,R> in lookup table
	ret	C		; 5   TIMING ONLY!!!

        ld      B,(hl)          ; 7   ...get delta R (step)
        inc     HL              ; 6
        ld      a,(hl)          ; 7   ...get I (page)
        ld      i,a             ; 9
        inc     HL              ; 6
        ld      a,(hl)          ; 7   ...get R start value

        ld      hl,latadr       ; 10  latch addr
	ld	de,0x880c       ; 10  D=0x88=latch contents, E=0x0c=scan line count
	LD	R,A		; 9

; * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *

; ------- ACTIVE SCREEN AREA --------INNER LOOP START (SCAN LINES)
LINES12
	LD      (HL),D	; 7t  <- - - - - - - - - - - 
        			; ---------- drawing starts here
	INC     D		; 1		D = char gen Row counter
	INC     D		; 2		D = char gen Row counter
	INC     D		; 3		D = char gen Row counter
	INC     D		; 4		D = char gen Row counter

	ld	h,c	; 5     push registers B, C
	ld	a,b	; 6
BRK
;	DEFM    'BREAK' ; OVAJ STRING JE TRANSPARENTAN
	ld b,d		; 7	B 
	ld d,d		; 8	R 
	ld b,l		; 9	E 
	ld b,c		; 10	A 
	ld c,e		; 11	K 
	NOP		; 12    00h terminator

	ld      b,a	; 13	pop registers B, C
	ld      c,h	; 14

ZEB5	DEFB    0	; 15
	DEFB    0	; 16
	ADD     A,B	; 17
	NOP		; 18

        NOP		; 19
        NOP		; 20
        NOP		; 21
        NOP		; 22
        NOP		; 23

	XOR     A	; 24  A <--- 0
	scf		; 25
	rra		; 26  80h
	rra		; 27  40h
	rra		; 28  20h```````
	ld h,a		; 29
	rla		; 30  40h
	rla		; 31  80h
	LD      (HL),A	; 32 (latadr)<--80h blank front/back porch

;************************************************************************
; ------------- FRONT PORCH ------------------------ (54T to LINES12)

        DEC     C		; 4  T  =4
        JR      Z,BLK		; 7  T  =11

        LD      A,R 		; 9  T  =20
        SUB     B		; 4  T  =24
        LD      R,A 		; 9  T  =33

        add     a,0             ; 7  T  =40     dummy, just for timing

        DEC     E               ; 4  T  =44
        JP      NZ,LINES12	; 10 T  =54   INNER LOOP=192T (12 SCAN LINES)

	pop	AF		; 10
        ld      B,A             ; 4         //////////////////// restore B
        JP      ROWS16          ; 10 ------ OUTER LOOP END (16 TEXT ROWS)

; * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *

; =================== end of screen service =====================

BLK     pop     bc              ; 10          ////////////////////

; -------------------- RTC --------------------------------

BSTR    EQU     2A80H   ; SAT
	jp	save13by

 ;       LD      A,(BSTR+2)
 ;       CP      ':'
 ;       JR      NZ,NESAT
 ;       LD      A,(stack+7)	; Ako je bit 7=1, sat radi
 ;       RLCA
 ;       JR      NC,NESAT
 ;       LD      HL,BSTR+10
 ;       jp      back13by

back13by
        LD      DE,3930H
        LD      B,8
        LD      A,D
        INC     (HL)
        INC     (HL)
        CP      (HL)
        JR      OVER1a
X7      INC     (HL)
        CP      (HL)
        LD      A,35H
OVER1a  JR      NC,NEOVF
        LD      (HL),E
        DEC     HL
        BIT     0,B
        JR      Z,UZ
        DEC     HL
        LD      A,D
UZ      DJNZ    X7
NEOVF   DEC     B
        DJNZ    NESAT
        LD      A,(HL)
        CP      34H
        JR      C,NESAT
        DEC     HL
        BIT     1,(HL)
        JR      Z,NESAT
        LD      (HL),E
        INC     HL
        LD      (HL),E
NESAT   JP      (IY)

LINK3   POP     HL	; ////
        POP     DE	; ///
        POP     BC	; //
        POP     AF	; /
        EI
        RETI

NOV40                   ; SKIP BLANKS
        INC     DE
Z40     LD      A,(DE)  ; skip blanks, pointer de
        CP      20H
        JR      Z,NOV40	; go get next byte
        RET		; if not equal

DIM     EQU     $
        INC     HL
        XOR     A
        CALL    HLX4	; HL <---- HLx16
        LD      (2A99H),HL
        RST     Z48
STRMAT  RST     Z807
        INC     HL
        XOR     A
        CALL    HLX4
        PUSH    DE
        LD      DE,(2A99H)
        INC     DE
        RST     Z32
        JR      NC,SORRY2
        JR      Z51
Z56     CALL    Z40	; Z40 = skip blanks (ptr DE)
        SUB     41H
        RET     C	; if <'A'
        CP      1AH
        CCF
        RET     C	; if >1AH
        INC     DE
        AND     A
        JR      NZ,Z82
        RST     Z8
        DEFB    28H
        DEFB    Z81-$-1
        RST     Z807
        INC     HL
        ADD     HL,HL
        ADD     HL,HL
        PUSH    DE
        JR      C,SORRY2
        LD      DE,(2A99H)
        ADD     HL,DE
        POP     DE
        PUSH    DE
        JR      C,SORRY
Z51     POP     DE
        RST     Z8
        DEFB    29H
        DEFB    SORRY-$-1
        PUSH    DE
        EX      DE,HL
        CALL    X825
        RST     Z32
        JR      NC,X82A
        DEFB    3EH
SORRY   PUSH    DE      ; SORRY ENTRY PT
SORRY2  CALL    Z8CD    ; SORRY
        DEFM    'SORRY'
        DEFB    0DH

Z81     XOR     A
Z82     LD      H,2AH
        RLA
        RLA
        LD      L,A
        XOR     A
        RET
HEXCIF  CALL    Z8C
        RET     NC
        CP      41H
        RET     C
        ADD     A,9
        CP      50H
        JR      ASK4
Z8C                     ; NC=numeric, C=alpha or interpunct
        LD      A,(DE)
        CP      30H
        RET     C
        CP      3AH
ASK4    CCF
        RET     C
        INC     DE
SKRS    AND     0FH
        RET

STRSUB  LD      (HL),A
SKRASC  INC     HL
        LD      A,L
        JR      SKRS

X825    PUSH    DE
        LD      DE,(BASEND)
X82A    LD      HL,(2A6AH)
        LD      A,L
        AND     0F0H
        LD      L,A
        SBC     HL,DE
        POP     DE
        XOR     A
        RET

Z98     INC     HL
        JR      Z,ZA2
        PUSH    BC
        LD      C,(HL)
        LD      B,0
        ADD     HL,BC
        POP     BC
        DEC     DE
ZA2     INC     DE
        INC     HL
        EX      (SP),HL
        RET
ZA6                       ; CONVERT STRING TO FLOATING POINT
        CALL    Z155
        LD      B,0
        LD      C,B
        CALL    Z40  ; skip blanks, pointer de
ZAD     CALL    ZB2
        JR      ZAD
ZB2     CALL    Z8C
        JR      C,ZD7
        SET     6,B
        BIT     7,B
        JR      NZ,ZD2
        CALL    ZC5
        BIT     0,B
        RET     Z
        DEC     C
        RET
ZC5     CALL    Z15E
        RET     Z
        EXX
        LD      H,D
        LD      L,E
        EX      AF,AF'
        LD      C,A
        EXX
        SET     7,B
        POP     AF
ZD2     BIT     0,B
        RET     NZ
        INC     C
        RET
ZD7     RST     Z8
        DEFB    2EH
        DEFB    ZDF-$-1
        BIT     0,B
        SET     0,B
        RET     Z
ZDF     POP     AF
        BIT     6,B
        RET     Z
        LD      HL,18H
        PUSH    BC
        PUSH    DE
        EXX
        CALL    ZE10IX
        POP     DE
        LD      BC,ZFB
        PUSH    BC
        PUSH    DE
        JP      ZD0F
ZFB     POP     BC
        PUSH    DE
        RST     Z8
        DEFB    45H
        DEFB    Z11C-$-1
        RST     Z8
        DEFB    2BH
        DEFB    2
        JR      Z10A
        RST     Z8
        DEFB    2DH
        DEFB    2
        SET     1,B
Z10A    CALL    Z157
Z10D    CALL    Z8C
        JR      C,Z120
        SET     5,B
        CALL    Z15E
        JR      NZ,Z12E
        JR      Z10D
Z11C    POP     DE
        XOR     A
        JR      Z137
Z120    BIT     5,B
        JR      Z,Z11C
        POP     AF
        EXX
        LD      A,C
        OR      H
        LD      A,L
        EXX
        JR      NZ,Z12E
        BIT     7,A
Z12E    JP      NZ,HOW
        BIT     1,B
        JR      Z,Z137
        NEG
Z137    ADD     A,C
Z138    AND     A
        JR      Z,Z14E
Z13B    BIT     7,A
        JR      Z,Z146
        INC     A
        PUSH    AF
        CALL    ZC95
        JR      Z14B
Z146    DEC     A
        PUSH    AF
        CALL    ZC84
Z14B    POP     AF
        JR      Z138
Z14E    BIT     6,B
        RET
Z155    RES     6,B
Z157    EXX
        RST     HL0
        LD      C,L
        EXX
        RET
Z15E    EX      AF,AF'
        EXX
        LD      D,H
        LD      E,L
        LD      A,C
        LD      B,0
        PUSH    AF
        ADD     HL,HL
        RL      C
        RL      B
        ADD     HL,HL
        RL      C
        RL      B
        ADD     HL,DE
        ADC     A,C
        LD      C,A
        LD      A,0
        ADC     A,B
        LD      B,A
        POP     AF
        PUSH    DE
        LD      D,0
        ADD     HL,HL
        RL      C
        RL      B
        EX      AF,AF'
        LD      E,A
        ADD     HL,DE
        LD      A,D
        ADC     A,C
        LD      C,A
        LD      A,D
        ADC     A,B
        LD      B,A
        POP     DE
        EXX
        RET

;-----------------------------------
BRISI                   ; edit delete
        jp      fix1
        defb      0xFF

;-----------------------------------
move00
	jp	move_ept

;-----------------------------------
rescan0
	jp	rescan_ept

;-----------------------------------
blocks0
	jp	blocks

;-----------------------------------
BKSP                    ; edit left
        LD      A,L
        CP      lo(BUF)
        JR      Z,OPET
        DEC     HL
        JR      OPET

;-----------------------------------
ADV                     ; edit right
        LD      A,(HL)
        CP      0DH
        JR      Z,OPET
        JR      INCOP

;-----------------------------------
EDIT                    ; EDIT EPT
        CALL    BEC4    ; CONVERT STRING TO INTEGER
        CALL    Z92A    ; find basic line number >= HL, starting DE
        JP      C,HOW   ; if not found (C set) then HOW?
        LD      A,0CH   ; CLS (HOME)
        RST     Z16     ; PRINT CHAR IN A ON SCREEN
        LD      HL,BUF
        LD      (2A68H),HL  ; Pozicija kursora u memoriji
        CALL    ZA63    ; print number and BASIC line (ptr DE)
        EXX
OPET                    ; redraw the editing line
        LD      DE,2800H    ; video mem start
        LD      (2A68H),DE  ; Pozicija kursora u memoriji
        LD      DE,BUF
        LD      C,(HL)
        LD      (HL),0
        CALL    Z94F
        LD      A,95
        CALL    SPEC
        CALL    TASTAT
        CP      0DH
        JR      Z,IZLAZ1
        OR      A
        JR      Z,BRISI
        CP      1DH
        JR      Z,BKSP
        CP      1EH
        JR      Z,ADV
        JR      C,OPET
        LD      B,A
        PUSH    HL
        LD      HL,BASIC-6
        RST     Z32
        POP     HL
        JR      C,OPET
INSERT  DEC     DE
        LD      A,(DE)
        INC     DE
        LD      (DE),A
        DEC     DE
        RST     Z32
        JR      NZ,INSERT
        LD      (HL),B
INCOP   INC     HL
        JR      OPET

IFNR    LD      A,(2A68H)
        AND     31
        LD      A,0DH
        LD      (stack+13),A
        RET     Z
        RST     Z16     ; PRINT CHAR IN A ON SCREEN
        RET

TESTB   LD      A,(2033H)       ; test if DEL pressed
        RRCA
        RET     C
IFBRK   LD      A,(2031H)       ; test if BREAK pressed
        RRCA
        JR      C,TESTB

STOP    CALL    IFNR
        LD      DE,BRK
        CALL    Z94F
        LD      DE,(2A9FH)
        LD      A,D
        OR      E
        CALL    NZ,PrintDE

Z1C9    EQU     $               ; Break EPT
        EI
        CALL    IFNR
        LD      DE,Z1AE
        CALL    Z94F
Z1D8    RST     HL0
        LD      DE,3031H        ; BRK-RET PRESET
        LD      SP,2AA7H
        PUSH    DE
        PUSH    HL
        PUSH    HL
        PUSH    HL
        LD      HL,(BASPTR)
        INC     HL
        INC     HL
        PUSH    HL              ; RESTORE
        LD      SP,stack
        LD      IX,IXPOS
        CALL    Z8FA
IZLAZ1  PUSH    DE
        LD      DE,BUF
        CALL    BEC4    ; CONVERT STRING TO INTEGER
        POP     BC
        JP      Z,X340
        DEC     DE
        LD      A,H
        LD      (DE),A
        DEC     DE
        LD      A,L
        LD      (DE),A
        PUSH    BC
Z1F9    PUSH    DE
        LD      A,C
        SUB     E
        PUSH    AF
        CALL    Z92A    ; find basic line number >= HL, starting DE
        PUSH    DE
        JR      NZ,Z213
        PUSH    DE
        CALL    Z945
        POP     BC
        LD      HL,(BASEND)
        CALL    ZA6F
        LD      H,B
        LD      L,C
        LD      (BASEND),HL
Z213    POP     BC
        LD      HL,(BASEND)
        POP     AF
        PUSH    HL
        CP      3
        JR      Z,Z1D8
        LD      E,A
        LD      D,0
        ADD     HL,DE
        LD      DE,(2a6AH-0)
        RST     Z32
        JP      NC,SORRY
        LD      (BASEND),HL
        POP     DE
        CALL    ZA77
        POP     DE
        POP     HL
        CALL    ZA6F
        JR      Z1D8

X340			; 
	LD      HL,Z1C9	; Z1C9 = Break ept
        PUSH    HL	; \\
        LD      L,lo(INSTRUC)
        DEFB    1	; Dummy "ld bc,nn" (skip next 2 bytes)
Z7ED    LD      L,lo(Z2EE)
        DEFB    1	; Dummy "ld bc,nn" (skip next 2 bytes)
IFCHR   LD      L,lo(ZACHR-1)
Z343    LD      H,0FH	; hi byte addr of instruction table
X343    CALL    Z40	; Z40 = skip blanks (ptr DE)
        PUSH    DE	; \\  Store addr of first char on stack
        INC     DE	; advance RAM ptr (program)
        INC     HL	; advance ROM ptr (table)
        CP      (HL)	; compare RAM byte : ROM byte
        JR      Z,Z351	; if equal
        BIT     7,(HL)	; was there 80H+ ?
        JR      NZ,Z35B	; \ no there was not 80H+
        JR      Z362	; \ yes there was 80H+
Z351    LD      A,(DE)
        INC     DE	; advance RAM ptr (program)
        INC     HL	; advance ROM ptr (table)
        CP      (HL)	; compare RAM byte : ROM byte
        JR      Z,Z351	; if equal
        BIT     7,(HL)	; was there 80H+ ?
        JR      Z,Z35E	; \ yes there was 80H+
Z35B    DEC     DE
        JR      Z370	; / 
Z35E    CP      2EH	; / 2EH = "."
        JR      Z,Z36B
Z362    INC     HL	; 
        BIT     7,(HL)	; was there 80H+ ?
        JR      Z,Z362	; 
        INC     HL
        POP     DE	; //
        JR      X343
Z36B    INC     HL
        BIT     7,(HL)	; was there 80H+ ?
        JR      Z,Z36B
Z370    LD      A,(HL)
        INC     HL
        LD      L,(HL)
        AND     7FH	; clean address from bit 7 (80H+)
        LD      H,A
        POP     AF	; //
        BIT     6,H	; was there 40H+ ?
        RES     6,H
        PUSH    HL	; \\
        CALL    NZ,Z814	; if there was 40H+ (eval expression)
        JP      stack+1         ;   INSTRUCTION LINK

Z18E    IM      1
        LD      IY,LINK3
        LD      HL,27FFH
        LD      (HL),L
        LD      B,L
GOONCP  INC     HL
        LD      (HL),B
        INC     (HL)
        JR      NZ,GOTOVO
        OR      (HL)
        JR      Z,GOONCP
GOTOVO
	dec	h
	dec	h		; minus 512 by (space for FlBuf)
	dec	hl
	dec	hl		; minus 2 more (space for chs)
	nop
	nop
        LD      (2A6AH-0),HL
  ;;;      LD      SP,stack+5
  ;;;      LD      HL,0C900H+HOR    ; HOR POS and RET
  ;;;      PUSH    HL          ;  1  VIDEO LINK
  ;;;      DEC     SP          ;  1
  ;;;      PUSH    HL          ;  1  HOR and LINK
        jp      rpt_and_ini_b  ;;;  3  initialize ROM B
back1
        LD      A,0CH   ; CLS (HOME)
        RST     Z16             ; PRINT CHAR IN A ON SCREEN
NEW                          ;       NEW
        CALL    BEC4    ; CONVERT STRING TO INTEGER
        LD      DE,BASIC
        ADD     HL,DE
        LD      SP,BASIC
        PUSH    HL
        PUSH    HL
Z384    JP      SP1C9
run_ept            ;       RUN
        CALL    BEC4    ; CONVERT STRING TO INTEGER
        LD      DE,(BASPTR)
        JR      go_run


Z8B3    LD      (stack+13),A
        RST     Z8
        DEFB    3AH
        DEFB    AS3-$-1
OVERPL  POP     AF
        JR      Z3A2
AS3     RST     Z8
        DEFB    0DH
        DEFB    ASRET-$-1
        POP     AF
Z394    RST     HL0
go_run  CALL    Z92D
        JR      C,Z384
Z39C    LD      (2a9FH-0),DE
        INC     DE
        INC     DE
Z3A2    CALL    IFBRK
        LD      IX,IXPOS
        LD      L,lo(Z26C)
        JP      Z343

Z799    CALL    Z7AD
        CALL    ZCB1
        RST     HL0
ASRET   RET

Z5FB    RST     Z807    ;       IF
        LD      A,H
        OR      L
        JR      NZ,Z3A2
        CALL    X947
ASIF    JR      NC,Z39C
        JR      Z384

Z5F6    RST     HL0     ; #,!,ELSE
        CALL    Z947
        JR      ASIF

Z3B5    RST     Z807    ;       GOTO
X3BC    PUSH    DE
Z3BC    CALL    Z92A    ; find basic line number >= HL, starting DE
        JP      NZ,Z1A3
        POP     AF
        JR      Z39C

LIST                     ;       LIST
        CALL    BEC4    ; CONVERT STRING TO INTEGER
LIST2   CALL    IFNR
        CALL    Z92A    ; find basic line number >= HL, starting DE
GOFARM  JR      C,Z384
LISTIT  CALL    ZA63
        CALL    Z92D
        JR      C,GOFARM
LOOPL   CALL    IFBRK
        LD      A,(2030H) ; key RETURN
        LD      HL,2034H  ; key LIST
        AND     (HL)
        RRCA
        JR      NC,LISTIT ; test bit 0
        JR      LOOPL

Z42F    RST     Z8      ;       PRINT
        DEFB    ':'
        DEFB    Z443-$-1
        LD      A,0DH
        RST     Z16     ; PRINT CHAR IN A ON SCREEN
        JR      Z3A2
Z443    RST     Z8
        DEFB    0DH
        DEFB    Z44C-$-1
        RST     Z16     ; PRINT CHAR IN A ON SCREEN
ZA394   JR      Z394
Z452    EQU     $
        RST     Z8
        DEFB    '"'
        DEFB    Z499-$-1
        CALL    Z950
        JR      NZ,ZA394
        JR      Z464
Z459    LD      L,92            ; X$
        DEFB    1       ; DUMMY LD BC,
Z45E    LD      L,96            ; Y$
Z460    LD      H,2AH
        CALL    Z6A4
Z461    LD      A,(HL)
        INC     HL
        OR      A
        JR      Z,Z464
        RST     Z16     ; PRINT CHAR IN A ON SCREEN
        LD      A,L
        AND     0FH
        JR      NZ,Z461
Z464    RST     Z8
        DEFB    2CH
        DEFB    Z48D-$-1
Z467    LD      A,(2A68H)
        AND     07H
        JR      Z,Z490
ZAREZ2  LD      A,20H
        RST     Z16     ; PRINT CHAR IN A ON SCREEN
        JR      Z467
Z473    RST     Z807    ;       AT
        LD      A,H
        OR      28H
        AND     29H
        LD      H,A
        LD      (2A68H),HL
        RST     Z8
        DEFB    2CH
        DEFB    2
        JR      Z490
Z48D    RST     Z8
        DEFB    3BH
        DEFB    Z495-$-1
Z490    CALL    Z8B3
Z44C    LD      L,lo(Z319)
        JP      Z343
HOME    CALL    BEC4    ; CONVERT STRING TO INTEGER
        LD      (2A6CH),HL
        JR      NZ,SKRSC
Z4B5    LD      A,0CH      ; CLS (HOME)
        DEFB    1       ;       DUMMY LD BC,
Z495    LD      A,0DH
        RST     Z16     ; PRINT CHAR IN A ON SCREEN
SKRSC   RST     Z48
Z499    CALL    IFCHR
        JR      NZ,DACHR
        CALL    Z24
        CALL    Z970
        DEFB    3EH     ; DUMMY LD A,
DACHR   RST     Z16     ; PRINT CHAR IN A ON SCREEN
        JR      Z464
Z4C4    CALL    ZA9F    ;       CALL
        RST     Z807
Z4CA    PUSH    DE
        CALL    Z92A    ; find basic line number >= HL, starting DE
        JP      NZ,Z1A3
        LD      HL,(2a9FH-0)
        PUSH    HL
        LD      HL,(2aA3H-0)
        PUSH    HL
        RST     HL0
        LD      (2aA1H-0),HL
        ADD     HL,SP
        LD      (2aA3H-0),HL
        JP      Z39C
Z4E6    EQU     $       ;       RETURN
        LD      HL,(2aA3H-0)
        LD      A,H
        OR      L
        JP      Z,HOW
        LD      SP,HL
        POP     HL
        LD      (2aA3H-0),HL
        POP     HL
        LD      (2a9FH-0),HL
        POP     DE
Z5F2    CALL    ZA84
        RST     Z48

Z560    RST     Z807    ;       STEP
        DEFB    1       ; DUMMY LD BC,
Z565    RST     HL0     ;       NO STEP
        INC     HL
Z568    LD      (2a91H-0),HL
        LD      HL,(2a9FH-0)
        LD      (2a93H-0),HL
        EX      DE,HL
        LD      (2a95H-0),HL
        LD      BC,0AH
        LD      HL,(2aA1H-0)
        EX      DE,HL
        RST     HL0
        ADD     HL,SP
        DEFB    3EH     ; DUMMY LD A,
Z580    ADD     HL,BC
        LD      A,(HL)
        INC     HL
        OR      (HL)
        JR      Z,Z59E
        LD      A,(HL)
        DEC     HL
        CP      D
        JR      NZ,Z580
        LD      A,(HL)
        CP      E
        JR      NZ,Z580
        EX      DE,HL
        RST     HL0
        ADD     HL,SP
        LD      B,H
        LD      C,L
        LD      HL,0AH
        ADD     HL,DE
        CALL    ZA77
        LD      SP,HL
Z59E    LD      HL,(2a95H-0)
        EX      DE,HL
        RST     Z48
Z5A3    CALL    IF56    ;       NEXT
        LD      (2a9BH-0),HL
Z5AA    PUSH    DE
        EX      DE,HL
        LD      HL,(2aA1H-0)
        LD      A,H
        OR      L
        JP      Z,Z1A3
        RST     Z32
        JR      Z,Z5C0
        POP     DE
        CALL    ZA84
        LD      HL,(2a9BH-0)
        JR      Z5AA
Z5C0    CALL    ZBC3
        CALL    ZC0B
        EX      DE,HL
        LD      HL,(2a91H-0)
        PUSH    HL
        ADD     HL,DE
        PUSH    HL
        CALL    ZC59
        LD      HL,(2aA1H-0)
        CALL    ZBE9
        POP     DE
        LD      HL,(2a6EH-0)
        POP     AF
        RLCA
        JR      NC,Z5E0
        EX      DE,HL
Z5E0    LD      A,H
        XOR     D
        JP      P,Z5E6
        EX      DE,HL
Z5E6    RST     Z32
        POP     DE
        JP      C,Z5F2
        LD      HL,(2a93H-0)
        LD      (2a9FH-0),HL
        JR      Z59E

Z654    JP      Z,Z8AE
AGN     PUSH    HL      ; PRIMA STRING
        CALL    Z694
        JR      C,NES
        JR      Z,CM
        EX      (SP),HL
        POP     BC
TRANS   LD      A,(BC)
        OR      A
        JR      Z,NULE2
        INC     BC
        CALL    STRSUB
        JR      NZ,TRANS
        RET
NES     POP     HL
        RST     Z8
        DEFB    '"'
        DEFB    0
NENAV   CALL    X68A
        JR      Z,NULE2
        INC     DE
        CALL    STRSUB
        JR      NZ,NENAV
X68A    LD      A,(DE)
        CP      0DH     ; CR
        RET     Z
        CP      22H     ; "
        RET     NZ
        INC     DE
        RET
CM      DEC     DE
        CALL    IFCHR
        JR      Z,NES
CH      POP     HL
        CALL    STRSUB
        RET     Z
NULE2   RST     Z8
        DEFB    '+'
        DEFB    NULE-$-1
        JR      AGN
NULE    LD      (HL),0
ASC0    CALL    SKRASC
        RET     Z
        LD      (HL),30H
        JR      ASC0
Z694    CALL    Z56	; LOCIRAJ VARIJABLU	CY = nema var
				;				A=0 (Z) = numericka
				;				A>0 (NZ) = string
        RET     C
        DEC     DE
        LD      A,(DE)
        INC     DE
        CP      29H
        RET     Z
        LD      A,(DE)
        CP      24H
        JR      Z,Z6A3
Z749    XOR     A
        RET
Z6A3    INC     DE
Z6A4    LD      A,L
        SUB     92
        JR      NZ,BS
        LD      L,70H
        RST     Z8
        DEFB    '('
        DEFB    3
        CALL    STRMAT
        OR      H
        RET
BS      CP      7
        JP      NC,WHAT ; WHAT?
        LD      L,80H
        OR      H
        RET

TAKE    CALL    Z694
        JR      C,CIFRE
        PUSH    DE
        PUSH    AF
        PUSH    HL
        LD      DE,(2A9DH)
        LD      HL,(BASEND)
SRCHT   RST     Z8
        DEFB    '#'
        DEFB    NETAR1-$-1
        JR      FOUNDT
NETAR1  RST     Z8
        DEFB    ','
        DEFB    NETAR-$-1
FOUNDT  POP     HL
        POP     AF
        CALL    Z654
SKRT    LD      (2A9DH),DE
        POP     DE
        RST     Z8
        DEFB    ','
        DEFB    SEE48-$-1
        JR      TAKE
NETAR   LD      A,(DE)
        INC     DE
        CP      0DH
        JR      NZ,NETAR
        INC     DE
        INC     DE
        RST     Z32
        JR      NC,SRCHT
        POP     HL
Z745    POP     AF
        DEFB    0EH     ; DUMMY LD C,
HOW    PUSH    DE      ; HOW? ENTRY PT
Z1A3    CALL    Z8CD
        DEFM    'HOW?'
        DEFB    0DH

CIFRE   RST     Z807
        PUSH    DE
        CALL    Z92A    ; find basic line number >= HL, starting DE
        INC     DE
        INC     DE
        JR      SKRT


Z623    EQU     $       	; INPUT
        PUSH    DE	; \
        LD      A,3FH
        CALL    Z8FC		; 
        LD      DE,BUF
        RST     Z8
        DEFB    0DH		; if <CR>
        DEFB    INPOK-$-1	; then goto inpok
        POP     DE	; /
        CALL    Z694
        RST     Z48
INPOK   POP     DE	; /
        PUSH    DE	; \
Z6D4    CALL    Z694
        JR      C,Z1A3
        PUSH    DE	; \\
        LD      DE,BUF
        CALL    Z654
        POP     DE	; //
        POP     AF	; /
SEE48   RST     Z48



Z7AD    RST     Z8
        DEFB    2DH
        DEFB    Z7B8-$-1
        RST     HL0
        CALL    ZC59
        JR      Z7CC
Z7B8    RST     Z8
        DEFB    2BH
        DEFB    0
        CALL    Z7D4
Z7BE    RST     Z8
        DEFB    2BH
        DEFB    Z7C9-$-1
        CALL    Z7D4
        CALL    ZCD3
        JR      Z7BE
Z7C9    RST     Z8
        DEFB    2DH
        DEFB    Z803-$-1
Z7CC    CALL    Z7D4
        CALL    ZCBF
        JR      Z7BE
Z7D4    CALL    Z7ED
Z7D7    RST     Z8
        DEFB    2AH
        DEFB    Z7E2-$-1
        CALL    Z7ED
        CALL    ZC87
        JR      Z7D7
Z7E2    RST     Z8
        DEFB    2FH
        DEFB    Z803-$-1
        CALL    Z7ED
        CALL    ZC98
        JR      Z7D7

Z838    LD      A,1     ;       UNDOT
        DEFB    1       ; DUMMY LD BC,
Z83C    LD      A,80H   ;       DOT
        PUSH    AF
        RST     Z8
        DEFB    '*'
        DEFB    NOCLK-$-1
        POP     AF
        LD      (stack+7),A
        RST     Z48
NOCLK   POP     AF
        DEFB    6       ; DUMMY LD B,
Z840    XOR     A       ;       IF DOT
        AND     A
        PUSH    AF
        RST     Z807
        PUSH    HL
        CALL    ZAREZ
        PUSH    DE
CONTXY  EX      DE,HL
        LD      BC,20H
        INC     E
        LD      HL,2800H
GOY     LD      D,3
        LD      A,1
Y3      DEC     E
        JR      Z,GOTY
        RLCA
        RLCA
        DEC     D
        JR      NZ,Y3
        ADD     HL,BC
        RES     1,H
        JR      GOY
GOTY    LD      B,A
        POP     DE
        EX      (SP),HL
        RES     7,L
        RES     6,L
        SRL     L
        JR      NC,PARNI
        RLCA
PARNI   LD      H,0
        POP     BC
        ADD     HL,BC
        LD      B,A
        POP     AF
        LD      A,B
        JR      NZ,SETRES
        BIT     7,(HL)
        JR      Z,NISTA
        AND     (HL)
NISTA   RST     HL0
        JR      Z,OSTA0
        INC     HL
OSTA0   JP      ZC59
SETRES  PUSH    AF
        BIT     7,(HL)
        JR      NZ,SR
        LD      (HL),80H
SR      POP     AF
        JP      M,SETXY
        CPL
        AND     (HL)
        DEFB    6       ; LD B,
SETXY   OR      (HL)
        LD      (HL),A
        RST     Z48


Z8A8    CALL    IF56
        RST     Z8
        DEFB    3DH
        DEFB    WHAT-$-1
Z8AE    PUSH    HL
        CALL    Z24
ZBE8    POP     HL
ZBE9    CALL    IXFFFB
        LD      BC,4
        PUSH    DE
        PUSH    HL
        EX      DE,HL
        PUSH    IX
        POP     HL
        LDIR
        EX      DE,HL
        DEC     HL
        DEC     HL
        RL      (HL)
        INC     HL
        LD      A,(IX+4)
        RLA
        RR      (HL)
        DEC     HL
        RR      (HL)
        POP     HL
        POP     DE
        RET

Z6B3    EQU     $
        CALL    Z694
        JR      C,GOTO48
        PUSH    AF
        RST     Z8
        DEFB    3DH
        DEFB    WHAT-$-1
        POP     AF
        CALL    Z654
GOTO48  RST     Z48

PTR     LD      H,D
        LD      L,E
        CALL    Z694
        JR      OSTA0

VAL     PUSH    DE
        EX      DE,HL
        CALL    Z24
        POP     DE
        RET

Z7F2    CALL    Z56
        JP      NC,ZBC3
        CALL    ZA6
        RET     NZ
Z7FC    RST     Z8
        DEFB    28H	; '('
        DEFB    WHAT-$-1 ; If '(' not found, go WHAT
        CALL    Z24	; eval expression
        RST     Z8; IF ((SP))=(DE) THEN (SP)=(SP)+2
                        ; ELSE (SP)=((SP)+1)+(SP)+2
        DEFB    29H	; ')'
        DEFB    1	; if not ")" go WHAT (skip RET)
Z803    RET


IF56    CALL    Z56
        RET     NC
WHAT    PUSH    DE      ; WHAT? ENTRY PT
Z8CA    CALL    Z8CD
        DEFM    'WHAT?'
        DEFB    0DH
Z8CD    POP     DE
ERROR_EP
        CALL    Z94F
        LD      DE,(2a9FH-0)
        LD      A,E
        OR      D
AS1C9   EQU     $
        LD      HL,Z1C9		; Z1C9 = Break ept
        EX      (SP),HL
        RET     Z
        RST     Z32
        RET     C
        LD      C,(HL)
        PUSH    BC
        LD      (HL),0
        PUSH    HL
        CALL    ZA63
        POP     HL
        POP     BC
        LD      A,3FH   ; ?
SPEC    DEC     DE
        LD      (HL),C
        JP      S94F



			; upis sa tastature u bafer
Z8FA    LD      A,3EH
Z8FC    LD      DE,BUF
        RST     Z16     ; PRINT CHAR IN A ON SCREEN
Z900X   EXX
        LD      (HL),95
        EXX
Z900    CALL    TASTAT
        RST     Z16     ; PRINT CHAR IN A ON SCREEN
        EXX
        LD      (HL),95
        EXX
        CP      0DH     ; CR?
        JR      Z,Z915
        CP      1DH     ; BKSP?
        JR      Z,Z922
        CP      0CH     ; CLS?
        JR      Z,Z8FA
        CP      20H     ; ' '?
        JR      C,Z900
Z915    LD      (DE),A
        INC     DE
        CP      0DH
        RET     Z
        LD      A,E
        CP      lo(BASIC-6)
        JR      NZ,Z900
        LD      A,1DH           ; BKSP
        RST     Z16             ; PRINT CHAR IN A ON SCREEN
Z922    LD      A,E
        CP      lo(BUF)
        JR      Z,Z8FA
        DEC     DE
        JR      Z900X


Z92A                    ; find basic line number >= HL, starting DE
        LD      DE,(BASPTR)
Z92D    PUSH    HL
        LD      HL,(BASPTR)
        DEC     HL
        RST     Z32
        JP      NC,Z1C9		; Z1C9 = Break ept
        LD      HL,(BASEND)
        DEC     HL
        RST     Z32
        POP     HL
        RET     C
        LD      A,(DE)
        SUB     L
        LD      B,A
        INC     DE
        LD      A,(DE)
        SBC     A,H
        JR      C,Z946
        DEC     DE
        OR      B
        RET


Z945    INC     DE
Z946    INC     DE
Z947    LD      A,(DE)
        CP      0DH
        JR      NZ,Z946
YES0D   INC     DE
        JR      Z92D

NOTE0D  INC     DE
X947    LD      A,(DE)
        RST     HL0
        CP      0DH
        JR      Z,YES0D
        CP      '!'
        JR      Z,Z946
        CP      '"'
        JR      NZ,IGN
GONAV   INC     DE
        LD      A,(DE)
        CP      0DH
        JR      Z,YES0D
        CP      '"'
        JR      NZ,GONAV
IGN     CP      'E'
        JR      NZ,NOTE0D
        LD      L,lo(XELSE-1)
        JP      Z343

Z983    LD      A,(IX-1)
        AND     A
        LD      A,20H
        JR      Z,Z98D
        LD      A,2DH
Z98D    RST     Z16     ; PRINT CHAR IN A ON SCREEN
        XOR     A
        LD      (IX-1),A
        DEC     A
Z994    PUSH    AF
        LD      HL,ZEB9
        CALL    ZCA6
        JR      NC,Z9A4
        CALL    ZC84
        POP     AF
        DEC     A
        JR      Z994


LOOP1   CALL    ZC95
        POP     AF
        INC     A
        PUSH    AF
Z9A4    LD      HL,ZEB5
        CALL    ZCA6
        JR      NC,LOOP1


Z9B4    LD      A,(IX-2)
        NEG
Z9B9    JR      Z,Z9C6
        EXX
        SRL     C
        RR      H
        RR      L
        EXX
        DEC     A
        JR      Z9B9


Z9C6    LD      B,7
        PUSH    IX
        POP     HL
        LD      (HL),0
        INC     HL
Z9CE    XOR     A
        CALL    Z15E
        EXX
        LD      A,B
        EXX
        LD      (HL),A
        INC     HL
        DJNZ    Z9CE
        LD      BC,600H
        DEC     HL
        LD      A,(HL)
        CP      5
Z9E2    CCF
        LD      A,0
        DEC     HL
        ADC     A,(HL)
        SLA     C
        CP      0AH
        JR      C,Z9EF
        LD      A,0
Z9EF    LD      (HL),A
        PUSH    AF
        AND     A
        JR      Z,Z9F6
        SET     0,C
Z9F6    POP     AF
        DJNZ    Z9E2
        LD      A,C
        POP     BC
        JR      C,ZA03
        INC     B
        PUSH    BC
        LD      B,1
        JR      Z9E2
ZA03    LD      C,A
        LD      A,B
        INC     A
        JP      M,ZA13
        CP      7
        JR      NC,ZA13
        LD      B,A
        CALL    ZA4D
        JR      ZA41


ZA13    PUSH    BC
        LD      B,1
        CALL    ZA4D
        LD      A,45H
        RST     Z16     ; PRINT CHAR IN A ON SCREEN
        POP     BC
        BIT     7,B
        LD      A,2BH
        JR      Z,ZA2B
        LD      A,2DH
        RST     Z16     ; PRINT CHAR IN A ON SCREEN
        LD      A,B
        NEG
        JR      ZA2D


ZA2B    RST     Z16     ; PRINT CHAR IN A ON SCREEN
        LD      A,B
ZA2D    LD      B,30H
ZA2F    CP      0AH
        JR      C,ZA38
        ADD     A,0F6H
        INC     B
        JR      ZA2F
PrintDE	LD	A,(DE)	; PRINT DECIMAL INTEGER (DE) ON SCREEN
        LD      L,A
        INC     DE
        LD      A,(DE)
        LD      H,A
        INC     DE
PrintHL	CALL	ZC59	; PRINT HL ON SCREEN (ZC59 = INT ept)
Z970    PUSH    DE
        PUSH    BC
        PUSH    HL
        LD      A,(IX-2)
        CP      80H
        JP      NZ,Z983
        XOR     A
        LD      B,20H
ZA38    OR      30H
        LD      C,A
        LD      A,B
RA41    RST     Z16     ; PRINT CHAR IN A ON SCREEN
        LD      A,C
        RST     Z16     ; PRINT CHAR IN A ON SCREEN
ZA41    EQU     $       ; BLANK POSLE BROJA
        POP     HL
        POP     BC
DEIXBC  POP     DE
IXFFFB  LD      BC,0FFFBH
ZAIX    ADD     IX,BC
        RET

ZE10IX  CALL    ZE00
BC10IX  LD      BC,0AH
        JR      ZAIX

ZA4D    INC     B
ZA4E    DJNZ    ZA54
        LD      A,2EH
        RST     Z16     ; PRINT CHAR IN A ON SCREEN
ZA54    LD      A,(HL)
        OR      30H
        RST     Z16     ; PRINT CHAR IN A ON SCREEN
        INC     HL
        SRL     C
        JR      NZ,ZA4E
        DEC     B
        DEC     B
        RET     M
        INC     B
        JR      ZA4D
ZA63                  ; print number and BASIC line (ptr DE)
        CALL    PrintDE
        LD      A,20H
S94F    RST     Z16     ; PRINT CHAR IN A ON SCREEN

Z94F    XOR     A
Z950    LD      B,A
Z951    LD      A,(DE)
        INC     DE
        CP      B
        RET     Z
        RST     Z16     ; PRINT CHAR IN A ON SCREEN
        CP      0DH
        JR      NZ,Z951
        INC     A       ; RESET Z FLAG
        RET

ZA6F    RST     Z32
        RET     Z
        LD      A,(DE)
        LD      (BC),A
        INC     DE
        INC     BC
        JR      ZA6F
ZA77    LD      A,B
        SUB     D
        JR      NZ,ZA7E
        LD      A,C
        SUB     E
        RET     Z
ZA7E    DEC     DE
        DEC     HL
        LD      A,(DE)
        LD      (HL),A
        JR      ZA77
ZA84    POP     BC
        POP     HL
        LD      (2aA1H-0),HL
        LD      A,H
        OR      L
        JR      Z,ZA9D
        POP     HL
        LD      (2a91H-0),HL
        POP     HL
        LD      (2a6EH-0),HL
        POP     HL
        LD      (2a93H-0),HL
        POP     HL
        LD      (2a95H-0),HL
ZA9D    PUSH    BC
        RET
ZA9F    LD      HL,0FFFFH-stack+113	; (=0xD4C8), (=-0x2B38)
        POP     BC		; /	; RET addr
        ADD     HL,SP
        JP      NC,SORRY
        LD      HL,(2aA1H-0)
        LD      A,H
        OR      L
        JR      Z,ZAC8
        LD      HL,(2a95H-0)
        PUSH    HL
        LD      HL,(2a93H-0)
        PUSH    HL
        LD      HL,(2a6EH-0)
        PUSH    HL
        LD      HL,(2a91H-0)
        PUSH    HL
        LD      HL,(2aA1H-0)
ZAC8    PUSH    HL
        PUSH    BC		; \	; RET addr
        RET

Z7A7    RST     Z8
        DEFB    '>'
        DEFB    NFOUNV-$-1
        CALL    Z799
        RET     Z
        RET     C
        INC     HL
        RET
NFOUNV  RST     Z8
        DEFB    '='
        DEFB    NFOUNJ-$-1
        CALL    Z799
        RET     NZ
        INC     HL
        RET
NFOUNJ  RST     Z8
        DEFB    '<'
        DEFB    Z797-$-1
        CALL    Z799
        RET     NC
        INC     HL
        RET

ZACB    PUSH    AF              ; print char in A on screen (RST Z16H)
        CALL    stack+4 ; LINK
        LD      HL,(2A68H)      ; Pozicija kursora u memoriji
        JR      C,ZB11          ; A = spec. code (<0x20)
        LD      (HL),A
        INC     HL
ZAF2                    ; cont with new cursor pos
        LD      A,2AH
        CP      H
        JR      NZ,ZB09
        LD      HL,stack+8
        CALL    WAIT    ; DOK SE ZAVRSI KLIZANJE
        PUSH    HL
        INC     HL
        INC     (HL)
        CALL    WAIT    ; DOK NE PRODJE 1 SLIKA
        OR      A
        LD      DE,(2A6CH)
        RES     1,D
        LD      HL,1E0H
        SBC     HL,DE
        JR      Z,IGNSCR
        JR      C,IGNSCR
        LD      B,H
        LD      C,L
        SET     3,D     ; DA BUDE DE=2800H, VIDEO
        SET     5,D     ; DA BUDE DE=2800H, VIDEO
        LD      HL,20H
        ADD     HL,DE
        LDIR            ; 1 RED NAGORE
IGNSCR  LD      HL,(2A6CH)
        LD      A,H
        OR      L
        POP     HL
        JR      NZ,NOT3
        LD      (HL),3  ; KLIZANJE U 3 FAZE
NOT3    LD      HL,29E0H        ; ZADNJI RED
        PUSH    HL
        CALL    ZB37    ; BRISANJE REDA 16
        POP     HL
ZB09    LD      (2A68H),HL      ; restore cursor ptr
Z797    POP     AF
        RET
ZB11                    ; print A = spec. code (<0x20) on screen
        CP      0DH             ; CR?
        JR      NZ,ZB1A         ; if not CR
CRET    LD      A,H
        CP      2BH
        JR      C,NEDITM
        LD      (HL),0DH
        JR      ZB09
NEDITM  CALL    ZB37
        JR      ZAF2
ZB1A    CP      0CH             ; CLS?
        JR      NZ,ZB2E         ; if not CLS
        LD      HL,29FFH        ; 00101001 11111111
GOCLR   LD      (HL),20H
        DEC     HL
        BIT     1,H
        JR      Z,GOCLR         ; if cursor still in screen
ADJUST1 INC     HL              ; restore to 1st screen pos
        JR      ZB09
ZB2E
        CP      1DH             ; BKSP?
        JR      NZ,ZB09         ; not BKSP
                                ; backspace
        LD      (HL),20H        ; print ' '
        DEC     HL              ; move cursor left
        BIT     1,H             ; out of screen left?
        JR      NZ,ADJUST1      ; out of screen left, readjust
        JR      ZB09            ; no, still in screen
ZB37                    ; BRISANJE REDA 16
        LD      (HL),20H
        INC     HL
        LD      A,L
        AND     1FH
        JR      NZ,ZB37
        RET

WAIT    LD      A,I
        RET     PO
WAIT2   LD      A,(HL)
        OR      A
        JR      NZ,WAIT2
        RET

ZBC3		      ; dodeli FP vrednost varijabli koja je pozvala funkciju
	PUSH    DE
        PUSH    HL
        PUSH    AF
        LD      BC,4
        PUSH    IX
        POP     DE
        LDIR
        RL      (IX+2)
        RL      (IX+3)
        LD      A,B
        RRA
        LD      (IX+4),A
        SCF
        RR      (IX+2)
        LD      C,5
        ADD     IX,BC
        POP     AF
        POP     HL
        POP     DE
        RET
Z814    CALL    Z7FC
ZC0B                    ; FLOATING POINT TO INTEGER
        EXX
        CALL    IXFFFB
        LD      DE,0
        LD      A,(IX+3)
        LD      C,(IX+4)
        CP      80H
        JR      Z,ZC52
        CP      1
        JP      M,ZC2C
        CP      10H
        EXX
        JP      P,HOW
        EXX
ZC30    LD      B,A
        LD      A,(IX+0)
        LD      L,(IX+1)
        LD      H,(IX+2)
ZC3A    SLA     A
        ADC     HL,HL
        RL      E
        RL      D
        DJNZ    ZC3A
ZC46    SLA     C
        JR      NC,ZC52
        OR      H
        OR      L
        JR      Z,ZC4F
        INC     DE
ZC4F    CALL    ZC78
ZC52    PUSH    DE
        EXX
        POP     HL
        RET

ZC2C    LD      A,0FFH
        JR      ZC46
Z24     CALL    Z7AD
Z75D    CALL    Z7A7
        DEFB    1       ; DUMMY LD BC,
ZC56    LD      HL,0AH
ZC59    PUSH    DE
ZC5A    EX      DE,HL
        CALL    BC10IX
        CALL    ZC75
        PUSH    DE
        LD      HL,10H
        RR      H
        EXX
        POP     DE
        RST     HL0
        LD      H,E
        LD      C,D
        CALL    ZE00
        JR      ZCA4
ZC75    XOR     A
        ADD     A,D
        RET     P
ZC78    LD      A,E
        NEG
        LD      E,A
        LD      A,D
        CPL
        CCF
        ADC     A,0
        LD      D,A
        SCF
        RET
ZC84    CALL    ZC56
ZC87    CALL    ZE1E		; PUTA (mnozenje)
        JR      Z,ZCCA
        CP      E
        JP      Z,ZD0D
        CALL    ZD27
        JR      ZCA4
ZC95    CALL    ZC56
ZC98    CALL    ZE1E		; KROZ (deljenje)
        JR      Z,ZCCA
        CP      E
        JP      Z,Z1A3
        CALL    ZD5C
ZCA4    JR      ZD0F
ZCA6    CALL    ZBC3
        CALL    ZE1E
        LD      BC,0FFFBH
        JR      ZCB7
ZCB1    CALL    ZE1E		; CPIXIX
        LD      BC,0FFF6H
ZCB7    ADD     IX,BC
        CP      L
        CALL    ZD94
        POP     DE
        RET
ZCBF    CALL    ZE1E		; MINUS (oduzimanje)
        JR      NZ,ZCC9
        CALL    ZD03
        JR      ZCF9
ZCC9    CP      E
ZCCA    JR      Z,ZD20
ZCCC    XOR     D
        LD      D,A
        JR      ZCDB
        CALL    ZBC3
ZCD3    CALL    ZE1E		; PLUS (sabiranje)
        JR      Z,ZD04
        CP      E
        JR      Z,ZD20
ZCDB    CALL    ZDB3
        JR      Z,ZCEE
        JR      NC,ZCE9
        EX      DE,HL
        EXX
        EX      DE,HL
        LD      A,C
        LD      C,B
        LD      B,A
        EXX
ZCE9    CALL    ZDCB
        JR      ZD0F
ZCEE    LD      A,H
        XOR     D
        JR      NZ,ZD0D
        LD      E,1
        CALL    ZDF3
        JR      ZD0F
ZCF9    LD      A,(IX-1)
        XOR     80H
        LD      (IX-1),A
        POP     DE
        RET
ZD03    PUSH    DE
ZD04    LD      H,D
        LD      L,E
        EXX
        LD      L,E
        LD      H,D
        LD      C,B
        EXX
        DEFB    1       ; DUMMY LD BC,
ZD0D    LD      L,80H
ZD0F    LD      (IX-6),H
        LD      (IX-7),L
        EXX
        LD      (IX-10),L
        LD      (IX-9),H
        LD      (IX-8),C
        EXX
ZD20    JP      DEIXBC
ZD27    LD      A,H
        XOR     D
        LD      H,A
        DEC     E
        PUSH    HL
        PUSH    BC
        LD      B,18H
        CALL    ZE39
        XOR     A
        RST     HL0
        LD      C,A
ZD3D    EXX
        SRL     C
        RR      H
        RR      L
        EXX
        JR      NC,ZD4B
        ADD     HL,DE
        LD      A,C
        ADC     A,B
        LD      C,A
ZD4B    EXX
        DJNZ    ZD53
        POP     BC
        POP     HL
        EXX
        JR      ZD83
ZD53    EXX
        RR      C
        RR      H
        RR      L
        JR      ZD3D
ZD5C    LD      A,E
        NEG
        LD      E,A
        LD      A,H
        XOR     D
        LD      H,A
        PUSH    HL
        PUSH    BC
        LD      B,19H
        EXX
ZD68    SBC     HL,DE
        LD      A,C
        SBC     A,B
        LD      C,A
        JR      NC,ZD72
        ADD     HL,DE
        ADC     A,B
        LD      C,A
ZD72    EXX
        CCF
        ADC     HL,HL
        RL      C
        DJNZ    ZD85
        PUSH    HL
        PUSH    BC
        EXX
        POP     BC
        POP     HL
        EXX
        POP     BC
        POP     HL
        EXX
ZD83    JR      ZDE9
ZD85    EXX
        ADD     HL,HL
        RL      C
        JR      NC,ZD68
        CCF
        SBC     HL,DE
        LD      A,C
        SBC     A,B
        LD      C,A
        OR      A
        JR      ZD72
ZD94    JR      Z,ZDA0
        CP      E
        JR      Z,ZDA8
        LD      A,H
        XOR     D
        CALL    Z,ZDB3
        JR      ZDA7
ZDA0    CP      E
        RET     Z
        SCF
        BIT     7,D
        JR      ZDAA
ZDA7    RET     Z
ZDA8    BIT     7,H
ZDAA    CCF
        RET     NZ
        CCF
        RRA
        SCF
        RL      A
        RET
ZDB3    LD      A,L
        SUB     E
        JR      Z,ZDBE
        JP      PO,ZDBC
        NEG
ZDBC    RLCA
        RET
ZDBE    EXX
        LD      A,C
        CP      B
        JR      NZ,ZDC9
        RST     Z32
ZDC9    EXX
        RET
ZDCB    LD      A,L
        SUB     E
        JR      Z,ZDDD
        CP      18H
        RET     NC
        EXX
ZDD3    SRL     B
        RR      D
        RR      E
        DEC     A
        JR      NZ,ZDD3
        EXX
ZDDD    LD      E,0
        LD      A,H
        XOR     D
        JP      M,ZDFA
        EXX
        ADD     HL,DE
        LD      A,C
        ADC     A,B
        LD      C,A
ZDE9    JR      NC,ZDF2
        RR      C
        RR      H
        RR      L
        SCF
ZDF2    EXX
ZDF3    LD      A,L
        ADC     A,E
ZDF5    JP      PE,ZE15
        LD      L,A
        RET
ZDFA    EXX
        SBC     HL,DE
        LD      A,C
        SBC     A,B
        LD      C,A
ZE00    LD      B,18H
        XOR     A
        INC     C
        DEC     C
ZE05    JP      M,ZE11
        DEC     A
        ADD     HL,HL
        RL      C
        DJNZ    ZE05
ZE0E    LD      L,80H
        RET
ZE11    EXX
        ADD     A,L
        JR      ZDF5
ZE15    LD      A,H
        OR      A
        JP      P,Z745
        JR      ZE0E
ZE1E    POP     HL
        PUSH    DE
        PUSH    HL
        LD      D,(IX-1)
        LD      E,(IX-2)
        LD      H,(IX-6)
        LD      L,(IX-7)
        EXX
        LD      E,(IX-5)
        LD      D,(IX-4)
        LD      B,(IX-3)
ZE39    LD      L,(IX-10)
        LD      H,(IX-9)
        LD      C,(IX-8)
        EXX
        LD      A,80H
        CP      L
        RET
ZE47    PUSH    DE		; RND
        EXX
        LD      HL,2aA7H-0
        PUSH    HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        LD      B,(HL)
        EXX
        CALL    Z155
        RST     HL0
        LD      C,3
ZE77    LD      B,8
        LD      D,(HL)
ZE7A    EXX
        ADD     HL,HL
        RL      C
        EXX
        RL      D
        JR      NC,ZE89
        EXX
        ADD     HL,DE
        LD      A,C
        ADC     A,B
        LD      C,A
        EXX
ZE89    DJNZ    ZE7A
        INC     HL
        DEC     C
        JR      NZ,ZE77
        RST     HL0
        EXX
        POP     DE
        LD      A,L
        ADD     A,65H
        LD      (DE),A
        INC     DE
        LD      L,A
        LD      A,H
        ADC     A,0B0H
        LD      (DE),A
        INC     DE
        LD      H,A
        LD      A,C     ;
        ADC     A,5
        LD      (DE),A
        LD      C,A
        CALL    ZE10IX
        JP      ZD0F
;_____________________________________

BEC4                    ; CONVERT STRING TO INTEGER
        RST     HL0
        CALL    Z40  ; skip blanks, pointer de
        CALL    Z8C  ; NC = numeric
        JR      C,ALPHA
        DEC     DE
        CALL    ZA6       ; CONVERT STRING TO FLOATING POINT
        CALL    ZC0B      ; FLOATING POINT TO INTEGER
ALPHA   LD      A,H
        OR      L
        RET

GO1     CP      H
        JR      NZ,NOTH
        LD      H,0		; if A=H then H=0
NOTH    CP      L
        JR      NZ,NOTL
        LD      L,0		; if A=L then L=0
NOTL    DEC     E
        JR      NZ,TAST3
        JR      TAST2		; if E=0 skeniraj od pocetka

TASTAT  EXX            	 ; TASTATURA
        LD      HL,(2AA5H)
        LD      C,14  	  ; BRZINA AUTOREPEAT
TAST2   LD      DE,2034H	; 2034 = LIST (poslednji u matrici)
TAST3   LD      A,(DE)	; uzmi stanje tastera (DE)
        RRCA
        LD      A,E		; da broj tastera bude u A
        JR      C,GO1
        CP      32H		; RPT?
        JR      NZ,NORPT	; nije
        DEC     C		; RPT jeste, cekaj istek
        JR      NZ,GO1
        LD      A,(stack+12) 	; uzmi zadnji pritisnut
        JR      IZLAZ
NORPT   CP      H
        JR      Z,NOTL
        CP      L
        JR      Z,NOTL
        LD      B,0
X200    RST     Z32		; DE=HL?
        LD      A,(DE)
        RRCA
        JR      C,GO1
        DJNZ    X200		; debouncer loop
        LD      A,H
        OR      A
        JR      NZ,ZAUZET
        LD      H,E
        JR      UPISAN
ZAUZET  LD      A,L
        OR      A
        JR      NZ,TAST3
        LD      L,E
UPISAN  LD      (2AA5H),HL	; upisi upravo pritisnut
        RST     HL0
        LD      A,E
        CP      34H		; LIST ?
        JP      Z,LIST2
        CP      31H		; ESC ?
        JP      Z,STOP3
CONT_FROM_SH_ESC
        CP      1BH		; 1B=prvi znak, ispod su slova
        LD      HL,2035H        ; SHIFT
        JR      C,IZLAZ2	; ako su slova (ne znaci i cifre)
        CP      1FH
        JR      C,IZLAZ	; ako su strelice
				; ovde su samo cifre i znaci
        SUB     1FH
        RR      (HL)      ; (HL) = SHIFT
        RLA			; x2 (+1 if SHIFT pressed)
        LD      C,A
        LD      HL,TABELA
        ADD     HL,BC
        LD      A,R
        LD      (2AA8H),A		; 2AA8H = random seed
        LD      A,(HL)
IZLAZ
  ;;;   LD      (stack+12),A	; upisi upravo pritisnut
        jp      ARROWS
bck_arr
        EXX
        RET

IZLAZ2  ADD     A,40H		; tu su slova (ne znaci i cifre)
        RR      (HL)
        JR      C,IZLAZ
        LD      HL,TAB3
        LD      BC,045BH ; 4BY TABLICA + STREL.LEVO
NFND    CP      (HL)
        JR      Z,FNDSL
        INC     HL
        INC     C
        DJNZ    NFND
        DEFB    0EH     ; DUMMY LD C,
FNDSL   LD      A,C
        JR      IZLAZ		; upisi upravo pritisnut

TABELA  DEFW    2020H   ; SPACE   201F
        DEFW    3029H   ; ) 0     2020
        DEFW    3121H   ; ! 1     2021
        DEFW    3222H   ; " 2     2022
        DEFW    3323H   ; # 3     2023
        DEFW    3424H   ; $ 4     2024
        DEFW    3525H   ; % 5     2025
        DEFW    36BFH   ; ' 6     2026
        DEFW    3726H   ; & 7     2027
        DEFW    382AH   ; * 8     2028
        DEFW    3928H   ; ( 9     2029
        DEFW    3B3AH   ; : ;     202A
        DEFW    2D5FH   ; _ -     202B
        DEFW    2C3CH   ; < ,     202C
        DEFW    3D2BH   ; + =     202D
        DEFW    2E3EH   ; > .     202E
        DEFW    2F3FH   ; ? /     202F
        DEFW    0D0DH   ; RET     2030

TAB3    DEFB    58H     ; C CASA
        DEFB    43H     ; C CURKA
        DEFB    5AH     ; Z ZIVOT
        DEFB    53H     ; S SKOLA

        DEFW    000CH   ; STOP DEL

Z821    CALL    X825
        LD      BC,(2A99H)
        SBC     HL,BC
        JR      FORC59

WORD2   LD      C,(HL)          ; READ 2 BYTES
        INC     HL
        LD      H,(HL)
        LD      L,C
        JR      FORC59

KEY     EQU     $       ; KEY
        LD      A,H
        OR      L
        JR      NZ,NOWAIT
        CALL    TASTAT
        JR      LA
NOWAIT  SET     5,H
        LD      A,(HL)
ARCPL   CPL
AREZ    AND     1
LA      LD      L,A
        DEFB    3EH
BYTE2a  LD      L,(HL)  ;       READ BYTE
ASK2    LD      H,0
FORC59  JP      ZC59


EQUS    CALL    Z694
        PUSH    HL
        RST     Z8
        DEFB    ','
        DEFB    0
        CALL    Z694
        POP     BC
POREDI  LD      A,(BC)
        CP      (HL)
        JR      NZ,NEQ
        OR      A
        JR      Z,ENDEQ
        INC     HL
        INC     BC
        LD      A,L
        AND     15
        JR      NZ,POREDI
ENDEQ   DEFB    3EH
NEQ     XOR     A
        JR      AREZ

HEX     CALL    HEXCIF
        JR      C,ZAHOW
        DEC     DE
        RST     HL0
GOCONV1 CALL    HEXCIF
        JR      C,FORC59
        RLCA
        RLCA
        RLCA
        RLCA
        LD      BC,GOCONV1
        PUSH    BC
HLX4    LD      B,4
HEX4    RLCA
        ADC     HL,HL
ZAHOW   JP      C,HOW
        DJNZ    HEX4
        RET

WORD1   DEFB    0F6H    ; (DUMMY OR) WRITE 2 BYTES
BYTE1a  XOR     A       ;       WRITE 1 BYTE
        PUSH    AF
        RST     Z807
        PUSH    HL
        CALL    ZAREZ
        EX      (SP),HL
        POP     BC
        LD      (HL),C
        POP     AF
        JR      Z,NOVINS
        INC     HL
        LD      (HL),B
NOVINS  RST     Z48

USR     EQU     $       ; USR
        PUSH    DE
        LD      DE,ZC5A
        PUSH    DE
        JP      (HL)

CHRS    EQU     $
        OR      D
        LD      A,L
        RET

FOR_ept				; FOR ept
	jp	for_link
 ;;;	CALL	   ZA9F
back_to_FOR
        CALL    Z8A8
        LD      (2AA1H),HL
        RST     Z8
        DEFB    'T'
        DEFB    WHAT2-$-1
        RST     Z8
        DEFB    'O'
        DEFB    WHAT2-$-1
        RST     Z807		; TO ept
        LD      (2A6EH),HL
        LD      L,lo(Z311)
        JP      Z343

; ------------------------------------
        org 0x0E30
SAVE_EPT                        ; SAVE     (original 0x0E30)
        jp      flash_save     ; *****************************

 ;;;        LD      HL,BASIC-4
        PUSH    HL         ; \    BASPTR
        LD      HL,(BASEND)
        RST     Z8              ; IF ((SP))=(DE) THEN (SP)=(SP)+2
                                ; ELSE (SP)=((SP)+1)+(SP)+2
        DEFB    0DH		; compare: if (DE)<>CR
        DEFB    2		; then skip 2 bytes
        JR      NODIM1
        RST     Z807		; read next num string to hl
        EX      (SP),HL		; BASPTR to HL, num string na (SP)
        CALL    ZAREZ           ; IF (DE)="," read to HL, else WHAT
        INC     HL	   ; ++
NODIM1  POP     DE	   ; /    num string + 1
        LD      B,60H
        DI
                               ;  DE = start address
                               ;  HL = end address
                        ; ------- tape write start
LEADER  XOR     A
        CALL    BYTE		; *** leadiong zeros
        DJNZ    LEADER          ;     loop sync byte (96 times)
        LD      A,0A5H          ; *** A5 header
        CALL    BYTE
        CALL    EXWORD          ; *** write DE (start address)
        CALL    EXWORD          ; *** write HL (end address)
        DEC     HL
REC     LD      A,(DE)
        INC     DE
        CALL    BYTE   	        ; *** PROGRAM write one byte
        JR      NC,REC	        ;     if not yet done
        LD      A,B
        CPL
        LD      E,A             ; *** E = cpl checksum
				; *** D dummy
EXWORD  EX      DE,HL           ; write one word LH (little endian)
;WORD
        LD      A,L
        CALL    BYTE            ; write one byte
        LD      A,H
BYTE                            ; write one byte
        EXX                     ; X
        LD      C,10H
        LD      HL,2038H        ; latch addr
GO16                            ; \\\\ byte write loop start
        BIT     0,C
        JR      Z,PULSE

        RRCA
        LD      B,100
        JR      NC,NOPUL
PULSE
        LD      (HL),0FCH       ; positive voltage to latch
        LD      B,50
        DJNZ    $
        LD      (HL),0B8H       ; negative voltage to latch
        LD      B,50
        DJNZ    $

        LD      (HL),0BCH       ; neutral voltage to latch
        INC     B
NOPUL
        DJNZ    $
        DJNZ    $
        DEC     C
        JR      NZ,GO16     ; //// byte write loop end
VVP
        INC     BC      ; 13312 T
        BIT     1,B
        JR      Z,VVP           ; a little silence
        EXX

ABHLDE  ADD     A,B
        LD      B,A
        RST     Z32     ; CP HL-DE Z & C FLAGS VALID (done or not)
        RET

;--------------------------------------
        org 0x0E97
OLD_EPT                 ; LOAD       (original 0x0E97)
        jp      old_both
;-------
 ;;;	RST     Z8
 ;;;	DEFB    '?'
 ;;;	DEFB    0
        PUSH    AF      ; IF VERIFY, Z SET
        RST     Z8
        DEFB    0DH
        DEFB    2
        RST     HL0
        DEFB    3EH
        RST     Z807
        PUSH    HL
        DI
GOA5    CALL    RXBYTE
        LD      A,C
        CP      0A5H
        JR      NZ,GOA5
        LD      B,A
        CALL    RX2
        LD      H,C
        POP     DE
        PUSH    DE
        ADD     HL,DE
        EX      DE,HL
        CALL    RX2
        LD      H,C
        DEC     HL
        LD      A,B
        POP     BC
        ADD     HL,BC
        LD      B,A
PUNI    EX      DE,HL
        CALL    RXBYTE
        EX      AF,AF'
        LD      A,C
        CP      (HL)
        JR      Z,EQUAL
        POP     AF
        JR      Z,WHAT2
        PUSH    AF
        LD      (HL),C
EQUAL   INC     HL
        EX      DE,HL
        EX      AF,AF'
        JR      C,PUNI
        CALL    RXBYTE
        POP     AF
        INC     B
        RET     Z
WHAT2   JP      WHAT    ; CHKSUM ERROR
RX2     CALL    RXBYTE
        LD      L,C
RXBYTE  EXX
        LD      B,1
RXBY    LD      A,167
SYNC2   ADD     A,B
        LD      HL,2000H
        BIT     0,(HL)
        JR      Z,FOUND
        DEC     A
        JR      NZ,SYNC2
        EXX
        LD      A,C
        JR      ABHLDE
FOUND   LD      B,0-38
VPPLUS  LD      A,256-87
        DJNZ    VPPLUS
        LD      B,90
RCV     LD      C,(HL)
        RR      C
        ADC     A,0
        DJNZ    RCV
        RLCA
        EXX
        RR      C
        EXX
        JR      RXBY

;--------------------------------------------------
        org 0x0F07
Z1AE			; READY message (original 0x0F07)
	DEFW    2740H	; logo
	DEFM    'READY'
	DEFB    0DH

;--------------------------------------------------
        ORG     0F0FH	; ENTIRE TABLE MUST BE ON PAGE 0x0Fnn!
INSTRUC EQU     $-1
        DEFM    'LIST'  ; ------------------ 
        DEFB    80h+hi(LIST)
        DEFB    lo(LIST)
        DEFM    'RUN'  ; ------------------ 
        DEFB    80h+hi(run_ept)
        DEFB    lo(run_ept)
        DEFM    'NEW'  ; ------------------ 
        DEFB    80h+hi(NEW)
        DEFB    lo(NEW)
        DEFM    'SAVE'  ; ------------------ SAVE
        DEFB    80h+hi(SAVE_EPT)
        DEFB    lo(SAVE_EPT)
        DEFM    'OLD'   ; ------------------ OLD
        DEFB    80h+hi(OLD_EPT)
        DEFB    lo(OLD_EPT)
        DEFM    'EDIT'  ; ------------------ 
        DEFB    80h+hi(EDIT)
Z26C    DEFB    lo(EDIT)		; following commands can exist in program
        DEFM    'NEXT'  ; ------------------ 
        DEFB    80h+hi(Z5A3)
        DEFB    lo(Z5A3)
        DEFM    'INPUT'  ; ------------------ 
        DEFB    80h+hi(Z623)
        DEFB    lo(Z623)
        DEFM    'IF'  ; ------------------ 
        DEFB    80h+hi(Z5FB)
        DEFB    lo(Z5FB)
        DEFM    'GOTO'  ; ------------------ 
        DEFB    80h+hi(Z3B5)
        DEFB    lo(Z3B5)
        DEFM    'CALL'  ; ------------------ 
        DEFB    80h+hi(Z4C4)
        DEFB    lo(Z4C4)
        DEFM    'UNDOT'  ; ------------------ 
        DEFB    80h+hi(Z838)
        DEFB    lo(Z838)
        DEFM    'RET'  ; ------------------ 
        DEFB    80h+hi(Z4E6)
        DEFB    lo(Z4E6)
        DEFM    'TAKE'  ; ------------------ 
        DEFB    80h+hi(TAKE)
        DEFB    lo(TAKE)
        DEFM    '!'  ; ------------------ 
        DEFB    80h+hi(Z5F6)
        DEFB    lo(Z5F6)
        DEFM    '#'  ; ------------------ 
        DEFB    80h+hi(Z5F6)
        DEFB    lo(Z5F6)
        DEFM    'FOR'  ; ------------------ 
        DEFB    80h+hi(FOR_ept)
        DEFB    lo(FOR_ept)
        DEFM    'PRINT'  ; ------------------ 
        DEFB    80h+hi(Z42F)
        DEFB    lo(Z42F)
        DEFM    'DOT'  ; ------------------ 
        DEFB    80h+hi(Z83C)
        DEFB    lo(Z83C)
        DEFM    'ELSE'  ; ------------------ 
        DEFB    80h+hi(Z5F6)
        DEFB    lo(Z5F6)
        DEFM    'BYTE'  ; ------------------ 
        DEFB    80h+hi(BYTE1a)
        DEFB    lo(BYTE1a)
        DEFM    'WORD'  ; ------------------ 
        DEFB    80h+hi(WORD1)
        DEFB    lo(WORD1)
        DEFM    'ARR$'  ; ------------------ 
        DEFB    80h+40H+hi(DIM)
        DEFB    lo(DIM)
        DEFM    'STOP'  ; ------------------ 
        DEFB    80h+hi(Z1C9)
        DEFB    lo(Z1C9)
        DEFM    'HOME'  ; ------------------ 
        DEFB    80h+hi(HOME)
        DEFB    lo(HOME)  ; ------------------ 
        DEFB    80h+hi(Z6B3)
Z2EE    DEFB    lo(Z6B3)
        DEFM    'RND'  ; ------------------ 
        DEFB    80h+hi(ZE47)
        DEFB    lo(ZE47)
        DEFM    'MEM'  ; ------------------ 
        DEFB    80h+hi(Z821)
        DEFB    lo(Z821)
        DEFM    'KEY'  ; ------------------ 
        DEFB    80h+40h+hi(KEY)
        DEFB    lo(KEY)
        DEFM    'BYTE'  ; ------------------ 
        DEFB    80h+40h+hi(BYTE2a)
        DEFB    lo(BYTE2a)
        DEFM    'WORD'  ; ------------------ 
        DEFB    80h+40h+hi(WORD2)
        DEFB    lo(WORD2)
        DEFM    'PTR'  ; ------------------ 
        DEFB    80h+hi(PTR)
        DEFB    lo(PTR)
        DEFM    'VAL'  ; ------------------ 
        DEFB    80h+40h+hi(VAL)
        DEFB    lo(VAL)
        DEFM    'EQ'  ; ------------------ 
        DEFB    80h+hi(EQUS)
        DEFB    lo(EQUS)
        DEFM    'INT'  ; ------------------ 
        DEFB    80h+40h+hi(ZC59)
        DEFB    lo(ZC59)
        DEFM    '&'  ; ------------------ 
        DEFB    80h+hi(HEX)
        DEFB    lo(HEX)
        DEFM    'USR'  ; ------------------ 
        DEFB    80h+40h+hi(USR)
        DEFB    lo(USR)
        DEFM    'DOT'  ; ------------------ 
        DEFB    80h+hi(Z840)
        DEFB    lo(Z840)
        DEFB    80h+hi(Z7F2)
Z311    DEFB    lo(Z7F2)
        DEFM    'STEP'  ; ------------------ 
        DEFB    80h+hi(Z560)
        DEFB    lo(Z560)
        DEFB    80h+hi(Z565)
Z319    DEFB    lo(Z565)
        DEFM    'AT'  ; ------------------ 
        DEFB    80h+hi(Z473)
        DEFB    lo(Z473)
        DEFM    'X$'  ; ------------------ 
        DEFB    80h+hi(Z459)
        DEFB    lo(Z459)
        DEFM    'Y$'  ; ------------------ 
        DEFB    80h+hi(Z45E)
        DEFB    lo(Z45E)
        DEFB    80h+hi(Z452)
        DEFB    lo(Z452)
ZACHR   DEFM    'CHR$'  ; ------------------ 
        DEFB    80h+40h+hi(CHRS)
        DEFB    lo(CHRS)
        DEFB    80h+hi(Z749)
        DEFB    lo(Z749)
XELSE   DEFM    'ELSE'  ; ------------------ 
        DEFB    80h+hi(OVERPL)
        DEFB    lo(OVERPL)
        DEFB    80h+hi(NOTE0D)
        DEFB    lo(NOTE0D)
        DEFB    0		; last byte in ROM A

; *****************************************************************
; *****************************************************************
        org     0x1000  ;      ************************************
;          R O M   B    ;      ************************************
; *****************************************************************
; *****************************************************************

#include        "galaxyb.asm"

; *****************************************************************
; *****************************************************************
        org     0xA000  ;      ************************************
;       M O N I T O R   ;      ************************************
; *****************************************************************
; *****************************************************************

#include        "monitor.inc"

; *****************************************************************
; *****************************************************************
;       P A T C H E S          ************************************
;    A N D   T A B L E S       ************************************
; *****************************************************************
; *****************************************************************

deltar equ 40
offs1  equ 1
r_tab
	defb	deltar+128
        defb               28h
	defb	                0x00-offs1+128
	defb	deltar
        defb               28h
	defb	                0x20-offs1
	defb	deltar
        defb               28h
	defb	                0x40-offs1
	defb	deltar+128
        defb               28h
	defb	                0x60-offs1

	defb	deltar+128
        defb               28h
	defb	                0x00-offs1
	defb	deltar
        defb               28h
	defb	                0x20-offs1+128
	defb	deltar
        defb               28h
	defb	                0x40-offs1+128
	defb	deltar+128
        defb               28h
	defb	                0x60-offs1+128

	defb	deltar+128
        defb               29h
	defb	                0x00-offs1+128
	defb	deltar
        defb               29h
	defb	                0x20-offs1
	defb	deltar
        defb               29h
	defb	                0x40-offs1
	defb	deltar+128
        defb               29h
	defb	                0x60-offs1

	defb	deltar+128
        defb               29h
	defb	                0x00-offs1
	defb	deltar
        defb               29h
	defb	                0x20-offs1+128
	defb	deltar
        defb               29h
	defb	                0x40-offs1+128
	defb	deltar+128
        defb               29h
	defb	                0x60-offs1+128

; ---------------------------------------------

rpt_and_ini_b			; initiallization of ROM B from ROM A
        LD      SP,stack+5
        LD      HL,0C900H+HOR    ; HOR POS and RET
        PUSH    HL             ;  1  VIDEO LINK
        DEC     SP             ;  1
        PUSH    HL             ;  1  HOR and LINK
        call    &1000
        jp      back1		; back to rom A

;---------------------------------------------

fix1        ; bug fix in EDIT (when deleting last+1 char)
        LD      E,L
        LD      D,H
        ld      a,(DE)
        jr      fix1rel      ; can't delete <CR>
delbyte INC     DE           ; \
        LD      A,(DE)
        DEC     DE
        LD      (DE),A
        INC     DE
fix1rel
        CP      0DH
        JR      NZ,delbyte   ; /
        JP      OPET

; ----------------------------------------------
STOP3             ; ESC just pressed, ignore if SHIFT-ESC
        ld      hl,0x2035               ; SHIFT addr
        bit     0,(hl)
        jp      nz,STOP                 ; not SHIFT-ESC, proceed ESC
        jp      TASTAT;CONT_FROM_SH_ESC        ; its SHIFT-ESC,  so ignore it

; -----------------------------------------------
hor_loop                ; free to use  A, C, DE, HL
        ld     a,6
first_loop
        dec     a
        jp      nz,first_loop

        LD      A,(stack)	; (stack) = horizontal screen offset
        bit     0,a
        jr      nz,hor1         ; 7/12     bit 0 set adds 1 T
        nop                     ; 4
hor1
        bit     1,a
        jr      z,hor2          ; 7/12     bit 1 adds 2 T
        or      0               ; 7
hor2
        bit     2,a
        jp      z,hor4          ; 10/10    bit 2 adds 4 T
        nop                     ; 4
hor4
        bit     3,a
        jp      z,hor8          ; 10/10    bit 3 adds 8 T 
        nop                     ; 4
        nop                     ; 4
hor8
        bit     4,a
        jp      z,hor16         ; 10/10    bit 4 adds 16 T 
        nop                     ; 4
        nop                     ; 4
        nop                     ; 4
        nop                     ; 4
hor16
        bit     5,a
        jp      z,hor32         ; 10/10    bit 5 adds 32 T 
        push    hl              ; 11
        pop     hl              ; 10
        or      0               ; 7
        nop                     ; 4
hor32
        jp      hor_loop_back

; -----------------------------------------------------
from_ini_mon
        LD   HL,START
	jp	Mon_print  ; print "MONITOR INITIALIZED"

; -----------------------------------------------------

ATN_CONT_THERE
TAYL8
        PUSH    BC
        PUSH    HL
        CALL    PLUSHL
        CALL    ISPOD2
        CALL    PUTA
        POP     HL
        INC     HL
        INC     HL
        INC     HL
        INC     HL
        POP     BC
        DJNZ    TAYL8
        LD      HL,C7
        CALL    PLUSHL
        CALL    ISPOD3
        CALL    PUTA
        POP     AF
        JR      C,XLTH1
        CALL    DUBLIX
        CALL    IXM10
        LD      HL,PIPOLA
        CALL    0A45H
        CALL    IX5
        CALL    MINUS
XLTH1   POP     AF
        JR      NC,XGTH0
        SET     7,(IX-1)
XGTH0   JP      MOVE02

save13by		; copied from ROM A
        LD      A,(BSTR+2)
        CP      ':'
        JP      NZ,NESAT
        LD      A,(stack+7)	; Ako je bit 7=1, sat radi
        RLCA
        JP      NC,NESAT
        LD      HL,BSTR+10
	jp	back13by

; -----------------------------------------------------
; ispravka da se dozvoli samo jedan parametar kod komande DUMP
dump_corr
	ld	a,(DE)
	cp	','		; ,
	jr	z,comma
	cp	0x0d		; CR
	jp	nz,WHAT		; no comma, no CR
	ld	HL,8192		; to je za 8192 * 8 = 65536 bajtova
	jr	hereFF
comma
	inc	DE	; point to 2nd param
	rst	Z807	; PRETVORI SLEDECI ASCII NIZ U INTEGER I SMESTI GA U HL
hereFF
        LD      C,L
	ld	B,H
	ld	A,B
        OR      C
        POP     HL	; /
        PUSH    DE	; \
        CALL    NZ,PMEM_A ; print mem hex BC rows, 8 by each
        POP     DE	; /
        RST     30H	; GO NEXT INSTRUCTION

;-------
PMEM_A			; print mem hex (BC = # of rows)
	push	BC	; \
	CALL    HEX16B		; print HL hex (&xxxx)
        LD      A,':'
        RST     20H		; print ":"
        LD      A,8
RED8_A			; <-----
	push	AF	; \\
	LD      A,' '
        RST     20H		; print " "
        LD      A,(HL)
        CALL    HEX8		; print A hex
        INC     HL
	pop	AF	; //
	dec	a
        jr	nz,RED8_A	; ----->
testkeys
	ld	a,(0x2031)	; BRK
	rrca
	jp	nc,Z1C9		; BREAK EPT
	ld	a,(0x2034)	; PAUSE
	rrca
	jr	nc,golist	; scroll loop if PAUSE pressed
	ld	a,(0x2030)	; ENTER
	rrca
	jr	c,testkeys	; loop if ENTER not pressed
golist
        LD      A,0DH
        RST     20H
	pop	bc	; /
        DEC     BC
	ld	a,b
	or	c
        JR      NZ,PMEM_A
        RET

; *****************************************************************
; *****************************************************************
;      M O N I T O R           ************************************
; *****************************************************************
; *****************************************************************

Mon_print			; print "MONITOR INITIALIZED"
        LD   (&2BAA),HL		; preneto
        LD      DE,mon_ini	; "MONITOR INITIALIZED"
        call	Z94F		; print it on screen
	ret

; *****************************************************************
; *****************************************************************
;       E E P R O M            ************************************
; *****************************************************************
; *****************************************************************

_WREN1  equ 0x06   ; Write enable 0000 0110
_WRDI   equ 0x04   ; Write disable 0000 0100
_RDSR   equ 0x05   ; Read status register 0000 0101
_WRSR   equ 0x01   ; Write status register 0000 0001
_READ   equ 0x03   ; Read from memory array 0000 0011
_WRITE  equ 0x02   ; Write to memory array 0000 0010

; *****************************************************************
; *****************************************************************
;       F O R M A T            ************************************
; *****************************************************************
; *****************************************************************
for_link			; link za popravku FOR (prepoznaje ekstenziju ...MAT)
	ld	(chs),de	; illegal use of var CHS
	ld	a,(de)
	cp	'M'
	jr	nz,false_alarm	; not FORMAT command
	inc	de
	ld	a,(de)
	cp	'A'
	jr	nz,false_alarm	; not FORMAT command
	inc	de
	ld	a,(de)
	cp	'T'
	jr	nz,false_alarm	; not FORMAT command
	inc	de
	call    Z40	; Z40 = skip blanks (ptr DE)
	ld	a,(de)
	cp	0dh
	jp	nz,ERR5		; if not followed by 0Dh, TOO MANY PARAMETERS
	jr	go2format

false_alarm
	ld	de,(chs)	; illegal use of var CHS
	call	ZA9F		; as it was deleted from original FOR_ept to make space
	jp	back_to_FOR

; -----------------------------
go2format
        CALL    IFNR		; if not start of line, then <CR>
        LD      DE,message_f_yn	; "DELETE ALL STORED DATA? (Y/N)?"
        CALL    Z94F		; print it on screen
	call	ny		; wait for N/ESC or Y key, go to STOP_RELEASE if N/ESC
 ; format unconditionally
	ld	a,0x0d
	ld	(BUF),a		; to avoid repeating of "FORMAT" command
	call	clrFB		; clear flash buffer
        di
        ld      bc,0		; start block for Save Mem
f512blocks
        call    write_block_fb	; write 512 bytes mem DE ---> flash BC
        inc     bc		; ++ block pointer
;;;;;;;;;;;;;;;;;;;;;;;;;
;	bit	2,b	; SVE
;	bit	1,b	; POLA FLASH-A
;	bit	0,b	; IMENA I PRVIH 240 BLOKOVA
;	bit	7,c	; IMENA I PRVIH 112 BLOKOVA
;	bit	6,c	; IMENA I PRVIH 48 BLOKOVA
;	bit	5,c	; IMENA I PRVIH 16 BLOKOVA
	bit	4,c	; SAMO IMENA
;;;;;;;;;;;;;;;;;;;;;;;;;
        jr      z,f512blocks	; loop until BC = 0x200
        ei
        CALL    IFNR		; if not start of line, then <CR>
        LD      DE,mes_f_complete ; 'FORMAT COMPLETE'
        CALL    Z94F		; print it on screen
        jp      STOP_RELEASE

; -----------------------------
ny			; wait for N/ESC or Y down, go to STOP_RELEASE if N/ESC, RET if Y
	ld	a,(0x2031)	; ESC key addr
	and	1
	jr	z,stop_rel2	; if ESC pressed
	ld	a,(0x2019)	; Y key addr
	and	1
	ld	a,'Y'
	jr	z,press_y	; Y pressed
	ld	a,(0x200E)	; N key addr
	and	1
	ld	a,'N'
	jr	nz,ny		; N not pressed
press_y
	ld	hl,(2A68H)      ; Pozicija kursora u memoriji
	dec	hl		; point to printed cursor
	ld	(hl),a		; print Y or N
	inc	hl
	ld	(hl),'_' 	; print '_'
	ld	b,a		; B <--- A
ENTESC_key			;			<--------------
	ld	a,(0x201D)	; BKSP key addr
	and	1
	jr	nz,no_bksp
	ld	hl,(2A68H)      ; Pozicija kursora u memoriji
	ld	(hl),' '
	dec	hl
	ld	(hl),'_'
	jr	ny
no_bksp
	ld	a,(0x2030)	; ENTER key addr
	and	1
	jr	z, ENT_press	; if ENTER pressed		(2: ent)
	ld	a,(0x2031)	; ESC key addr
	and	1
	jr	nz,ENTESC_key	; if ESC not pressed	------------->
	call	keys_up		; wait for all keys up		(3: esc)
	jr	stop_rel
stop_rel2
	ld	hl,(2A68H)      ; Pozicija kursora u memoriji
	dec	hl
	ld	(hl),' '
stop_rel
        jp      STOP
ENT_press
	ld	a,'Y'
	cp	b		; previous A ('Y' or 'N')
	ret	z		; if it was 'Y'
	jp	Z1C9		; if it was 'N' then go "READY"

; -----------------------------
clrFB			; clear flash buffer
	ld	e,0
	ld	hl,FlBuf	; flash buffer addr
go_clrFB2
	ld	(hl),0		; clr second 256 by
	inc	hl
	ld	(hl),0		; clr second 256 by
	inc	hl
	dec	e		; FlBuf takes two whole pages
	jr	nz,go_clrFB2
	ret

; *****************************************************************
; *****************************************************************
;       A R R O W S            ************************************
; *****************************************************************
; *****************************************************************

ARROWS
        LD	(stack+12),A	; store last key (preneto)
	ld	a,(0x2035)	; SHIFT
	and	1
	jp	nz,no_arr	; if not shift
	ld	a,(0x2031)	; ESC
	and	1
	jp	nz,no_arr	; if not SHIFT+ESC

	ld	a,(stack+12)	; reload last key
	cp	'M'		; key M
	jr	z,MI_ept
	cp	'I'		; key I
	jr	z,MI_ept

; SHIFT+ESC+arrows
        cp	0x1B
        jp      z,ARROW_UP      ; save mem
        cp	0x1C
        jp      z,ARROW_DOWN    ; restore mem
        cp	0x1D
        jp      z,ARROW_LEFT    ; save screen (ALSO Y)
        cp	'Y'
        jp      z,ARROW_LEFT    ; save screen (ALSO Y)
        cp	0x1E
        jp      z,ARROW_RIGHT   ; restore screen
no_arr
	ld	a,(stack+12)	; reload last key
        jp	bck_arr		; if not SHIFT+ESC+SPEC

; -------------------------------
MI_ept			; M,I ----------------------------- KEY COMMAND M or I
        call    inimon		; initialize MONITOR
STOP_RELEASE            ; wait for all keys released, then STOP
	call	keys_up		; wait for all keys up
	jp      cr66 	; Z1C9


cr66
	ld	a,0x0D
	ld	(BUF),a
	jp	0x0066

; ----------------------------------------------------------
keys_up			; ; wait for all keys released
        ld      c,8
go_test_424
	ld	a,0x36		; last key + 1
	ld      hl,0x2001       ; key A
go_test_53
	bit     0,(hl)
	jr      z,keys_up	; startover, some key is pressed
	inc	l
	cp	l
	jr	nz,go_test_53	; inner loop
 	dec	c
	jr	nz,go_test_424
	ret

; *********************************************************
ARROW_UP                ; save mem
	ld	de,txt_memory1
	jp	flash_save
; ---------------------------------------------------------
ARROW_LEFT              ; save screen
	ld	de,txt_screen1
	jp	flash_save
; ---------------------------------------------------------
ARROW_DOWN              ; restore mem
	ld	de,txt_memory2
	jp	old_both
; ---------------------------------------------------------
ARROW_RIGHT             ; restore screen
	ld	de,txt_screen2
	jp	old_both
; *********************************************************
wr_sub
        call    wait_end        ; trashes HL
        call    wren
        ld      a,_WRITE        ; instruction
        call    write_a         ; trashes HL

        xor     a               ;      clr Carry
        rl      c               ;      cx2
        rl      b               ;      bcx2
        ld      a,b             ;      adr hi
        call    write_a         ; 420
        ld      a,c             ;      adr m
        call    write_a         ; 420
        xor     a               ;      adr lo = 0
        call    write_a         ; 420
	ret
; ---------------------------
spec_n_wr_block   ; wr directly 510 (DE) by + next block addr
	call	wr_sub
	ld	de,(from)
	ld      bc,510          ; 10   block format
	jr	wr_loop_1

; ---------------------------
spec_1_wr_block   ; wr direct from + to + 506 (DE) by + next block addr
; ------
	call	wr_sub
	ld	de,(from)
	ld	a,e
	call	write_a
	ld	a,d
	call	write_a
	ld	a,(to)
	call	write_a
	ld	a,(to+1)
	call	write_a
	ld	bc,506
wr_loop_1
        ld      a,(de)          ; 7
        inc     de              ; 6
        call    write_a         ; 420
        dec     bc              ; 6
        ld      a,b             ; 4
        or      c               ; 4
        jr      nz,wr_loop_1    ; 12   loop 459 t × 512 = 235008 t

	call	is_it_end
	jr	nc,not_end
	xor	a		; if eof
	call	write_a
	xor	a		; if eof
	call	write_a
	jr	cont_spc1	; if eof
not_end
	push	de	; \
	call	find_0_in_FlBuf	; find free bit in FlBuf, update free_bits & next_block
	pop	de	; /
	ld	a,(next_block)	 ; next block lo
	call	write_a
	ld	a,(next_block+1) ; next block hi
	call	write_a
cont_spc1
        ld      hl,latadr
		     ; TSWCD---
        ld      (hl),0b10000000 ; 10   cs deselect, ck low, dt low
	ld	(from),de	; new (from)
is_it_end
	ld	hl,(to)
	or	a		; clr Carry
	sbc	hl,de		; (to)-(from), Z or C set if done
        ret                     ; 10


; ---------------------------
write_block_fb
	ld	de,FlBuf
write_block   ; wr 512 by mem DE ---> block BC  235077 t = 78 ms
        push    bc      ; \
        push    hl      ; \\
	call	wr_sub
        ld      bc,512          ; 10   block format
wr_loop
        ld      a,(de)          ; 7
        inc     de              ; 6
        call    write_a         ; 420
        dec     bc              ; 6
        ld      a,b             ; 4
        or      c               ; 4
        jr      nz,wr_loop      ; 12   loop 459 t × 512 = 235008 t
		     ; TSWCD---
        ld      (hl),0b10000000 ; 10   cs deselect, ck low, dt low
        pop     hl      ; //    ; 10
        pop     bc      ; /     ; 10
        ret                     ; 10

; ---------------------------
rd_sub
	call    wait_end
        ld      a,_READ         ; instruction
        call    write_a
        xor     a               ; clr Carry
        rl      c               ; cx2
        rl      b               ; bcx2
        ld      a,b             ; adr hi
        call    write_a
        ld      a,c             ; adr m
        call    write_a
        xor     a               ; adr lo = 0
        call    write_a
	ret

; ---------------------------
read_last_two	; rd last two bytes of block BC to reg BC     trashes BC,HL
	call    wait_end
        ld      a,_READ         ; instruction
        call    write_a
        xor     a               ; clr Carry
        rl      c               ; cx2
        rl      b               ; bcx2
        ld      a,b             ; adr hi
        call    write_a
        ld      a,c             ; adr m
	add	a,1		; jer ne pocinje od 0 nego od 510
        call    write_a
        ld	a,254		; adr lo = 254 (pocinje od 510)
        call    write_a

        call    read_a
        ld      c,a		; read lo byte
        call    read_a
        ld      b,a		; read hi byte
        ld      (hl),0b10000000 ; cs deselect, dt low
        ret

; ---------------------------
read_first_four	; rd first four bytes of block BC to (file_from), (file_to)
	call    wait_end
        ld      a,_READ         ; instruction
        call    write_a
        xor     a               ; clr Carry
        rl      c               ; cx2
        rl      b               ; bcx2
        ld      a,b             ; adr hi
        call    write_a
        ld      a,c             ; adr m
        call    write_a
        ld	a,0		; adr lo = 0 (pocinje od 0)
        call    write_a

        call    read_a
        ld      (file_from),a
        call    read_a
        ld      (file_from+1),a
        call    read_a
        ld      (file_to),a
        call    read_a
        ld      (file_to+1),a
        ld      (hl),0b10000000 ; cs deselect, dt low
        ret

; ---------------------------
spec_128_read_block    ; rd 128 by block BC ---> mem DE
        push    bc      ; \
        push    hl      ; \\
	call	rd_sub
        ld      bc,128
	jr	rd_loop

; ---------------------------
read_block_fb
	ld	de,FlBuf
read_block    ; rd 512 by block BC ---> mem DE  260000 t = 87 ms
        push    bc      ; \
        push    hl      ; \\
	call	rd_sub
        ld      bc,512          ; 10  block format
rd_loop
        call    read_a          ; 458
        ld      (de),a          ; 10
        inc     de              ; 6
        dec     bc              ; 6
        ld      a,b             ; 4
        or      c               ; 4
        jr      nz,rd_loop      ; 12    loop 507 t
        ld      (hl),0b10000000 ; 10    cs deselect, dt low
        pop     hl      ; //    ; 10
        pop     bc      ; /     ; 10
        ret                     ; 10

; ---------------------------
write_a            ; write a ----> flash (call 17t)  420t
        push    bc         ; \          11
        push    de         ; \\         11
        ld      bc,0b1110000011101000 ; 10
        ld      de,0b1111100011110000 ; 10
        ld      hl,latadr             ; 10

      rept 8            ;   TSWCD---
        ld      (hl),b  ; 0b11100000    7   cs selected, ck low, dt low
        rlca            ;               4
        jr      nc,$+7  ;               12/7  
        ld      (hl),c  ; 0b11101000    7   ck low, dt high if a,#7 high
        ld      (hl),d  ; 0b11111000    7   _/  ck high, dt high, write d7=1
        jp      $+4     ;               10
        ld      (hl),e  ; 0b11110000    7   _/  ck high, dt low, write d7=0
      endm              ;                   30/49 t
        ld      (hl),b  ; 0b11100000    7   ck low, dt low
        pop     de         ; //         10
        pop     bc         ; /          10
        ret                ;            10

; ----------------------------
read_a              ;  TSWCD---    read flash ----> a (call 17t)  439t
        push    bc         ; \   ; 11
        push    de         ; \\    11
        ld      de,0x203C        ; 10  row 4 addr of 74HCT251
        ld      hl,latadr        ; 10
        xor     a                ; 4
        ld      (hl),0b11100000  ; 10  ck low

      rept 8          ; --------
        ld      (hl),0b11110000  ; 10  _/ ck high
        ld      c,a              ; 4
        ld      a,(de)           ; 7
        rra                      ; 4
        ld      a,c              ; 4
        rla                      ; 4
        ld      (hl),0b11100000  ; 10  ck low
      endm            ; --------              43 t
        pop     de         ; //    10
        pop     bc         ; /     10
        ret                      ; 10

; -----------------------------------------------
wait_end        ; wait for WIP=0 (Write In Progress)
        ld      a,_RDSR
        call    write_a
go_wait
        call    read_a
        bit     0,a             ; WIP
        jr     nz,go_wait
        ld      (hl),0b10000000  ; cs deselected
        ld      (hl),0b11100000  ; cs selected, ck low, dt low
        ret                     ; CS is selected on exit
; ---------------------------
wren            ; write enable
                ;      TSWCD---
 push hl
        call    wait_end
        ld      a,_WREN1
        call    write_a
        ld      (hl),0b10000000  ; cs deselect, ck low, dt low
 pop hl
        ret                     ; CS is selected on exit
; ---------------------------
wrsr            ; write a to status register
        push    af              ; \
        call    wait_end
        call    wren
        ld      a,_WRSR
        call    write_a         ; wr cmd
        pop     af              ; /
        call    write_a         ; wr data
        ld      (hl),0b10000000  ; cs deselect, dt low
        ret
; ---------------------------
rdsr            ; read status register to a
                ;      TSWCD---
        ld      hl,latadr
        ld      (hl),0b11100000  ; cs selected, ck low, dt low
        ld      a,_RDSR
        call    write_a
        call    read_a
        ld      (hl),0b10000000  ; cs deselect, dt low
        ret

; ************************************************************************
; ************************************************************************
; *****    B A C K U P   /   R E S T O R E    ****************************
; ************************************************************************
; ************************************************************************

BACKUP
	call	get_blocks	; Blocks ----> FlBuf+8 (126 by) (contains DI)
				; at exit: HL = number of free blocks (0...1024)
	ld	B,H
	ld	C,L
	ld	HL,1024
	xor	A
	sbc	HL,BC		; HL = # of occupied blocks (including #0-#15)
	push	HL	  ; \	  HL = # of occupied blocks

	xor	a
	ld	(chs),a		; ini CHS
	ld	a,0xB7
	call	txbyte		; -------------> command byte B7
	ld	a,0xE2
	call	txbyte		; -------------> command byte E2

	ld	HL,FlBuf+8	; start of blocks (first 8 by are back porch)
	ld	DE,BUF-1
	ld	BC,126
	ldir			; Blocks ----> BUF-1 ... BUF+125
	pop	hl	  ; /	  HL = # of occupied blocks (including #0-#15)
	ld	A,L
	push	hl	  ; \	  HL = # of occupied blocks (including #0-#15)
	call	txbyte		; -------------> block count lo
	ld	A,H
	call	txbyte		; -------------> block count hi
 ; send first 16 blocks unconditionally
	ld	BC,0		; main block register  0 ... 1023
	ld	D,16
first_16
	call	send_block	; -------------> tx 514 by (C, B, then block 512 by)
	inc	BC	  ; ++
	dec	D
	jr	nz,first_16
 ; send all used blocks (16 - 1023)
	ld	HL,BUF-1	; Blocks pointer
	ld	D,126		; bytes in FLAG (1) and BUF (125)
FBloop
	ld	E,0x01		; bit pointer (Rotor Left)
FBloop2
	ld	A,(HL)
	and	E
	call	nz,send_block	; -------------> tx 514 by (block BC)
	inc	BC	  ; ++
	rlc	E	 ; <---   next bit in blocks
	jr	nc,FBloop2	; 8x (still in progress with E rotate)
	inc	HL	  ; ++
	dec	D
	jr	nz,FBloop	; 126x
 ; CHS
	ld	A,(chs)
	call	txbyte		; -------------> block count hi
	jp	0x0066		; done

; ------------------------------
send_block		; salje C, B, 512 by blok(BC)
	push	DE	  ; \
	push	HL	  ; \\
	ld	a,c
	push	BC	  ; \\\
	call	txbyte		; -------------> tx block address lo
	pop	BC	  ; ///
	ld	a,b
	push	BC	  ; \\\
	call	txbyte		; -------------> tx block address hi
	pop	BC	  ; ///
	call	read_block_fb	; read block BC to Flash Buffer
	ld	DE,FlBuf
	ld	HL,512
sbloop
	ld	A,(DE)
	push	BC	  ; \\\
	call	txbyte		; -------------> tx data byte
	pop	BC	  ; ///
	inc	DE
	dec	HL
	ld	A,H
	or	L
	jr	nz,sbloop	; 512 x

	pop	HL	  ; //
	pop	DE	  ; /
	ret

; ************************************************************************
blk_tot		equ BUF+120	; Blocks total
blk_cou		equ BUF+122	; Block count
; ************************************************************************
RESTORE
        LD      DE,message_f_yn	; "DELETE ALL STORED DATA? (Y/N)?"
        CALL    Z94F		; print it on screen
	call	ny		; wait for N/ESC or Y key, go to STOP_RELEASE if N/ESC
 ; restore unconditionally
	ld	a,0x0d
	ld	(BUF),a		; to avoid repeating of "RESTORE" command
	DI
	xor	a
	ld	(chs),a		; ini CHS adder
; ------- Galaksija sends to PC
	DI			; DI
	ld	a,0x65
        call    txbyte		; command byte 0x65  1 ---------->
	ld	a,0x97
        call    txbyte		; command byte 0x97  1 ---------->

 ;;; receive 1st raport -------------------------------------------------------

	call	rxbyte	 	;      <---------- 1
	cp	0xAA		; poruka greske?
	jp	nz,ERR11	; unrecognized reply from PC
	call	rxbyte	 	;      <---------- 1
	cp	0x39
	jp	nz,ERR11	; unrecognized reply from PC
 ; receive parser
	call	rxbyte   	;      <---------- 1
	cp	0xF0
	jr	z,cont_restore
	cp	0xF2
	jp	z,ERR13		; FILE NOT FOUND IN PC FOLDER
	cp	0xF5
	jp	z,ERR16		; BAD FILE FORMAT
	cp	0xF6
	jp	z,ERR3		; Error on serial line
	jp	ERR11		; UNRECOGNIZED REPLY FROM PC
cont_restore
; ------- PC sends to Galaksija
	xor	a
	ld	(chs),a		; ini CHS adder
	ld	BC,0
	ld	(blk_cou),BC	; block counter
	call	rxbyte		;       <---------- 1
	cp	0xCC		; CC
	jp	nz,WHAT		; nije stiglo CC
	call	rxbyte2		;       <---------- 1
	cp	0x36		; 36
	jp	nz,WHAT		; nije stiglo 36	
 ; synced CC 36, get # of blocks
	call	rxbyte2		;       <---------- 1
	ld	(blk_tot),a	; blocks total
	call	rxbyte2		;       <---------- 1
	ld	(blk_tot+1),a	; blocks total
go_blocks			; <====================================
	call	rxbyte		;       <---------- 1
	ld	C,A		; block addr lo
	call	rxbyte2		;       <---------- 1
	ld	B,A		; block addr hi
	push	BC	  ; \
	ld	DE,FlBuf
	ld	B,0
get512by			; <==================
	call	rxbyte2		;       <---------- 1 (256)
	ld	(DE),A
	inc	DE
	call	rxbyte2		;       <---------- 1 (256)
	ld	(DE),A
	inc	DE
	djnz	get512by	; ==================>

; push bc
; push de
; push hl
; ld	HL,(blk_cou)
; call	PrintHL
; pop hl
; pop	de
; pop bc

	pop	BC	  ; /
	call	write_block_fb	; Write Block # BC to EE

	ld	DE,(blk_cou)	; block counter
	inc	DE		; ++
	ld	(blk_cou),DE	; block counter
	ld	HL,(blk_tot)	; blocks total
	or	A
	sbc	HL,DE		; (blk_tot)-(blk_cou)
	jr	z,done_restore
	jr	nc,go_blocks	; ====================================>
done_restore
	ld	A,(chs)
	ld	E,A
	call	rxbyte		;       <---------- 1
	cp	E
	jp	nz,ERR4		; bad checksum
	jp	0x0066		; OK

; ************************************************************************
; ************************************************************************
; *****       D I R       ************************************************
; ************************************************************************
; ************************************************************************

hex_flag	equ BUF+105  ; 11295  0 = dec, >0 = hex
file_from	equ BUF+106  ; 11296  file (from)
file_count	equ BUF+108  ; 11298  countdown of filenames listed
listed		equ BUF+110  ; 11300  # of all listed filenames
string_start	equ BUF+112  ; 11302  match string start
string_end	equ BUF+114  ; 11304  match string end
name_count	equ BUF+118  ; 11306  name down count in inner loop 31 ---> 0
block_count	equ BUF+119  ; 11308  block down count in outer loop 15 ---> 1
file_to		equ BUF+120  ; 11310  file (to)
string_len	equ BUF+122  ; 11312  match string length

dir
	xor	a
	ld	(hex_flag),a	; default decimal
	ld	hl,0
	ld	(listed),hl	; # of all listed filenames
	ld	(string_len),hl	; def match string length = 0 (no match string)
	ld	a,16
	ld	(file_count),a	; countdown of filenames listed on one screen
	call    Z40		; Z40 = skip blanks (ptr DE)

	cp	'&'
	jr	nz,nothex
	ld	(hex_flag),a
	inc	de
	call    Z40		; Z40 = skip blanks (ptr DE)
nothex
	cp	0dh		; CR
	jr	z,no_matchstr
	ld	(string_start),de ; match string FROM
match_loop
	ld	a,(de)
	inc	de
	call	isitchar	; NC if reg A is valid char | num | "_" | "."
	jr	nc,match_loop

	dec de
	ld	(string_end),de	; match string string_end = addr of first non-char byte
	call    Z40		; Z40 = skip blanks (ptr DE)

	cp	'&'
	jr	nz,nothex2
	ld	(hex_flag),a
	inc	de
	call    Z40		; Z40 = skip blanks (ptr DE)
nothex2
	cp	0x0d		; <CR>
	jp	nz,ERR5		; pogresan bajt iza Match String-a (not 0x0d)
	ld	de,(string_start)
	ld	hl,(string_end)
	or	a		; clr Carry
	sbc	hl,de		; (string_end) - (string_start)
	ld	(string_len),hl	; match string length
no_matchstr
	ld	a,15
	ld	(block_count),a	; block_count = block down counter 15 ---> 1
	di
x15			; <==================== 1
	ld	a,(block_count)
	ld	c,a
	ld	b,0
	call	read_block_fb	; read block (block_count)

	ld	hl,FlBuf+512-16	; hl points to first name from top
	ld	a,31
	ld	(name_count),a	; name_count = name down counter 31 ---> 0
x32			; <==================== 2
	ld	a,l
	and	0xF0
	ld	l,a
	ld	a,(string_len)
	or	a		; test Z
	push	hl	; \
	call	nz,test_match	; filename (HL):(from-to) Z = match, NZ = no match
	pop	hl	; /
	push	hl	; \
	call	z,print_filename ; print filename pointed by (HL)
	pop	hl	; /
	ld	a,l
	and	0xF0
	ld	l,a
	dec	hl	; --
	ld	a,(name_count)
	dec	a
	ld	(name_count),a
	bit	7,a
	jr	z,x32	; ====================> 2

	ld	a,(block_count)
	dec	a
	ld	(block_count),a
	jr	nz,x15	; ====================> 1

; sledi broj fajlova, ukupno zauzetih i slobodnih blokova

	call	get_blocks	; HL = number of free blocks (0...1024) (~135 ms)
	jp	dir_message

; ----------------------------------------------
test_match	; test if match string (from...to) is contained in the filename (HL)
		; A=len(to-from), at exit: Z = match, NZ = no match
	cp	15
	jp	nc,ERR9		; if match string > 14
	ld	c,a		; c = match string length (1...14)
	ld	de,(string_start)
go_test_match
	call	cp_string	; test string (DE):(HL) length C
	ret	z		; Z = found
	inc	hl	; ++
	ld	a,l
	and	0x0F
	cp	14
	jr	nz,go_test_match ; if still in filename
	or	0xFF		; make it NZ
	ret

; -------------------------
cp_string		; test string (DE):(HL) length C
	ld	b,c
	push	de	; \
	push	hl	; \\
test_string_loop
	ld	a,(de)		; A <---- command line pointer (from)
	inc	de	; ++
	cp	(hl)		; (hl) points to char in filename
	inc	hl	; ++
	jr	nz,keep_cp_nz	; keep NZ and exit
	  ld	  a,l
	  and	  0x0F
	  cp	  0x0F
	  jr	  z,keep_cp_nz	; make it NZ and exit
	djnz	test_string_loop
	and	0		; make it z
	jr	$+4		; keep Z
keep_cp_nz
	or	0xFF		; make it NZ
	pop	hl	; //
	pop	de	; /
	ret			; Z if total match after C chars

; ----------------------------------------------
print_filename		; print filename pointed by (HL)
	ld	a,(hl)
	or	a
	ret	z		; no file here
;;; file count
	push	hl	; \
	ld	hl,(listed)	; # of all listed filenames
	ld	a,h
	or	l
	ld	a,0x0C		; CLS
	call	z,Z16		; PRINT CHAR IN A (CLS) ON SCREEN
	inc	hl
	push	hl	; \\
	ld	de,-100
	add	hl,de
	ld	a,' '
	call	nc,Z16		; if # < 100 then PRINT ' '
	pop	hl	; //
	push	hl	; \\
	ld	de,-10
	add	hl,de
	ld	a,' '
	call	nc,Z16		; if # < 10 then PRINT ' '
	pop	hl	; //
	call	PrintHL		; PRINT file number
	ld	a,' '
	rst	Z16		; PRINT ' '
	pop	hl	; /
;;; file name
	ld	b,14		; max chars in name
xx14
	ld	a,(hl)
	inc	hl
	or	a
	push	af	; \
	call	nz,Z16		; PRINT A if it is >0
	pop	af	; /
	ld	a,' '
	call	z,Z16		; PRINT ' ' if it was 0x00
	djnz	xx14
;;; file start addr
	ld	c,(hl)
	inc	hl
	ld	a,(hl)
	and	3
	ld	b,a		; bc = pos of the 1st block (0x10...0x3FF)
	call	read_first_four	; rd first 4 by of block BC to (file_from),(file_to)
	ld	hl,(file_from)
	call	print_dechex	; PRINT (FROM)
	ld	bc,(file_from)
	ld	hl,(file_to)
	or	a		; clr Carry
	sbc	hl,bc
	call	print_dechex	; PRINT file size

;;; dir administration
	ld	hl,(listed)	; # of all listed filenames
	inc	hl
	ld	(listed),hl
	ld	a,(file_count)	; countdown of filenames listed on one screen
	dec	a
	push	af	; \
	ld	(file_count),a
	ld	a,0dh
	call	nz,Z16		; <CR> only if not 16 line printed
	pop	af	; /
	ret	nz		; return to <DIR> if not 16 line printed
	ei
	call	click_retpauesc	; wait for keystroke...
	di
	ld	a,0x0C
	rst	Z16		; <CLS> (HOME)
	ld	a,16
	ld	(file_count),a	; countdown of filenames listed in one screen
	ret

; -------------------------------
align_right
	push	bc	; \
	push	de	; \\
	push	hl	; \\\
	ld	de,-10000
	add	hl,de
	ld	a,' '
	call	nc,Z16		; if # < 10000 then PRINT ' '
	pop	hl	; ///
	push	hl	; \\\
	ld	de,-1000
	add	hl,de
	ld	a,' '
	call	nc,Z16		; if # < 1000 then PRINT ' '
	pop	hl	; ///
	push	hl	; \\\
	ld	de,-100
	add	hl,de
	ld	a,' '
	call	nc,Z16		; if # < 100 then PRINT ' '
	pop	hl	; ///
	push	hl	; \\\
	ld	de,-10
	add	hl,de
	ld	a,' '
	call	nc,Z16		; if # < 10 then PRINT ' '
	pop	hl	; ///
	pop	de	; //
	pop	bc	; /
	ret

; -------------------------------
print_dechex
	ld	a,(hex_flag)
	or	a
	jp	z,PrintHL_AR	; PRINT DECIMAL right-aligned
print_hex
	ld	a,' '		; ' '
	call	Z16		; PRINT ' '
	jp	HEX16B		; print &+HEX

; -------------------------------
PrintHL_AR
	call	align_right	; RIGHT ALIGN
	jp	PrintHL
; -------------------------------
click_retpauesc		; detect all release, then any pressed
	ld	a,(0x2031)	; ESC
	rra
	jp	nc,STOP2
	ld	a,(0x2030)	; ENTER
	rra
	ret	nc
	ld	a,(0x2034)	; PAUSE
	rra
	ret	nc
	jr	click_retpauesc

; -------------------------------

hex8
	push	af	; \
	srl	a
	srl	a
	srl	a
	srl	a
	call	hex4
	pop	af	; /
	and	0x0F
hex4
	cp	10
	jr	c,ispod10
	add	'A'-10
	ld	(de),a
	inc	de
	ret
ispod10
	or	0x30
	ld	(de),a
	inc	de
	ret

; ******************************************************************************
; ******************************************************************************
; ****************        E R A S E         ************************************
; ******************************************************************************
; ******************************************************************************

flash_erase		; ERASE EPT
        DI
	call	locate_filename
	jp	nz,ERR2		; if no such filename then NO SUCH FILE
	call	erase_pgm_mm
	jp	0x0066

;---------------------
erase_pgm_mm			; (memorized): high=block #, low=name #
	ld	bc,(memorized+1); C=block (1...15)
	ld	b,0		; BC = Block # (1...15)
	call	read_block_fb	; **** NAME rd block with names
	ld	hl,(memorized)	; L= of pos inside block (0...31), H=block (1...15)
	ld	h,0
	add	hl,hl		; hl = block * 2
	add	hl,hl		; hl = block * 4
	add	hl,hl		; hl = block * 8
	add	hl,hl		; hl = block * 16 (in 0-1F range)
	ld	de,FlBuf
	add	hl,de		; hl <--- FlBuf+16*L  (point to first char of fn)
	ld	b,14
erase14
	ld	(hl),0		; all chars in name = chr$(0) : ERASED!
	inc	hl
	djnz	erase14

	ld	c,(hl)		; HL point to # of 1st block (after name)
	ld	(hl),0		; erase it too
	inc	hl
	ld	a,(hl)
	ld	(hl),0		; erase it too
	and	3		; 10-bit range
	ld	b,a		; bc = block #
	push	bc	; \
 ; write back block 1...15
	ld	bc,(memorized+1); C = block # (1...15)
	ld	b,0		; BC = Block # (1...15)
	call	write_block_fb	; @@@@ NAME write back block with name
 ; read block 0 with occupancy bits
	ld	bc,0
	call	read_block_fb	; **** BITS read block 0 with occupancy bits
	pop	bc	; /
go_clear			; <-------------------------------
	push	bc	; \	; bc = block #
	call	clear_block_bit	; clear block bit BC in FlBuf
	pop	bc	; /
	call	read_last_two	; rd last two bytes of block BC to reg BC
	ld	a,b
	or	c
	jr	nz,go_clear	; ------------------------------->
 ; write back block 0
	ld	bc,0
	call	write_block_fb	; @@@@ BITS wr modif block 0 back to flash mem
	ret

; -------------------------------
clear_block_bit		; clear block bit BC in FlBuf (0x0010...0x03FF)
	ld	d,0
    rept 3          ; --------	; /8
	srl	b
	rr	c		; BC = pozicija bajta u matrici blokova (0x10-0x3FF)
	rr	d		; d = broj bita u bajtu <5 (0x20...0xE0 step 8)
    endm	    ; --------
	ld	hl,FlBuf-2	; -2 jer treba da krene od bloka -0x10
	add	hl,bc		; addr of block bit to be erased
	ld	a,d		; a = 0x20...0xE0 (XXX00000)
	rlca
	rlca
	rlca			; a = 0..7 (broj bita koji treba resetovati)
; reset bit 0...7 in (HL) if a=0...7
	or	a
	jr	nz,$+4
	res	0,(HL)
	dec	a
	jr	nz,$+4
	res	1,(hl)
	dec	a
	jr	nz,$+4
	res	2,(hl)
	dec	a
	jr	nz,$+4
	res	3,(hl)
	dec	a
	jr	nz,$+4
	res	4,(hl)
	dec	a
	jr	nz,$+4
	res	5,(hl)
	dec	a
	jr	nz,$+4
	res	6,(hl)
	dec	a
	jr	nz,$+4
	res	7,(hl)
	ret

; -----------------------------
setbit			; set bit 0...7 in (DE) if a=0...7
	ex	de,hl	   ; X
	or	a
	jr	nz,$+4		; 0
	set	0,(HL)
	dec	a
	jr	nz,$+4		; 1
	set	1,(HL)
	dec	a
	jr	nz,$+4		; 2
	set	2,(HL)
	dec	a
	jr	nz,$+4		; 3
	set	3,(HL)
	dec	a
	jr	nz,$+4		; 4
	set	4,(HL)
	dec	a
	jr	nz,$+4		; 5
	set	5,(HL)
	dec	a
	jr	nz,$+4		; 6
	set	6,(HL)
	dec	a
	jr	nz,$+4		; 7
	set	7,(HL)
	ex	de,hl	   ; X
	ret

; ------------------------------------------
locate_filename   ; find filename (DE), Z:found, H=block#, L=name#, BC=len of pgm, DE=after fn
		  ; NZ:not found, H=block#, L=free name#, DE = start of filename in mem
	call	skip_quote	; skip blanks and quote, if any
	ld	(start_of_fn),de ; = start of filename
	call	count_chars	; count (de) valid chars (out: a = filename length)
	ld	(fn_len),a	; filename length
	dec	a
	cp	14
	jp	nc,ERR9		; if filename lenght <1 or >14 chars = irregular name length
 ; start testing up to 15 blocks, (BUF+0) = filename ptr, H = filename length
	ld	bc,1		; start with block 1 (ignore block 0)
	ld	(current),bc	; bc = current block #
go_find_bl		  ; find block with exact name	<================= 1
        call    read_block_fb	; rd 512 by block BC ---> Flash Buffer
	ld	hl,FlBuf	; flash buf start addr (L #87654 = filename count)
go_find_name		; find name  0...31	<============ 2
 ; start compare names inside 1 block
	ld	a,(fn_len)	; filename length
	ld	b,a		; B = filename len
	ld	de,(start_of_fn) ; DE points to start of filename in memory

	ld	a,(hl)		; --1st-- char in the name (should be 0 if not used)
	call	isitchar
	jr	nc,no_memo	; it is a valid char, do not memorize	----->
	call	memorize	; this position is unused, memorize it
	jr	fail1		; free space, no file here	-------------->
no_memo

go_test_char		  ; cp chars loop start 1...(B)	<======== 3
	ld	a,(de)
	inc	de
	cp	(hl)
	inc	hl
	jr	nz,fail1	; no match		-------------->
	djnz	go_test_char	; cp chars loop end	========> 3
; check if next (hl)=0 or L (bits 3210) = 14, otherwise names do not match
	xor	a
	cp	(hl)
	jr	z,fn_match	; all bytes equal after B chars  ==========> FOUND
	ld	a,L
	and	0x0F
	cp	14
	jr	z,fn_match	; all bytes equal after B chars  ==========> FOUND
; continues to fail1...
; -------------------------------
fail1
	ld	a,l
	or	0x0F
	ld	l,a
	inc	hl		; HL points to the next name
	ld	a,hi(FlBuf+512)	; end of FlBuf+1
	cp	h
	jp	nz,go_find_name	; name loop end		============> 2
; end of buffer, match not found
	ld	bc,(current)	; bc = current block #
	inc	bc		; next
	ld	(current),bc	; bc = current block #
	bit	4,c
	jp	z,go_find_bl	; find block end	=================> 1
; name not found in 15 blocks, use (memorized)
	ld	hl,(memorized)	; H=block # with free name, L=free name #
	ld	de,(start_of_fn) ; DE = start of filename in mem
 ; calculate de after filename and quote (if any)
	ld	a,(fn_len)	; filename length (1...14)
	ld	l,a
	ld	h,0
	add	hl,de
	ex	de,hl		; de = after filename
	call	skip_quote	; *** skip quote, if any (DE points to AFTER filename)
	ld	bc,0		; length of program = 0
	ld	hl,(memorized)
	xor	a
	ld	(fn_len+1),a	; zero bytes used in Flash
	or	0xFF		; NZ:not found, H=block#, L=free name#
	ret

; ------------------------------
fn_match	; filename match found! Get pgm length         <=========== FOUND
	call	memorize
	ld	a,L		; lo = pos # inside block (0-31)(found or not)
	and	0xF0
	add	a,14
	ld	L,a		; point to 1st block #
	ld	c,(hl)
	inc	L
	ld	a,(hl)
	and	3
	ld	b,a		; bc = 1st block # (0x0010...0x03FF)

	ld	a,(HL)
	srl	a
	srl	a
	ld	(fn_len+1),a	; # of blocks used in Flash

	call	read_block_fb	; *** DATA read 1st DATA block
	ld	hl,FlBuf
	ld	c,(hl)
	inc	hl
	ld	b,(hl)		; bc = from
	inc	hl
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a		; hl = to
	or	a		; Clear Carry
	sbc	hl,bc		; HL = file len in by (from flash storage)
	ld	b,h
	ld	c,l		; BC = file len in by (from flash storage)
	ld	de,(start_of_fn) ; DE points to start of filename in memory
 ; calculate de after filename and quote (if any)
				; skip fn loop start	<======== 3
	ld	a,(fn_len)	; A = filename length (1...14)
	ld	l,a
	ld	h,0		; HL = filename length (1...14)
	add	hl,de
	ex	de,hl		; de = after filename
	call	skip_quote	; *** skip quote, if any (DE points to AFTER filename)
	ld	hl,(memorized)	; H=block (1-15), L=pos inside block (0-31)
	xor	a		; set Z flag
	ret

; ----------------------------------------------------------------
cp_de_hl		; compare (de):(hl) filename, length B
	ld	a,(de)
	inc	de
	cp	(hl)
	inc	hl
	ret	nz	; NZ
	djnz	cp_de_hl
	and	0	; Z
	ret
; ------------------------------
skip_quote		; skip blanks and if quote, skip it (ptr DE)
	call    Z40	; Z40 = skip blanks (ptr DE)
	cp	34		; 34 = '"'
	ret	nz
	inc	de
	call    Z40	; Z40 = skip blanks (ptr DE)
	ret
; ------------------------------
count_chars		  ; count (de) valid chars (filename length)
	ld	h,0xFF		; H = char counter
go_count
	ld	a,(de)
	inc	de
	inc	h
	call	isitchar	; NC if char|num|"_"|"."
	jr	nc,go_count	; char count loop end		----->
	ld	a,h		; filename length
	ret			; A = filename length
; ------------------------------
memorize	; this pos is free, memorize HL to (memorized), maybe good for SAVE
	push	hl	; \	; 
	ld	a,(current)	; block under test
	ld	(memorized+1),a	; hi byte = block # (1-15)
	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	a,h
	and	0x1F
	ld	(memorized),a	; low byte = pos inside block (0-31)
	pop	hl	; /
	ret

; ------------------------------
; ------------------------------------------------------
isitchar	; NC if reg A is valid char | num | "_" | "."
	cp	95+1	; 95 = '_'
	ccf
	ret	c	; if >95
	cp	46	; 46 = '.'
	ret	z	; also NC
	cp	'A'	; 65 = 'A'
	ret	nc	; NC if >=A
	cp	'9'+1
	ccf
	ret	c	; if >'9'
	cp	'0'
	ret		; C set if <'0'

; ************************************************************************
; ************************************************************************
; *****     B L O C K S      *********************************************
; ************************************************************************
; ************************************************************************

blocks		    ; sets pixels for used blocks graphically (64*16 matrix)
	call	get_blocks	; HL = number of free blocks (0...1024) (~135 ms)
	ei
	push	hl	; \	  hl = # of free blocks in flash (0...1024)
	ld	ix,FlBuf	; bits ready for testing (bit 0 first)
	ld	e,6		; rows
lev2			; <----------------
	ld	b,32		; 32 chars/row
lev1			; <----------------
	xor	a
	rrc	(ix+0)
	rra
	rrc	(ix+0)
	rra
	rrc	(ix+8)
	rra
	rrc	(ix+8)
	rra
	rrc	(ix+16)
	rra
	rrc	(ix+16)
	rra
	rra
	scf
	rra
	push	bc	; \\
	push	de	; \\\
	rst	Z16             ; PRINT GRAPHICAL CHAR IN A ON SCREEN
	pop	de	; ///
	pop	bc	; //

	bit	0,b
	jr	z,noinc
	bit	1,b
	jr	nz,noinc
	inc	ix	; ++
noinc
	djnz	lev1	; ---------------->
	ld	bc,16
	add	ix,bc
	dec	e
	jr	nz,lev2	; ---------------->
	pop	hl	; /	  hl = # of free blocks in flash (0...1024)
dir_message
	ei
	push	hl	; \
	ld	de,message_total
        CALL    Z94F		; print 'TOTAL' on screen
	ld	de,1008
	ex	de,hl
	xor	a		; clear carry
	sbc	hl,de		; 1008 - free
	call	PrintHL		; PRINT DECIMAL INTEGER HL (blocks used)
	ld	de,message_bu
        CALL    Z94F		; print 'BLOCKS USED' on screen

	pop	hl	; /	  hl = # of free blocks in flash (0...1024)
	call	PrintHL		; PRINT DECIMAL INTEGER HL
	ld	de,message_bf
        CALL    Z94F		; print 'FREE' on screen

	jp	0x0066

; ------------------------------------------------------
get_blocks	    ; at exit: HL = number of free blocks (0...1024) (~135 ms)
	ld	bc,0		; block 0
	ld      de,FlBuf	; buf start addr
	call	clr8		; front porch
	di
	call    spec_128_read_block	; rd 128 by block 0 ---> FlBuf (87 ms)
					; hl = # of free blocks in flash (0...1024)
	call	clr8		; back porch
	ld	b,126		; blocks to count
	ld	de,FlBuf+8	; buf start addr with blocks
	ld	hl,0		; free block counter
go_count_blocks			; <------------ 139 t * 1024 = 142336 t ~48 ms
	ld	a,(de)
	inc	de
      rept 8          ; --- 8
	rrca			; bit 0 first
	jr	c,$+3		; if block used
	inc	hl		; if block not used
      endm            ; --- 8	  8 * 12.5 = 100 t
	djnz	go_count_blocks ; 139 t loop ------------>
	ret			; hl = # of free blocks in flash (0...1024)

; ------------------------------------------------------
clr8			; clear 8 bytes, ptr DE
	xor	a
	ld	b,8
go8
	ld	(de),a
	inc	de
	djnz	go8
	ret

; ------------------------------------------------------

bytes_to_blocks		; input HL bytes, output DE blocks (HL must be >0)
	ld	de,1		; counter = 1
	ld	bc,506		; first block len = 506
	or	a		; clr C
	sbc	hl,bc
	ld	bc,510		; all other blocks len = 510
	jr	into1		; -------->
go_measure			; <-------------
	inc	de
	or	a		; clr C
	sbc	hl,bc
into1				; <--------
	ret	z
	jr	nc,go_measure	; -------------> 36 T loop
	ret

; ------------------------------------------------------
blocks_to_bytes		; input DE blocks, output HL bytes
	ld	hl,0
	ld	bc,506
countblocks
	ld	a,d
	or	e
	ret	z
	add	hl,bc
	ld	bc,510
	dec	de
	jr	countblocks

; ************************************************************************
; ************************************************************************
; *****     M O V E      *************************************************
; ************************************************************************
; ************************************************************************

move_ept
 ; first name
	call	countname	; service quotes, (start_of_fn), (fn_len)
	ld	a,(fn_len)
	or	a
	jp	Z,ERR1		; must have filename
 ; find first name in EE
	ld	de,(start_of_fn)
        DI
	call	locate_filename
	jp	nz,ERR2		; No such file
	call	skip_quote
 ; comma detection
	cp	','
	jp	nz,WHAT
	inc	de
 ; second name	
	call	countname	; service quotes, (start_of_fn), (fn_len)
	ld	a,(fn_len)
	or	a
	jp	Z,ERR1		; must have filename

	ld	hl,(memorized)	; H=block # with name
	ld	c,h
	ld	b,0
        call    read_block_fb	; rd 512 by block BC ---> Flash Buffer
	ld	hl,(memorized)	; lo = # of pos inside block (0-31)
	ld	h,0
	add	hl,hl		; x2
	add	hl,hl		; x4
	add	hl,hl		; x8
	add	hl,hl		; x16
	ld	de,FlBuf
	add	hl,de		; HL = destinatio-n
	ex	de,hl		; DE = destination
	ld	hl,(start_of_fn)
	ld	bc,(fn_len)
	ld	b,0		; bc = filename length
	ldir			; copy FILENAME to flash buffer
 ; fill gap with zeros
	ex	de,hl		; hl = filename + 1
go_zeros_move
	ld	a,L
	and	0x0F
	cp	14
	jr	z,end_of_name_move
	ld	(hl),0
	inc	hl
	jr	go_zeros_move
end_of_name_move	; HL = name (in blocks 1-15) + 14 (1st block # + blocks count)
	ld	hl,(memorized)	; H=block # with name
	ld	c,h
	ld	b,0
        call    write_block_fb	; wr 512 by block BC ---> Flash Buffer
	jp	0x0066

; ************************************************************************

RescBuf	equ	BUF-1	; This is FLAG position, needed for 126-byte buffer
BlokReg	equ	0x2A9B	; Block Down Count Register (guest at NEXT variable addr)

; ************************************************************************
; ************************************************************************
; *****     R E S C A N      *********************************************
; ************************************************************************
; ************************************************************************

rescan_ept
	ld	HL,RescBuf
	ld	B,126
clr126
	ld	(HL),0
	inc	hl
	djnz	clr126		; RescBuf cleared
;-------
	ld	a,15
	ld	(BlokReg),a	; BlkReg = Block down count Register 15 ---> 1
	di
x15_rs			; <==================== 1
	ld	a,(BlokReg)
	ld	c,a
	ld	b,0
	call	read_block_fb	; read block 15...1 (BlkReg) with names

	ld	hl,FlBuf+512-16	; hl points to first (last) block name
x32_rs			; <==================== 2
	ld	a,(hl)		; 1st char in name
	call	isitchar
	jr	c,no_name_here	; if not a valid char

	ld	a,L
	add	a,14
	ld	L,a		; HL points to addr of 1st block with data

	ld	c,(hl)
	inc	hl
	ld	b,(hl)
	dec	hl

	ld	a,b
	and	3		; rule out file length (need only 10 bits)
	ld	b,a		; bc = addr of next block with data
	or	c
	jr	z,done_rescan3	; if next block addr = 0x0000 (EOF)
cont_next_block		; <==================== 3
	push	HL	  ; \
	call	set_BC_in_RescBuf
	call	read_last_two
	pop	HL	  ; /

	ld	a,b
	or	c
	jr	nz,cont_next_block   ; ==============> 3 if next block addr >0x0000
done_rescan3
	ld	a,L
	add	a,-14
	ld	L,a		; HL points to 1st char in name
no_name_here
	ld	a,L
	add	a,-16
	ld	L,a		; next name backwards
	jr	c,x32_rs	; ====================> 2  if not L underflow
	dec	h
	ld	a,h
	cp	hi(FlBuf)
	jr	z,x32_rs	; ====================> 2  if H = hi(FlBuf)

	ld	a,(BlokReg)
	dec	a
	ld	(BlokReg),a
	jr	nz,x15_rs	; ====================> 1 if BlockReg still >0
 ; done
 ; read block 0
	ld	bc,0
	call	read_block_fb	; @@@@ read to FlBuf

	ld	hl,RescBuf
	ld	de,FlBuf
	ld	BC,126
	ldir			; move 126 bytes from RescBuf to FlBuf
 ; write back block 0
	ld	bc,0
	call	write_block_fb	; @@@@ write to FlBuf
	jp	0x0066

; -----------------------
set_BC_in_RescBuf		; in: BC=block # (0x0010...0x03FF), trashes  A, DE
	push	HL	; \
	ld	H,B
	ld	L,C		; HL = 0x10...0x03FF
	ld	DE,0x10		; DE = 0x0010
	or	a
	sbc	hl,de		; HL = 0x0000...0x03EF
	jp	C,ERR10		; if block # was <0x10

	push	HL	; \\
	ld	DE,0x3F0
	or	a
	sbc	hl,de		; 0x03FF - block #
	jp	NC,ERR10	; if block # >=0x03F0
	pop	HL	; //

	xor	a
      rept 3		  ; ---
	srl	H
	rr	L
	rra
      endm		  ; ---
	rlca
	rlca
	rlca

	or	a
	ld	DE,RescBuf
	add	HL,DE
	ex	de,hl
	call	setbit		; set bit 0...7 in (DE) if a=0...7
	pop	HL	; /
	ret

; ************************************************************************

FLAG_X		equ BUF+90	; bit 7: load_from_pc, other bits: ascii +|-|=
file_name	equ BUF+92	; 14 by, naziv fajla
displacement	equ BUF+106	; displacement
free_bits	equ BUF+108	; lo = bit arrangement (00000000-11111111)
				; hi = # of byte (0-125)
next_block	equ BUF+110	; NEXT free block for writing (0x0010-0x03FF)
from		equ BUF+112	; Parameter 1 (FROM)
to		equ BUF+114	; Parameter 2 (TO)
start_of_fn	equ BUF+116	; addr of start of fn in mem (after [ ] and ["])
memorized	equ BUF+118	; lo = # of pos inside block (0-31)
				; hi = # of block (1-15)
current		equ BUF+120	; # of CURRENT block in test (1-15)
fn_len		equ BUF+122	; filename len (1-14), len in blocks (1-59)
save_flag	equ BUF+124	; bit 7 set = save to computer

;-------------------------------------------|
;  0  1  2  3    4  5  6  7    8  9  A  B   |   C  D  E  F
;  O  J  R  H    K  P  T  U    V  N  L  B   |   W  D  G  F
;-------------------------------------------|

; ************************************************************************
; ************************************************************************
; *****    S A V E      **************************************************
; ************************************************************************
; ************************************************************************

flash_save		; write mem (DE)...(HL-1) to EE (find place), filename (DE)
	call	Z40		; skip blanks
	cp	'#'		; "computer" symbol
	jp	z,save_to_pc	; ----------------------> PC
        DI
	call	locate_filename
	push	af	; \
	call    Z40	; Z40 = skip blanks (ptr DE)
	cp	0x2C		; 0x2C = comma
	jr	nz,$+3
	inc	DE		; skip '"' if any
        LD      BC,BASPTR	; BASPTR ili (BASPTR)
	ld	(from),bc	; 1st num string
        LD      HL,(BASEND)	; basic end+1
	ld	(to),hl
	ld	a,(de)
	cp	0dh
	jr	z,NODIM2_b
         RST	 Z807		; read 1st num string to HL
	 ld	 (from),hl	; 1st num string
         CALL	 ZAREZ		; IF (DE)="," read 2nd num string to HL, else WHAT
         INC	 HL		; ++ addr of first unused byte
	 ld	 (to),hl	; 2nd num string ++
NODIM2_b
	ld	de,(from)
	dec	hl		; last used byte instead of first unused
	or	a		; clr C
	sbc	hl,de		; (to) - (from)
	jp	c,ERR7		; if range was zero or negative

	pop	af	; /
	jr	nz,name_not_fou1;  ==========================>
	ei
        LD      DE,message_o_yn	; "FILE EXISTS. OVERWRITE? (Y/N)?_"
        CALL    Z94F		; print it on screen
	call	ny		; wait for N/ESC or Y key, go to STOP_RELEASE if N/ESC
	di
 ; decided: save program
	call	can_it_fit	; test da li program moze da stane u flash (go HOW if not)
	call	erase_pgm_mm	; ERASE PGM (memorized)

	jr	start_save
name_not_fou1	; NZ:not fou, H=block # 1-15, L=free name # ; <==========================
	call	can_it_fit	; test da li program moze da stane u flash (go HOW if not)
start_save
 ; file saving starts now, find the 1st free block (block 0 already in FlBuf)
	ld	bc,0
	call	read_block_fb	; **** 0000 read block 0
	call	find_0_in_FlBuf	; find free bit in FlBuf, update free_bits & next_block
 ; filename
	ld	bc,(memorized+1) ; hi = # of block (1-15)
	ld	b,0		; bc = # of block (1-15)
	call	read_block_fb	; **** NAME read block (1-15)

	ld	hl,(memorized)	; lo = # of pos inside block (0-31)
	ld	h,0
	add	hl,hl		; x2
	add	hl,hl		; x4
	add	hl,hl		; x8
	add	hl,hl		; x16
	ld	de,FlBuf
	add	hl,de		; HL = destinatio-n
	ex	de,hl		; DE = destination
	ld	hl,(start_of_fn)
	ld	bc,(fn_len)
	ld	b,0		; bc = filename length
	ldir			; copy FILENAME to flash buffer
 ; fill gap with zeros
	ex	de,hl		; hl = filename + 1
go_zeros
	ld	a,L
	and	0x0F
	cp	14
	jr	z,end_of_name
	ld	(hl),0
	inc	hl
	jr	go_zeros
end_of_name		; HL = name (in blocks 1-15) + 14 (1st block # + blocks count)
	push	hl	; \
	ld	hl,(to)
	ld	bc,(from)
	or	a		; clr Carry
	sbc	hl,bc		; HL = file length in bytes
	call	bytes_to_blocks	; input HL bytes, output DE blocks
	ld	a,e
	ld	(fn_len+1),a	; length in blocks (0...60)
	pop	hl	; /
 	ld	bc,(next_block)
	ld	(hl),c		; next block lo
	inc	hl
	sla	a		; len <
	sla	a		; len <<
	or	b		; bits 10 next block + bits 765432 length in blocks
	ld	(hl),a		; next block wrtitten after filename
	ld	bc,(memorized+1) ; hi = block # (1-15)
	ld	b,0		; bc = block # with filename and 1st block #
	call	write_block_fb	; @@@@ NAME Write block (1...15) with filename(s)

	ld	bc,0
	call	read_block_fb	; **** 0000 rd block 0 to FlBuf

	call	find_0_in_FlBuf	; find free bit (FlBuf), update free_bits & next_block
	call	setbit		; mark bit 0...7 in (DE) as used if a=0...7
	ld	bc,(next_block)
	call	spec_1_wr_block	; @@@@spec DATA wr from 2 + to 2 + 506by + next block 2
	jr	c,save_done
wr_blocks
	call	find_0_in_FlBuf	; find free bit (FlBuf), update free_bits & next_block
	call	setbit		; mark bit 0...7 in (DE) as used if a=0...7
	ld	bc,(next_block)
	call	spec_n_wr_block	; @@@@spec DATA wr 510by + next block 2by (=from)
	jr	nc,wr_blocks
save_done:
	ld	bc,0
	call	write_block_fb	; @@@@ 0000 write back block 0 (with bits set)
;	call	show1	; ************************************
	jp	cr66		; done

; ----------------------------------------------------------
can_it_fit		; test da li program moze da stane u flash (go HOW if not)
	call	get_blocks	; at exit: HL = number of free blocks (0...1024)
	ld	a,(fn_len+1)	; length of pgm in blocks

	ld	c,a
	ld	b,0		; bc <---- (fn_len+1)
	add	hl,bc		; as (fn_len+1) blocks will be free after file erasing

	push	hl	; \	; number of free blocks in flash
	ld	de,(from)
	ld	hl,(to)
	or	a		; clr Carry
	sbc	hl,de
	ret	z		; if pgm length = 0
	call	bytes_to_blocks	; input HL bytes, output DE blocks (HL must be >0)
	pop	hl	; /
	or	a		; clr Carry
	sbc	hl,de		; free blocks - blocks needed by pgm
	jp	c,ERR8		; if not enough place in flash!
	ret

; ----------------------------------------------------------
find_0_in_FlBuf	; find unused block in the FlBuf, update free_bits and next_block
	ld	a,0xFF
	ld	hl,FlBuf
	ld	b,128-2
go126
	cp	(hl)
	jr	nz,found_free_space
	inc	hl
	djnz	go126
	jp	SORRY		; not found byte <255 (should never come here)
found_free_space
	ld	d,h
	ld	e,l		; DE <---- HL (physical addr of byte with bit 0)
	ld	a,(HL)		; a = byte with bit 0 (occupancy bits)
	ld	H,L		; H : # of byte (0...125)
	ld	L,a		; L : bit arrangement (00000000-11111111)
 	ld	(free_bits),HL	; low : bit arrangement, high: # of byte
; HL <---- H
	ld	l,h
	ld	h,0		; HL = # of byte in block bit area (0...125)
; HL <---- hl * 8
	add	hl,hl		; # of byte x2
	add	hl,hl		; # of byte x4
	add	hl,hl		; # of byte x8
; HL <---- HL+0x10
	ld	bc,0x10
	add	hl,bc
; count one's in A from right and add to HL, copy to BC
	call	get_zero	; in: A = occupancy bits, out: C = # of 1's from right
	ld	a,c
	ld	b,0		;BC = 0...7 (bit pos of 0, the first free block)
	add	hl,bc
	ld	(next_block),hl	; new value of block #, adj to 0x0010...0x03FF
	ret			; NOTE: keep DE and A at exit, SETBIT needs them!

; ----------------------------------------------------------
get_zero		; in: A = occupancy bits, out: C = number of 1's from right
	ld	c,0xFF
	cp	c
	jp	z,SORRY		; Zero set = no free block here (should never come here)
count8
	inc	c
	rrca
	jr	c,count8
	ret

; ************************************************************************
; ************************************************************************
; *****    O L D        **************************************************
; ************************************************************************
; ************************************************************************

old_both		; load file (DE) from EE or from UART
	xor	a
	ld	(FLAG_X),a
	ld	(fn_len),a
	ld	hl,0
	ld	(displacement),hl ; default displacement = 0
	ld	(start_of_fn),de ; addr of start of filename
	call	Z40		; skip blanks
	cp	'#'		; "computer" symbol
	jr	nz,no_flag_pc	; ---->
 ; -PC-
	inc	de
	ld	a,0x80
	ld	(FLAG_X),a
no_flag_pc			; <----
 ; BOTH
	call	countname
	ld	a,(FLAG_X)
	bit	7,a
	jr	nz,notEE
 ; -EE-
	ld	a,(fn_len)
	or	a
	jp	Z,ERR1		; must have filename if in EE mode
	ld	de,(start_of_fn)
        DI
	call	locate_filename
	jp	nz,ERR2		; No such file
	call	skip_quote
notEE
 ; BOTH
	call	read_p_m_e	; if -|+|= then update FLAG_X and displacement, go WHAT if <> CR
	ld	a,(FLAG_X)
	bit	7,a
	jp	nz,load_from_pc	; if PC mode ===================================> GO SERIAL
; ------------------------------
	ld	bc,(memorized+1); C=block (1...15)
	ld	b,0		; BC = Block # (1...15)
	call	read_block_fb	; rd block with names
	ld	hl,(memorized)	; L= of pos inside block (0...31), H=block (1...15)
	ld	h,0
	add	hl,hl		; hl = block * 2
	add	hl,hl		; hl = block * 4
	add	hl,hl		; hl = block * 8
	add	hl,hl		; hl = block * 16 (range 0x0000-0x01F0 step 16)
	ld	de,FlBuf+14
	add	hl,de		; hl <--- point to AFTER filename in FlBuf
 ; hl <--- point to AFTER filename in FlBuf
	ld	c,(hl)
	inc	hl
	ld	a,(hl)
	and	3
	ld	b,a		; bc point to 1st block of file
 ; bc point to 1st block of file
	call	read_block_fb	; **** DATA read the 1st block of data

	ld	hl,FlBuf
	ld	e,(hl)
	inc	hl	; ++
	ld	d,(hl)		; de = FROM
 ;;;	LD	(BASPTR),de	; BASPTR
	ld	hl,(displacement)

	ld	a, (FLAG_X)
	and	0x7F
	cp	'='
	jr	z,$+3		; if prefix '=' then (from) <--- displacement

	add	hl,de
	ld	(from),hl

	ld	hl,FlBuf+2
	ld	e,(hl)
	inc	hl	; ++
	ld	d,(hl)		; de = TO
 ;;;	LD	(BASEND),de	; BASEND
	ld	hl,(displacement)

	ld	a, (FLAG_X)
	and	0x7F
	cp	'='
	jr	nz,$+3		; if prefix <>'=' then calculate (to)
	push	hl	; \
	ld	hl,(to)
	ld	bc,(from)
	or	a
	sbc	hl,bc
	ld	b,h
	ld	c,l		; bc <--- (to) - (from)
	pop	hl	; /
	add	hl,bc		; hl <--- displacement + (to-from) (za prefix =)
	jr	no_calc_to

calc_to
	add	hl,de
no_calc_to
	ld	(to),hl

	ld	hl,FlBuf+4
	ld	bc,506
	call	transfer
old_loop
	call	read_block_fb	; **** DATA read the next block of data
	ld	hl,FlBuf
	ld	bc,510
	call	transfer
	jr	old_loop

;-------------------------------
transfer	    ; in: HL source (FlBuf), transfer BC bytes or when (from)=(to)
go_transfer			; LOOP   <=====================
	ld	a,(hl)
	inc	hl	; ++
	ld	de,(from)
	ld	(de),a		; UPIS U MEMORIJU
	inc	de	; ++
	ld	(from),de	; updated (from)
	push	hl	; \
	ld	hl,(to)
	or	a
	sbc	hl,de		; (to) - (from), NC if (to) >= (from)
	pop	hl	; /
	jr	z,old_done	; if (to) = (from)
	jr	c,old_done	; if (to) < (from)
	dec	bc	; --
	ld	a,b
	or	c
	jr	nz,go_transfer	; LOOP   =====================>
	ld	c,(hl)
	inc	hl	; ++
	ld	b,(hl)		; bc <---- next block
	ld	a,b
	or	c
	ret	nz		; if bc > 0
old_done
	jp	Z1C9		; BREAK ept

; ------------------------------

countname		; service quotes, (start_of_fn), (fn_len)
	call	skip_quote
	call	Z40		; skip blanks
	ld	(start_of_fn),de
	call	count_chars
	dec	de
	ld	(fn_len),a
	jp	skip_quote	; skip blanks and quote, if any

; ------------------------------
read_p_m_e
	call	Z40		; skip blanks
	cp	'-'		; -
	jr	z,minus
	cp	'+'		; +
	jr	z,plus
	cp	'='		; =
	jr	z,plus		; zasad se tretira isto kao +
	cp	0x0d		; <CR>
	jp	nz,ERR6		; if not +|-|=|CR
	ret
minus			; -
	push	AF	; \
	inc	de
	RST	Z807		; read num string to HL (displacement)
	ld	b,h
	ld	c,l
	ld	hl,0
	or	a		; clr Carry
	sbc	hl,bc		; HL <=== 0-HL
	pop	AF	; /
	jr	emp1
plus			; +
	push	AF	; \
	inc	de
	RST	Z807		; read num string to HL (displacement)
	pop	AF	; /
emp1
	ld	c,a
	ld	(displacement),hl
	call	Z40		; skip blanks
	cp	0x0d		; <CR>
	jp	nz,ERR6		; if not +|-|=|CR
	ld	a,(FLAG_X)
	or	c
	ld	(FLAG_X),a
	xor	a		; set Z
	ret			; Z (DE++)

; ------------------------------
countname_L		; count and skip quotes (L), (start_of_fn), (fn_len)
			; same as 'countname', but counts quotes (L)
	ld	L,0		; L = quote counter
	call	skip_quote_2
	call	Z40		; skip blanks
	ld	(start_of_fn),de
	call	count_chars
	dec	de
	ld	(fn_len),a
skip_quote_2		; skip blanks and if quote, skip it (ptr DE)
	call    Z40	; Z40 = skip blanks (ptr DE)
	cp	34		; 34 = '"'
	ret	nz
	inc	de
	inc	L	; count quotes
	call    Z40	; Z40 = skip blanks (ptr DE)
	ret		; L = # of quotes skipped

; *****************************************************************
; *****************************************************************
;     S A V E   T O   P C          ********************************
; *****************************************************************
; *****************************************************************

save_to_pc
	inc	de		; skip "#"
        CALL    Z40     	; skip blanks, pointer de
	cp	0x0d		; CR?
	jr	nz,name_exists

	ld	HL,0
	ld	(start_of_fn),HL
	xor	a
	ld	(fn_len),a
	ld	L,2		; simulate quotes
	jr	simulated_L
name_exists
	call	countname_L	; count and skip quotes (L), (start_of_fn), (fn_len)
simulated_L
	ld	a,(fn_len)
	or	a
	jr	nz,there_was_name
; check if there were quotes instead of name
	ld	a,L
	or	a
	jr	nz,quotes_present
	ld	HL,(fn_len)
	ld	a,H
	or	L
	jp	z,WHAT		; no quotes, no name, so ----> WHAT
there_was_name
quotes_present
	call    Z40	; Z40 = skip blanks (ptr DE)
	cp	0x2C		; 0x2C = comma
	jr	nz,$+3
	inc	DE		; skip '"' if any
 ;;; get parameters
        LD      BC,BASPTR	; BASPTR
	ld	(from),bc	; 1st num string
        LD      HL,(BASEND)	; basic end+1
	ld	(to),hl
	ld	a,(de)
	cp	0dh
	jr	z,NODIM2_a
         RST	 Z807		; read 1st num string to HL
	 ld	 (from),hl	; 1st num string
         CALL	 ZAREZ		; IF (DE)="," read 2nd num string to HL, else WHAT
         INC	 HL		; ++ addr of first unused byte
	 ld	 (to),hl	; 2nd num string ++
NODIM2_a
	ld	de,(from)
	dec	hl		; last used byte instead of first unused
	or	a		; clr C
	sbc	hl,de		; (to) - (from)
	jp	c,ERR7		; if range was zero or negative

	DI			; DI
	xor	a
	ld	(chs),a
	ld	a,0xC7
        call    txbyte		; command byte 0xC7  ---------------------------->
;;; send_filename
	ld	de,(start_of_fn)
	ld	HL,(fn_len)
	ld	h,14		; total bytes to send
	ld	a,l		; active (non-zero) bytes to send
	or	a
	jp	z,send_zeros_loop_s ; if no filename specified (sends 14 zeros)
send_fn_loop_s
	ld	a,(de)
	inc	de
        call    txbyte		;  filename  ---------------------------->
	dec	h
	dec	L
	jr	nz,send_fn_loop_s

	ld	a,h
	or	a
	jr	z,zero_zeros_s
send_zeros_loop_s
	xor	a
        call    txbyte		;  binary zeros  ----------------------------->
	dec	h
	jr	nz,send_zeros_loop_s
zero_zeros_s
	ld	DE,(from)
	ld	A,E
        call    txbyte		;  FROM lo  ----------------------------->
	ld	A,D
        call    txbyte		;  FROM hi  ----------------------------->
	ld	HL,(to)
	ld	A,L
        call    txbyte		;  TO lo  ----------------------------->
	ld	A,H
        call    txbyte		;  TO hi  ----------------------------->

	or	a		; clr Carry
	sbc	HL,DE
body_loop		    ; \
	ld	A,H
	or	L
	jr	z,body_done	; \
	ld	A,(DE)
        call    txbyte		;  DATA  ----------------------------->
	inc	DE
	dec	HL
	jr	body_loop   ; /
body_done			; /
	ld	A,(chs)
        call    txbyte		;  CHS  ----------------------------->
; RECEIVE ERROR MESSAGE for TRANSMIT
error_parser
remt
	call	rxbyte
	cp	0xCC
	jp	nz,ERR11
	call	rxbyte
	cp	0xDD
	jp	nz,ERR11
	call	rxbyte
	cp	0xEE
	jp	nz,ERR11
	call	rxbyte
; receive parser
	cp	0xF0
	jp	z,Z1C9		; All set
	cp	0xF1
	jp	z,ERR12		; DIFFERENT FILENAMES SPECIFIED
	cp	0xF2
	jp	z,ERR13		; FILE NOT FOUND IN PC FOLDER
	cp	0xF3
	jp	z,ERR4		; BAD CHECKSUM
	cp	0xF4
	jp	z,ERR15		; NO FILENAME SPECIFIED
	cp	0xF5
	jp	z,ERR16		; BAD FILE FORMAT
	cp	0xF6
	jp	z,ERR3		;

	jp	ERR11		; UNRECOGNIZED REPLY FROM PC

; ----------------------------------------------------------------

; *****************************************************************
; *****************************************************************
;     L O A D   F R O M   P C        ******************************
; *****************************************************************
; *****************************************************************

load_from_pc	; send  0xA3, (filename)
		; receive  0xA5, (filename), (from), (to), (file_data...), CHS
		; only ESC is active all the time
;;; DE points to filename
;;; (FLAG_X bit 7) and (displacement -,+,=) set
;;; also (start_of_fn) and (fn_len)
;;; send_command
	DI			; DI
	ld	a,0xA3
        call    txbyte		; command byte 0xA3  ---------->
;;; send_filename
	ld	de,(start_of_fn)
	ld	HL,(fn_len)
	ld	h,14		; total bytes to send
	ld	a,l		; active (non-zero) bytes to send
	or	a
	jr	z,send_zeros_loop ; if no filename specified (sends 14 zeros)
send_fn_loop
	ld	a,(de)
	inc	de
        call    txbyte		;  filename in loop    ---------->
	dec	h
	dec	L
	jr	nz,send_fn_loop

	ld	a,h
	or	a
	jr	z,zero_zeros
send_zeros_loop
	xor	a
        call    txbyte		;  binary zero    ---------->
	dec	h
	jr	nz,send_zeros_loop
zero_zeros

 ;;; receive 1st raport -------------------------------------------------------

	call	rxbyte
	cp	0xCC		; poruka greske?
	jp	nz,ERR11
	call	rxbyte
	cp	0xDD
	jp	nz,ERR11
	call	rxbyte
	cp	0xEE
	jp	nz,ERR11
	call	rxbyte
 ; receive parser
	cp	0xF0
	jp	z,cont_rx_load
	cp	0xF1
	jp	z,ERR12		; DIFFERENT FILENAMES SPECIFIED
	cp	0xF2
	jp	z,ERR13		; FILE NOT FOUND IN PC FOLDER
	cp	0xF4
	jp	z,ERR15		; NO FILENAME SPECIFIED
	cp	0xF6
	jp	z,ERR3		; Error on serial line
	jp	ERR11		; UNRECOGNIZED REPLY FROM PC

 ;;; receive header + file -------------------------------------------------------

cont_rx_load
	call	rxbyte		;       <---------- 1
	cp	0xA5		; A5
	jr	z,syncedA5

	call	rxbyte		;       <---------- 2
	call	rxbyte		;       <---------- 3
	call	rxbyte		;       <---------- 4
	call	rxbyte		;       <---------- 5
	call	rxbyte		;       <---------- 6
	cp	0xA5
	jp	nz,WHAT		; nije stiglo A5 ni kao 1. ni k ao 6. bajt	
syncedA5
	ld	(chs),a		; ini CHS adder
; ime programa, uvek 14 by (višak su binarne nule)
	ld	DE,file_name
	ld	B,14
go_rx_14
	call	rxbyte2		;       <----------
	ld	(DE),a		; filename 14 ASCII bytes
	inc	DE
	djnz	go_rx_14

	call	rxbyte2		;       <----------
	ld	e,a
	call	rxbyte2		;       <----------
	ld	d,a		; DE = FROM	2c36
	call	rxbyte2		;       <----------
	ld	b,a
	call	rxbyte2		;       <----------
	ld	h,a		; 4
	ld	l,b		; 4    HL = TO	34e8

	sbc	hl,de		; 15   TO - FROM
	ld	c,l		; 4
	ld	b,h		; 4

;;; receive file
	call	rxbyte_spec	; calculates displacement inside Rx subroutine
	ld	(de),a
	inc	de
go_rec				; <----
	call	rxbyte2		;       <----------
	ld	(de),a
	inc	de
	dec	bc
	ld	a,b
	or	c
	jp	nz,go_rec	; ---->

	ld	A,(chs)
	ld	E,A
	call	rxbyte2		;       <----------	Receive CHS
	EI			; EI
	cp	E
	jp	z,0x0066
	jp	ERR4		; CHS error

; *****************************************************************
; *****************************************************************
;       S E R I A L     T X        ********************************
; *****************************************************************
; *****************************************************************

; 1T = 0.3333 uS
; 1 bit @ 19200 baud = 52.08 uS = 156 T/bit
txbyte			; Tx A reg (19200 baud = 156 T/bit)  ABC
	ld	c,a

	ld	a,(chs)
	add	c
	ld	(chs),a

	or	a		; 4   clear carry
	call	txbit		; 17 + 118 = 135 start bit
	ld	b,8		; 7   bit counter
	ld	b,8		; 7   bit counter
tx8
	rrc	c		; 8
	call	txbit		; 17 + 118 = 135 each (data bits)
	djnz	tx8		; 13|8
	scf			; 4   stop bit
txbit				;     sub 118T + 17T call
	ld	a,0b00000000	; 7   for timing only
	ld	a,0b00000000	; 7
	rra			; 4   Carry to bit 7,A
	ld	(latadr),a	; 13
	ld	a,5		; 7
txbaud
	dec	a		; 4 x 5 = 20
	jp	nz,txbaud	; 10 x 5 = 50
	ret			; 10

; *****************************************************************
; *****************************************************************
;       S E R I A L     R X        ********************************
; *****************************************************************
; *****************************************************************

STOP2   jp      STOP
;________________________________

; 1T = 0.3333 uS
; 1 bit @ 19200 baud = 52.08 uS = 156 T/bit
; on exit: Carry set = reception OK, byte in A and C
;          NC, NZ    = framing error (no stop bit), go to WHAT?
;          NC, Z     = reception interrupted (BRK), go to BREAK

rxbyte_spec        ; (1st byte only!) Rx A reg (19200 baud = 156 T/bit) (234 T/1.5 bit)
        ld      hl,0x203A       ; 10    Rx bit addr
rxloop_1                   ; \
        ld      a,(0x2031)      ; 13
        rrca                    ; 4
        jr      nc,STOP2        ; 7     if BREAK hit
        ld	a,(hl)		; 7
        rrca                    ; 4
        jp      c,rxloop_1 ; /  ; 10    loop 45 T, wait for LOW input
                        ;   ************ here ~37 T (+/- 23 T) after start bit \_ edge
 ;  time optimization
	ld	a,(FLAG_X)	;;;  +|-|=  13 t
	cp	'='+0x80	;;;  +|-|=   7 t (PC flag is set, that's why +0x80)
	jr	nz,not_exact	;;;  +|-|=   7/12 t (32 t after jr, 27 t if no jr)
 
; exact			; comes with 13+7+7=27 t
	ld	de,(displacement) ;;;  =    20 t
	ld	a,7		; ;;;  =     7 t  ******************************
	jp	skr_rx		; ;;;  =    10 t   (64 t)
                        ;   ************ here ~101 t after start bit \_ edge

not_exact			; comes with 13+7+12=32 t
	nop			;;;    4 t
	ld	hl,(displacement) ;;; 16 t
	add	hl,de		;;;   11 t  hl = (displacement) + (from)
	ex	de,hl		;;;    4 t  de = (displacement) + (from)
	ld	hl,0x203A	;;;   10 t  Rx bit addr
	ld	a,5		;;;    7 t        ******************************
	jp	skr_rx		;;;   10 t       (90 t)
                        ;   ************ here ~131 t after start bit \_ edge

rxbyte                  ; Rx A reg (19200 baud = 156 T/bit)  A,HL
        ld      hl,0x203A       ; 10    Rx bit addr
rxbyte2                    ; \
        ld      a,(0x2031)      ; 13
        rrca                    ;  4
        jr      nc,STOP2        ;  7     if BREAK hit
        ld	a,(hl)		;  7
        rrca                    ;  4
        jp      c,rxbyte2  ; /  ; 10    loop 45 T, wait for LOW input
                        ;  here ~37 T (+/- 23 T) after start bit \_ edge
	nop			;  4
        ld      a,10            ;  7              ******************************
                        ;  here ~48 T (+/- 23 T) after start bit \_ edge
skr_rx
        dec     a          ; \  ;  4*A
        jp      nz,$-1     ; /  ; 10*A   first timing for 1.5 bits(=234 T)
                        ; here ~200 T after start bit falling edge
        call    rxbit           ; 156
        call    rxbit           ; 156
        call    rxbit           ; 156
        call    rxbit           ; 156
        call    rxbit           ; 156
        call    rxbit           ; 156
        call    rxbit           ; 156
        call    rxbit7          ; 70	37
                        ; CHS service
	 ld	 HL,chs		 ; 10
	 push	 AF	  ; \	 ; 11
	  add	  a,(HL)	  ; 7
	  ld	  (HL),a	  ; 7	     affects 8 bits only
	 pop	 AF	  ; /	 ; 10
	 ld	 HL,0x203A	 ; 10	55   Restore HL
                        ; STOP bit
        call    retonly3        ; 27
        bit     0,(hl)          ; 12	
        or	a		; 4	     clr C
        bit     0,(hl)          ; 12	55   read stop bit
        ret     nz              ; 11  ret if input high (OK stop bit)

        jp      ERR3            ;     framing err (no stop bit)
;________________________________

rxbit7                     ; call 17
        rrca                    ; 4
        bit     0,(hl)          ; 12         get -Rx to Z flag
        jr      z,$+4           ; 12  7   +
        set     7,a             ; 0   8   +
        jr      nz,$+4          ; 7   12  +
        res     7,a             ; 8   0   + = 27
	ret                     ; 10

rxbit                      ; call 17
        rrca                    ; 4
        bit     0,(hl)          ; 12         get -Rx to Z flag
        jr      z,$+4           ; 12  7   +
        set     7,a             ; 0   8   +
        jr      nz,$+4          ; 7   12  +
        res     7,a             ; 8   0   + = 27
        call    retonly2        ; 35
        call    retonly2        ; 35
        nop                     ; 4
        nop                     ; 4
retonly2
        nop                     ; 4
        nop                     ; 4
retonly3
        ret                     ; 10
;________________________________

STOP4
	jp	STOP

rxbyte_rt              ; RUNTIME Rx A reg (19200 baud = 156 T/bit)  A,HL
        ld      hl,0x203A       ; 10    Rx bit addr
rxbyte2_rt                 ; \
        ld      a,(0x2031)      ; 13
        rrca                    ;  4
        jr      nc,STOP4        ;  7     if BREAK hit
        ld	a,(hl)		;  7
        rrca                    ;  4
        jp      c,rxbyte2  ; /  ; 10    loop 45 T, wait for LOW input
                        ;  here ~37 T (+/- 23 T) after start bit \_ edge
	nop			;  4
        ld      a,10            ;  7              ******************************
                        ;  here ~48 T (+/- 23 T) after start bit \_ edge
        dec     a          ; \  ;  4*A
        jp      nz,$-1     ; /  ; 10*A   first timing for 1.5 bits(=234 T)
                        ; here ~200 T after start bit falling edge
        call    rxbit           ; 156
        call    rxbit           ; 156
        call    rxbit           ; 156
        call    rxbit           ; 156
        call    rxbit           ; 156
        call    rxbit           ; 156
        call    rxbit           ; 156
        call    rxbit7          ; 70
 ; CHS
	 ld	 HL,chs		 ; 10
	 push	 AF	  ; \	 ; 11
	  add	  a,(HL)	  ; 7
	  ld	  (HL),a	  ; 7	     affects 8 bits only
	 pop	 AF	  ; /	 ; 10
	 ld	 HL,0x203A	 ; 10	55   Restore HL
	ret

; *****************************************************************
; *****************************************************************
; ******      R U N T I M E     T X        ************************
; *****************************************************************
; *****************************************************************

GO_TY
	ld	HL,0x2A80	; Y$
	jr	skr_T
GO_TX
	ld	HL,0x2A70	; X$
skr_T
	DI
	push	HL	; \
	LD	L,50		; ZEROS TO SEND
zeros50
	ld	a,0x00
	call	txbyte		; ------> 00 (50 times)
	dec	l
	jr	nz,zeros50
	pop	hL	; /

	ld	a,0xFF
	call	txbyte		; ------> FF
	ld	a,0xD6
	call	txbyte		; ------> D6 sync
	xor	a
	ld	(chs),a
sendXstring
	ld	a,(HL)
	inc	HL
	call	txbyte		; ------> data 16x
	ld	a,L
	and	0x0F
	jr	nz,sendXstring
	ld	a,(chs)
	call	txbyte		; ------> CHS

	EI
	rst	Z48		; GO NEXT INSTRUCTION

; *****************************************************************
; *****************************************************************
; ******      R U N T I M E    R X        *************************
; *****************************************************************
; *****************************************************************

GO_RY
	ld	BC,0x2A80	; Y$
	jr	skr_R
GO_RX
	ld	BC,0x2A70	; X$
skr_R
	ld	a,#1
	ld	(RxFLAG),a
wait_Rx
        ld      a,(0x2031)      ; 13
        rrca                    ;  4
        jp      nc,STOP         ;  7     if BREAK hit
	ld	A,(RxFLAG)
	and	1
	jr	nz,wait_Rx	; if no Rx bit 0 was detected during INT
	DI
getD6
	call	rxbyte_rt	; <------ D6 sync
	cp	0xD6
	jr	nz,getD6
	xor	a
	ld	(chs),a
getXstring
	call	rxbyte2_rt	; <------ data 16x
	ld	(BC),a
	inc	BC
	ld	a,C
	and	0x0F
	jp	nz,getXstring
	ld	a,(chs)
	ld	C,A
	call	rxbyte_rt	; <------ CHS
	cp	c
	ld	hl,0xFFFF	; HL = -1, CHS ERROR
	jr	nz,badchs_rt
	inc	hl		; HL = 0, CHS OK
badchs_rt
	EI
	JP	ZC59	; izlaz funkcije (dodeli vrednost HL, GO NEXT INSTRUCTION)

; ----------------------------------------------------------------

ERR1			; Filename not defined
	ld	de,errmes_fnd
	jr	ERRX
ERR2			; No such file
	ld	de,errmes_nsf
	jr	ERRX
ERR3			; Error on serial line
	ld	de,errmes_esl
	jr	ERRX
ERR4			; CHS error
	ld	de,errmes_chs
	jr	ERRX
ERR5			; too many parameters
	ld	de,errmes_tmp
	jr	ERRX
ERR6			; EXPECTED  -, +, =,
	ld	de,errmes_pmj
	jr	ERRX
ERR7			; IRREGULAR RANGE
	ld	de,errmes_ir
	jr	ERRX
ERR8			; not enough place in flash
	ld	de,errmes_nep
	jr	ERRX
ERR9			; string length
	ld	de,errmes_sl
	jr	ERRX
ERR10			; data damaged, can't rescan
	ld	de,errmes_dd
	jr	ERRX
ERR11			; unrecognized reply from PC
	ld	de,errmes_wm
	jr	ERRX
ERR12			; DIFFERENT FILENAMES SPECIFIED
	ld	de,errmes_df
	jr	ERRX
ERR13			; FILE NOT FOUND IN PC FOLDER
	ld	de,errmes_fnp
	jr	ERRX
ERR15			; NO FILENAME SPECIFIED
	ld	de,errmes_nfs
	jr	ERRX
ERR16			; BAD FILE FORMAT
	ld	de,errmes_bff
	jr	ERRX
ERRX
        CALL    Z94F		; print it on screen
	jp	Z1C9		; BREAK ept
; ----------------------------------------------------------------

errmes_bff	defb	'BAD FILE FORMAT',13
errmes_nfs	defb	'NO FILENAME SPECIFIED',13
errmes_fnp	defb	'FILE NOT FOUND IN PC FOLDER',13
errmes_df	defb	'DIFFERENT FILENAMES SPECIFIED',13
errmes_wm	defb	'UNRECOGNIZED REPLY FROM PC', 13
errmes_dd	defb	'DATA DAMAGED, CAN', 27, 'T RESCAN', 13
errmes_fnd	defb	'FILENAME NOT DEFINED', 13
errmes_sl	defb	'BAD NAME LENGTH', 13
errmes_nep	defb	'NOT ENOUGH FREE SPACE IN EEPROM', 13
errmes_ir	defb	'WRONG RANGE', 13
errmes_pmj	defb	'DISPLACEMENT SIGNS ARE -,+,=', 13
errmes_tmp	defb	'TOO MANY PARAMETERS', 13
errmes_chs	defb	'CHECKSUM ERROR', 13
errmes_esl	defb	'FRAMING ERROR IN SERIAL SIGNAL', 13
errmes_nsf	defb	'NO SUCH FILE', 13
message_flf	defb	' FILE'
message_f_yn	defb	'DELETE ALL DATA IN EEPROM? (Y/N)?_', 0
mes_f_complete	defb	'FORMAT COMPLETE', 13
mon_ini		defb	'MONITOR INITIALIZED', 13
message_bu	defb	' BLOCKS USED,', 0
message_total	defb	'TOTAL',0
message_bf	defb	' FREE', 13
message_o_yn	defb	'FILE EXISTS. OVERWRITE? (Y/N)?_', 0
txt_screen2	defb	'SCREEN', 13
txt_memory2	defb	'MEMORY', 13
txt_screen1	defb	'SCREEN &2800,&2A00', 13
txt_memory1	defb	'MEMORY &2C36,&9DFE', 13

;*********************************************************
	END
;*********************************************************
