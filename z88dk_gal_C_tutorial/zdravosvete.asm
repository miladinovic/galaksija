ROMPRINT  EQU     0x0937      ; ROM routine: prints zero-terminated string

PUBLIC _main:
; --- Main program ---
_main:
        LD      DE, message   ; DE = address of string
print:  CALL    ROMPRINT      ; print it
        ;JP      $             ; infinite loop (stay here)

; --- Data section ---
message:
        DEFM    "ZDRAVO SVETE!"
        DEFB    0             ; zero terminator (end of string)