#include <stdint.h>
#include "zgalaksija.h"



extern unsigned char dot(unsigned int packed_xy) __z88dk_fastcall;
// Elegant macro for use with x, y
#define DOT(x, y) dot(((x) << 8) | (y))

void main() {
    gal_cls();
    

    // Box coordinates
    int x0 = 0;        // left
    int y0 = 0;        // top
    int x1 = 30;   // right (12 chars * 8px + margin)
    int y1 = 8;    // bottom (char height + margin)

    // Top and bottom lines
    for (int x = x0; x <= x1; x++) {
        DOT(x, y0);    // top
        DOT(x, y1);    // bottom
    }

    // Left and right lines
    for (int y = y0; y <= y1; y++) {
        DOT(x0, y);    // left
        DOT(x1, y);    // right
    }

    gal_gotoxy(1, 1);
    gal_puts("ZDRAVO SVETE!");

    while (1) {}  // keep program alive
}