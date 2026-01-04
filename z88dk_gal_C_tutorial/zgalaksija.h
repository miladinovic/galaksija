/* Header file with specific GALAKSIJA low-level functions */

#define z80_bpoke(a,b)  (*(unsigned char *)(a) = b)
#define z80_wpoke(a,b)  (*(unsigned int *)(a) = b)
#define z80_lpoke(a,b)  (*(unsigned long *)(a) = b)
#define z80_bpeek(a)    (*(unsigned char *)(a))
#define z80_wpeek(a)    (*(unsigned int *)(a))
#define z80_lpeek(a)    (*(unsigned long *)(a))

#define SCREEN_ADDR 0x2800
#define RND_ADDR 0x2AA7

unsigned char _scr_x, _scr_y;


// Low-level clear the screen and reset internal cursor position
void gal_cls() { 
	int z;
	for (z = 0; z <512; z++) {
		z80_bpoke(SCREEN_ADDR + z, 32);
	}
	_scr_x = 0;
	_scr_y = 0;
}

// Set internal position of cursor for low-level putc and call gotoxy
void gal_gotoxy(char x, char y) {
	_scr_x = x;
	_scr_y = y;
}

// Low-level write character to internal cursor position
void gal_putc(char ch) {
	z80_bpoke(SCREEN_ADDR + (_scr_y << 5) + _scr_x, ch);
	_scr_x++;
	if (_scr_x > 32) {
		_scr_x = 0;
		_scr_y++;
	}
}

// Low-level write string to internal cursor position
int gal_puts (char *str) {
	char ch;
	int len = 0;
	while ((ch = *str) != 0x0) {
		z80_bpoke(SCREEN_ADDR + (_scr_y << 5) + _scr_x, ch);
		str++;
		len++;
		_scr_x++;
		if (_scr_x > 32) {
			_scr_x = 0;
			_scr_y++;
		}
	}
	return len;
}


// Fast single-key reader (returns 0 if no key pressed, or one of 1–4 for directions)
extern unsigned char get_key_fast(void) __z88dk_fastcall;

// Bitmask-based key reader for multi-key support (up to 8 bits)
extern unsigned char get_keys(void) __z88dk_fastcall;

// Bitmask return values
#define KEY_LEFT     0x01  // bit 0
#define KEY_RIGHT    0x02  // bit 1
#define KEY_UP       0x04  // bit 2
#define KEY_DOWN     0x08  // bit 3
#define KEY_Z        0x10  // bit 4
#define KEY_X        0x20  // bit 5
#define KEY_SPACE    0x40  // bit 6

// Diagonal directions (combinations)
#define KEY_UP_LEFT      (KEY_UP   | KEY_LEFT)   // 0x05
#define KEY_UP_RIGHT     (KEY_UP   | KEY_RIGHT)  // 0x06
#define KEY_DOWN_LEFT    (KEY_DOWN | KEY_LEFT)   // 0x09
#define KEY_DOWN_RIGHT   (KEY_DOWN | KEY_RIGHT)  // 0x0A
