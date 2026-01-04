; Galaksija DOT routine by Voja Antonić, optimized for Z88DK
; Fills screen from (0,0) to (63,47) rapidly using _dot

    PUBLIC _dot
    PUBLIC _undot
    PUBLIC _ifdot


_dot:
    LD D, H       ; X (C passes it in L)
    LD E, L       ; Y (C passes it in H)
    LD A, 0x80
    JP pt1

_undot:
    LD D, H
    LD E, L
    LD A, 1
    JP pt1



_ifdot:
    LD D, H       ; X (in L)
    LD E, L       ; Y (in H)
    XOR A         ; mode 0 for ifdot
    CALL pt1
    ; result of AND (HL) was done in pt1; we now use Z flag
    LD H, 0          ; Return z flag.Place result in L for return
    LD L, 0       ; assume OFF
    RET Z         ; if Zero (pixel is OFF), return 0
    LD L, 1       ; else ON
    RET



pt1:
    PUSH DE
    EXX
    POP DE
    OR A
    PUSH AF
    LD C,D
    PUSH BC
    LD BC,0x20
    INC E
    LD HL,0x2800
goY:
    LD D,3
    LD A,1
y3:
    DEC E
    JR Z,gotov
    RLCA
    RLCA
    DEC D
    JR NZ,y3
    ADD HL,BC
    RES 1,H
    JR goY
gotov:
    LD B,A
    EX (SP),HL
    RES 7,L
    RES 6,L
    SRL L
    JR NC,parni
    RLCA
parni:
    LD H,0
    POP BC
    ADD HL,BC
    LD B,A
    POP AF
    LD A,B
    JR NZ,sres
    BIT 7,(HL)
    JR Z,exret
    AND (HL)
exret:
    EXX
    RET

sres:
    PUSH AF
    BIT 7,(HL)
    JR NZ,sr
    LD (HL),0x80
sr:
    POP AF
    JP M,setxy
    CPL
    AND (HL)
    LD (HL),A
    EXX
    RET

setxy:
    OR (HL)
    LD (HL),A
    EXX
    RET
