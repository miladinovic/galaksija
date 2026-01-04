# Programiranje Galaksije sa Z88DK

## Uvod

Ovo je kompletan vodič za programiranje računara **Galaksija** koristeći **Z88DK** — razvojni paket koji omogućava pisanje C i ASM programa za Z80 arhitekturu.

Z88DK omogućava prevod C programa u Z80 mašinski kod koji se može izvršavati na stvarnoj Galaksiji ili u emulatorima kao što je JSGalmin.

Inspiracija i dodatne informacije: https://pcpress.rs/c-kompajler-za-galaksiju/

---

## Z88DK: Šta, zašto i kako

**Z88DK** je cross‑compiler i razvojni paket za Z80 računare.  
Za Galaksiju omogućava:

- pisanje programa u C jeziku
- kombinovanje C i ASM koda
- generisanje `.gtp`, `.hex` i `.wav` fajlova
- višestruko brže programe u odnosu na BASIC

U PC Press članku je prikazan primer gde C program popunjava ekran za ~0.28 s,
dok BASIC‑u treba ~17 s (više od 60× sporije).

---

## Instalacija

1. Preuzmi z88dk sa:
   https://github.com/z88dk/z88dk/releases
2. Raspakuj arhivu
3. Dodaj `bin` direktorijum u PATH

Provera instalacije:

```bash
zcc --version
```

---

## Kompajliranje ASM koda

```bash
zcc +gal -create-app program.asm
```

Z88DK automatski:
- postavlja ORG
- dodaje startup kod
- generiše izlazne fajlove za Galaksiju

---

## Primer ASM programa

```asm
ROMPRINT EQU 0x0937

PUBLIC _main

_main:
    LD DE, message
    CALL ROMPRINT
    JP $

message:
    DEFM "ZDRAVO SVETE!"
    DEFB 0
```

---

## Programiranje u C-u

Primer C programa za Galaksiju:

```c
#include "zgalaksija.h"

void main() {
    gal_cls();
    gal_gotoxy(0, 0);
    gal_puts("ZDRAVO SVETE!");
}
```

Kompajliranje:

```bash
zcc +gal -create-app zdravosvete.c
```

---

## Header fajl `zgalaksija.h`

Header sadrži pomoćne funkcije za:
- rad sa ekranom
- pozicioniranje kursora
- direktan pristup memoriji

Koristi se umesto standardne C biblioteke radi uštede memorije.

---

## Kombinacija C i ASM

Z88DK omogućava pozivanje ASM funkcija iz C‑a pomoću `__z88dk_fastcall`.

Primer deklaracije:

```c
extern unsigned char dot(unsigned int packed_xy) __z88dk_fastcall;
#define DOT(x,y) dot(((x)<<8)|(y))
```

Na ovaj način se može:
- koristiti brzi ASM kod
- zadržati čitljivost C programa
- prosleđivati parametri bez stack overheada

---

## Emulatori

Za razvoj se preporučuje korišćenje emulatora:

- JSGalmin
- Galaksija emulatori sa GTP podrškom

Omogućavaju brzo testiranje bez stvarnog hardvera.

---

## Zaključak

Z88DK je trenutno **najpraktičniji alat** za razvoj softvera za Galaksiju:

- znatno brži od BASIC‑a
- fleksibilan (C + ASM)
- kompatibilan sa originalnim hardverom

Idealan je za:
- edukaciju
- retro‑razvoj
- moderne projekte za stari hardver
