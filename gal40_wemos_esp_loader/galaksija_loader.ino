#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <FS.h>
#include <LittleFS.h>
#include <SoftwareSerial.h>

// ===================== WiFi =====================
const char* WIFI_SSID = "_ADD_YOUR_WIFI_SSID_";
const char* WIFI_PASS = "_ADD_YOUR_WIFI_PASSWORD_";

const char* AP_SSID   = "GALAKSIJA-LOADER";
const char* AP_PASS   = "12345678";

static const uint32_t WIFI_CONNECT_TIMEOUT_MS = 15000;

// ===================== Servers =====================
ESP8266WebServer server(80);
WiFiServer tcpServer(2323);
WiFiClient tcpClient;
WiFiClient bbsClient;

// ===================== G40 padding =====================
static const uint8_t G40_PAD = 0x1E; // RS filler

// *** NEW SHORT PROTO / CLASSIC PREAMBLE CONFIG ***
static uint8_t G40_PREAMBLE_ZEROS_TX       = 50;  // ESP->GAL (classic 16-byte)
static const uint8_t G40_PREAMBLE_ZEROS_RX_MIN = 1; // min zeros before FF in classic RX

static uint8_t SHORT_PREAMBLE_ZEROS_TX     = 50;  // ESP->GAL (short)

// Base inter-frame gap (for non-BBS classic)
static const uint16_t INTERFRAME_GAP_MS = 100;

// --- Galaksija YU placeholders in internal pipeline ---
static const uint8_t GAL_YU_S_PLACE   = 0x11; // Š / š
static const uint8_t GAL_YU_CCAR_PLACE= 0x12; // Č / č
static const uint8_t GAL_YU_CAC_PLACE = 0x13; // Ć / ć
static const uint8_t GAL_YU_Z_PLACE   = 0x14; // Ž / ž

// ===================== FS info =====================
struct FsInfoLite {
  uint32_t totalBytes = 0;
  uint32_t usedBytes  = 0;
  uint32_t freeBytes  = 0;
};

FsInfoLite getFsInfoLite() {
  FSInfo info;
  FsInfoLite out;
  if (LittleFS.info(info)) {
    out.totalBytes = info.totalBytes;
    out.usedBytes  = info.usedBytes;
    out.freeBytes  = info.totalBytes - info.usedBytes;
  }
  return out;
}

String fmtBytes(uint32_t b) {
  char buf[32];
  if (b < 1024) snprintf(buf, sizeof(buf), "%lu B", (unsigned long)b);
  else if (b < 1024UL * 1024UL) snprintf(buf, sizeof(buf), "%.1f KB", b / 1024.0);
  else snprintf(buf, sizeof(buf), "%.2f MB", b / (1024.0 * 1024.0));
  return String(buf);
}

// ===================== Galaksija UART pins =====================
static const int8_t GAL_RX_PIN = D5; // ESP RX  <- Galaksija TX
static const int8_t GAL_TX_PIN = D6; // ESP TX  -> Galaksija RX
SoftwareSerial gal;

// ===================== Modes =====================
enum Mode {
  MODE_PROTO   = 0,
  MODE_TCP_RAW = 1,
  MODE_TCP_G40 = 2,
  MODE_BBS_G40 = 3,
  MODE_SOUND   = 4
};
volatile Mode mode = MODE_PROTO;

// ===================== Options =====================
bool optLogSerial         = false;
bool optTcpLineMode       = true;
bool optUppercaseFromBBS  = true;
bool optRawEcho           = false;

// BBS target
const char*  BBS_HOST = "bbs.retrocampus.com";
const uint16_t BBS_PORT = 6561;

// ===================== Flags =====================
volatile bool fsBusy  = false;
volatile bool gtpBusy = false;

String lastUploadedGtpUpper = "";

// ===================== Utils =====================
static inline void tinyYield() { delay(0); yield(); }
void logln(const String& s) { if (optLogSerial) Serial.println(s); }

void logHex(const char* tag, const uint8_t* data, size_t len) {
  if (!optLogSerial) return;
  Serial.print(tag);
  for (size_t i = 0; i < len; i++) Serial.printf(" %02X", data[i]);
  Serial.println();
}
void logAscii16(const char* tag, const uint8_t* body16) {
  if (!optLogSerial) return;
  Serial.print(tag);
  Serial.print(" '");
  for (int i=0;i<16;i++){
    uint8_t b=body16[i];
    if (b=='\r') Serial.print("\\r");
    else if (b=='\n') Serial.print("\\n");
    else if (b=='\b') Serial.print("\\b");
    else if (b>=32 && b<=126) Serial.write((char)b);
    else Serial.printf("\\x%02X", b);
  }
  Serial.println("'");
}

// ===================== Filename sanitize =====================
String galfname(String s) {
  s.toUpperCase();
  s.replace(" ", "");
  if (s.endsWith(".GTP")) s = s.substring(0, s.length() - 4);

  String out;
  const String allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.";
  for (size_t i = 0; i < s.length(); i++) {
    char c = s[i];
    if (allowed.indexOf(c) >= 0) out += c;
  }
  if (out.length() > 14) out = out.substring(0, 14);
  return out;
}

bool readExact(Stream& st, uint8_t* buf, size_t n, uint32_t timeoutMs) {
  size_t got = 0;
  uint32_t t0 = millis();
  while (got < n && (millis() - t0) < timeoutMs) {
    if (st.available()) {
      int b = st.read();
      if (b >= 0) buf[got++] = (uint8_t)b;
    } else {
      tinyYield();
    }
  }
  return got == n;
}

String readName14(Stream& st, uint32_t timeoutMs = 2000) {
  uint8_t buf[14];
  if (!readExact(st, buf, 14, timeoutMs)) return "";

  String fn;
  for (int i = 0; i < 14; i++) {
    if (buf[i] > 32 && buf[i] < 127) fn += char(buf[i]);
  }
  fn.trim();
  if (fn.endsWith("GTP")) fn = fn.substring(0, fn.length() - 3);
  fn = galfname(fn);
  return fn;
}

void galWrite(const uint8_t* data, size_t len) {
  gal.write(data, len);
  gal.flush();
  tinyYield();
}
void galWriteByte(uint8_t b) {
  gal.write(b);
  gal.flush();
  tinyYield();
}

// Case-insensitive file lookup
bool findFileCaseInsensitive(const String& upperNoExt, String& outPath) {
  String want = "/" + upperNoExt + ".gtp";
  if (LittleFS.exists(want)) { outPath = want; return true; }

  Dir d = LittleFS.openDir("/");
  while (d.next()) {
    String f = d.fileName();
    String up = f; up.toUpperCase();
    if (up == want) { outPath = f; return true; }
  }
  return false;
}

// ===================== OLD#/SAVE# protocol =====================
bool sendGTPFromLittleFS(const String& fsPath, const String& reqNameUpper) {
  File f = LittleFS.open(fsPath, "r");
  if (!f) return false;

  uint32_t basePos = 0;
  int b0 = f.read();
  if (b0 < 0) { f.close(); return false; }
  if ((uint8_t)b0 == 0x10) {
    int nameLen = f.read();
    if (nameLen < 0) { f.close(); return false; }
    basePos = (uint32_t)nameLen + 5;
    f.seek(basePos, SeekSet);
  } else {
    f.seek(0, SeekSet);
    basePos = 0;
  }

  uint32_t stdLen = f.size() - basePos;
  if (stdLen < 16) { f.close(); return false; }

  uint8_t hdr[14];
  f.seek(basePos, SeekSet);
  if (f.read(hdr, 14) != 14) { f.close(); return false; }
  if (hdr[5] != 0xA5) { f.close(); return false; }

  uint16_t word1 = (uint16_t)hdr[6] | ((uint16_t)hdr[7] << 8);
  uint16_t word2 = (uint16_t)hdr[8] | ((uint16_t)hdr[9] << 8);

  uint32_t calcLen = (uint32_t)(word2 - word1) + 11;
  uint32_t endExclusive = basePos + ((calcLen == stdLen) ? (stdLen - 1) : (stdLen - 2));
  uint32_t startPos = basePos + 6;

  const uint8_t head6[6] = {0x00,0x00,0x00,0x00,0x00,0xA5};
  galWrite(head6, 6);

  uint32_t csum = 0xA5;

  String tn = galfname(reqNameUpper);
  uint8_t name14[14];
  memset(name14, 0, sizeof(name14));
  for (size_t i=0; i<tn.length() && i<14; i++) name14[i] = (uint8_t)tn[i];

  galWrite(name14, 14);
  for (int i=0; i<14; i++) csum += name14[i];

  f.seek(startPos, SeekSet);
  uint8_t buf[128];
  uint32_t pos = startPos;
  while (pos < endExclusive) {
    size_t want = sizeof(buf);
    if (pos + want > endExclusive) want = endExclusive - pos;
    int n = f.read(buf, want);
    if (n <= 0) break;
    galWrite(buf, (size_t)n);
    for (int i=0; i<n; i++) csum += buf[i];
    pos += (uint32_t)n;
    tinyYield();
  }

  galWriteByte(0x20);
  csum += 0x20;
  galWriteByte((uint8_t)(csum & 0xFF));
  f.close();

  const uint8_t okrep[4] = {0xCC,0xDD,0xEE,0xF0};
  galWrite(okrep, 4);
  return true;
}

bool receiveGTPToLittleFS(const String& reqNameUpper) {
  const uint32_t PTR_TIMEOUT_MS  = 5000;
  const uint32_t DATA_TIMEOUT_MS = 5000;

  uint8_t pointers[4];
  if (!readExact(gal, pointers, 4, PTR_TIMEOUT_MS)) {
    logln("[SAVE] timeout reading pointers");
    return false;
  }

  uint16_t fstart = (uint16_t)pointers[0] | ((uint16_t)pointers[1] << 8);
  uint16_t fend   = (uint16_t)pointers[2] | ((uint16_t)pointers[3] << 8);

  if (fend <= fstart) {
    logln("[SAVE] invalid length (fend<=fstart)");
    return false;
  }

  uint32_t flen = (uint32_t)(fend - fstart);
  if (flen == 0 || flen > 65535UL) {
    logln("[SAVE] crazy length, abort");
    return false;
  }

  String path = "/" + reqNameUpper + ".gtp";

  fsBusy = true;
  File tmp = LittleFS.open(path, "w");
  if (!tmp) {
    fsBusy = false;
    logln("[SAVE] cannot open file for write");
    return false;
  }

  uint16_t xlen = (uint16_t)(flen + 7);
  tmp.write((uint8_t)0x00);
  tmp.write((uint8_t)(xlen & 0xFF));
  tmp.write((uint8_t)((xlen >> 8) & 0xFF));
  tmp.write((uint8_t)0x00);
  tmp.write((uint8_t)0x00);
  tmp.write((uint8_t)0xA5);
  tmp.write(pointers, 4);

  uint32_t sumData = 0;
  uint8_t buf[128];
  uint32_t remaining = flen;

  while (remaining > 0) {
    size_t want = (remaining > sizeof(buf)) ? sizeof(buf) : (size_t)remaining;

    size_t got  = 0;
    uint32_t t0 = millis();
    while (got < want && (millis() - t0) < DATA_TIMEOUT_MS) {
      if (gal.available()) {
        int x = gal.read();
        if (x >= 0) buf[got++] = (uint8_t)x;
      } else {
        tinyYield();
      }
    }

    if (got == 0) {
      logln("[SAVE] data timeout, abort");
      tmp.close();
      fsBusy = false;
      return false;
    }

    tmp.write(buf, got);
    for (size_t i=0; i<got; i++) sumData += buf[i];
    remaining -= got;
    tinyYield();
  }

  uint8_t rxChk = 0;
  uint32_t t1 = millis();
  while (!gal.available() && (millis() - t1) < 2000) {
    tinyYield();
  }
  if (gal.available()) {
    int c = gal.read();
    if (c >= 0) rxChk = (uint8_t)c;
  }
  (void)rxChk;

  uint32_t checksumx = 0xA5;
  checksumx += (uint32_t)pointers[0] + pointers[1] + pointers[2] + pointers[3];
  checksumx += sumData;
  uint8_t fileChk = (uint8_t)(255 - (checksumx & 0xFF));

  tmp.write(fileChk);
  tmp.write((uint8_t)0x00);
  tmp.close();
  fsBusy = false;

  lastUploadedGtpUpper = reqNameUpper;

  const uint8_t ok[4] = {0xCC,0xDD,0xEE,0xF0};
  galWrite(ok, 4);

  logln("[SAVE] completed OK");
  return true;
}

// ===================== G40 parsers & senders =====================

// *** SHORT PROTO TOGGLE ***
bool useShortProto = false;

// Classic 16-byte frame parser for D6 protocol
struct FrameParser {
  uint8_t state = 0;      // 0=preamble,2=expect D6,3=body,4=checksum
  uint8_t body[16];
  uint8_t idx = 0;
  uint8_t zeroCount = 0;
} fp;

// Short protocol parser for up to 48-byte payload
struct ShortParser {
  uint8_t state = 0;   // 0=preamble,1=FF,2=payload,3=checksum
  uint8_t payload[48];
  uint8_t len = 0;
} sp;

bool parseG40FrameByte(uint8_t b, uint8_t outBody[16]) {
  switch (fp.state) {
    case 0: // preamble zeros / wait FF after zeros
      if (b == 0x00) {
        if (fp.zeroCount < 255) fp.zeroCount++;
      } else if (b == 0xFF && fp.zeroCount >= G40_PREAMBLE_ZEROS_RX_MIN) {
        fp.state = 2; // expect D6
      } else {
        fp.zeroCount = 0;
      }
      break;

    case 2: // expect D6
      if (b == 0xD6) {
        fp.state = 3;
        fp.idx   = 0;
      } else if (b == 0xFF) {
        // still waiting for D6
      } else {
        fp.state = 0;
        fp.zeroCount = 0;
      }
      break;

    case 3: // body
      fp.body[fp.idx++] = b;
      if (fp.idx >= 16) fp.state = 4;
      break;

    case 4: { // checksum
      uint8_t chk = 0;
      for (int i = 0; i < 16; i++) chk = (uint8_t)(chk + fp.body[i]);
      fp.state = 0;
      fp.zeroCount = 0;
      if (chk != b) return false;
      memcpy(outBody, fp.body, 16);
      return true;
    }
  }
  return false;
}

bool parseShortFrameByte(uint8_t b, uint8_t *outPayload, uint8_t &outLen) {
  switch (sp.state) {
    case 0: // preamble zeros
      if (b == 0x00) {
        // just stay in preamble
      } else if (b == 0xFF) {
        sp.state = 1; // expect D6
      } else {
        // ignore noise
      }
      break;

    case 1: // expect D6
      if (b == 0xD6) {
        sp.state = 2;
        sp.len   = 0;
      } else if (b == 0xFF) {
        // still waiting for D6
      } else {
        sp.state = 0;
      }
      break;

    case 2: // payload until 0x04
      if (b == 0x04) {
        sp.state = 3; // next is checksum
      } else {
        if (sp.len < sizeof(sp.payload)) {
          sp.payload[sp.len++] = b;
        }
      }
      break;

    case 3: { // checksum
      uint8_t chk = 0x04;
      for (uint8_t i = 0; i < sp.len; i++) chk = (uint8_t)(chk + sp.payload[i]);
      sp.state = 0;
      if (chk != b) {
        sp.len = 0;
        return false;
      }
      memcpy(outPayload, sp.payload, sp.len);
      outLen = sp.len;
      sp.len = 0;
      return true;
    }
  }
  return false;
}

// Classic 16-byte sender with adjustable preamble
uint32_t lastFrameToGalMs = 0;

void sendFrameBody(const uint8_t body16[16]) {
  if (optLogSerial) {
    Serial.println("[G40 ESP->GAL]");
    logAscii16("[BODY]", body16);
    logHex("[HEX ]", body16, 16);
  }

  for (uint8_t i = 0; i < G40_PREAMBLE_ZEROS_TX; i++) {
    gal.write((uint8_t)0x00);
  }

  gal.write((uint8_t)0xFF);
  gal.write((uint8_t)0xD6);

  uint8_t chk = 0;
  for (int i = 0; i < 16; i++) {
    uint8_t b = body16[i];
    gal.write(b);
    chk = (uint8_t)(chk + b);
  }
  gal.write(chk);
  gal.flush();

  lastFrameToGalMs = millis();

  uint16_t gap = INTERFRAME_GAP_MS;
  if (mode == MODE_TCP_G40 || mode == MODE_BBS_G40) {
    gap = gap;
  }
  delay(gap);
}

void sendFrameText16(const String& s) {
  uint8_t body[16];
  memset(body, G40_PAD, 16);
  for (size_t i=0;i<s.length() && i<16;i++) body[i] = (uint8_t)s[i];
  sendFrameBody(body);
}

// Short sender
void sendShortFrame(const uint8_t *payload, uint8_t len) {
  if (optLogSerial) {
    Serial.println("[SHORT ESP->GAL]");
    Serial.print("[PAYL] '");
    for (uint8_t i = 0; i < len; i++) {
      uint8_t b = payload[i];
      if (b == '\r') Serial.print("<r>");
      if (b == 4) Serial.print("\\r");
      else if (b >= 32 && b <= 126) Serial.write((char)b);
      else Serial.printf("\\x%02X", b);
    }
    Serial.println("'");
    Serial.print("\\r HEX ");
    for (uint8_t i = 0; i < len; i++) {
      uint8_t b = payload[i];
      Serial.printf("\\x%02X", b);
    }

  }

  for (uint8_t i = 0; i < SHORT_PREAMBLE_ZEROS_TX; i++) {
    gal.write((uint8_t)0x00);
  }

  gal.write((uint8_t)0xFF);
  gal.write((uint8_t)0xD6);

  uint8_t chk = 0x04;
  for (uint8_t i = 0; i < len; i++) {
    gal.write(payload[i]);
    chk = (uint8_t)(chk + payload[i]);
  }

  gal.write((uint8_t)0x04);
  gal.write(chk);
  gal.flush();
}

// ===================== TCP accept helper =====================
void acceptTcpClient() {
  static bool wasConnected = false;

  if (tcpServer.hasClient()) {
    if (!tcpClient || !tcpClient.connected()) {
      tcpClient = tcpServer.accept();
      tcpClient.setNoDelay(true);
      if (optLogSerial) Serial.println("[TCP] client connected");
      wasConnected = true;
    } else {
      WiFiClient extra = tcpServer.accept();
      extra.stop();
    }
  }

  bool now = (tcpClient && tcpClient.connected());
  if (wasConnected && !now) {
    if (optLogSerial) Serial.println("[TCP] client disconnected");
    wasConnected = false;
  }
}

// ===================== Stop remotes =====================
void stopRemoteConnections() {
  if (tcpClient) tcpClient.stop();
  if (bbsClient) bbsClient.stop();
}

// ===================== TELNET minimal IAC =====================
struct TelnetState {
  uint8_t st = 0;
  uint8_t cmd = 0;
} tn;

void pushRemoteByte(uint8_t c, bool doUppercase);

// BBS prompt timing
uint32_t lastBbsRxMs    = 0;
bool     lastBbsEnqSent = false;

void telnetFeed(uint8_t b) {
  if (tn.st == 0) {
    if (b == 0xFF) { tn.st = 1; return; }
    if (b == 0x00) { tn.st = 1; return; }
    pushRemoteByte(b, optUppercaseFromBBS);
    return;
  }
  if (tn.st == 1) {
    if (b == 0xFF) { tn.st = 0; pushRemoteByte(0xFF, false); return; }
    tn.cmd = b;
    tn.st = 2;
    return;
  }
  if (tn.st == 2) {
    uint8_t reply[3] = {0xFF, 0x00, b};
    if (tn.cmd == 0xFD) reply[1] = 0xFC;
    else if (tn.cmd == 0xFB) reply[1] = 0xFE;
    else { tn.st = 0; return; }
    if (bbsClient && bbsClient.connected()) bbsClient.write(reply, 3);
    tn.st = 0;
    return;
  }
  tn.st = 0;
}

// ===================== BBS connect =====================
bool ensureBbsConnected() {
  if (bbsClient && bbsClient.connected()) return true;
  bbsClient.stop();
  logln("[BBS] connecting...");
  if (!bbsClient.connect(BBS_HOST, BBS_PORT)) {
    logln("[BBS] connect FAIL");
    return false;
  }
  bbsClient.setNoDelay(true);
  tn.st = 0;
  logln("[BBS] connected");
  lastBbsRxMs = millis();
  lastBbsEnqSent = false;
  return true;
}

// ===================== FIFO remote->Gal =====================
static const uint16_t FIFO_SZ = 512;
uint8_t fifo[FIFO_SZ];
volatile uint16_t fHead=0, fTail=0;

bool fifoPush(uint8_t b) {
  uint16_t n = (uint16_t)((fHead + 1) % FIFO_SZ);
  if (n == fTail) return false;
  fifo[fHead] = b;
  fHead = n;
  return true;
}
bool fifoPop(uint8_t &b) {
  if (fTail == fHead) return false;
  b = fifo[fTail];
  fTail = (uint16_t)((fTail + 1) % FIFO_SZ);
  return true;
}
uint16_t fifoCount() {
  if (fHead >= fTail) return (uint16_t)(fHead - fTail);
  return (uint16_t)(FIFO_SZ - (fTail - fHead));
}

uint8_t mapBbsCharToGal(uint8_t c) {
  if (c == 0x0D) return 0x0D;
  if (c == 0x01) return 0x01;
  if (c == 0x1E) return 0x1E;
  if (c == 0x0C) return 0x01;
  if (c == 0x0A) return 0x00;
  if (c == 0x00) return 0x7F;

  if (c == GAL_YU_S_PLACE)    return 0x5E;
  if (c == GAL_YU_CCAR_PLACE) return 0x5B;
  if (c == GAL_YU_CAC_PLACE)  return 0x5C;
  if (c == GAL_YU_Z_PLACE)    return 0x5D;

  if (c >= 0x20 && c <= 0x7E) return c;

  return 0xBF;
}

void pushRemoteByte(uint8_t c, bool doUppercase) {
  if (c == 0x0A) return;

  if (c == '[')       c = '(';
  else if (c == ']')  c = ')';
  else if (c == '\\') c = '/';
  else if (c == '\'') c = '"';

  if (doUppercase && c >= 'a' && c <= 'z') {
    c = (uint8_t)(c - 32);
  }

  c = mapBbsCharToGal(c);
  if (c == 0x00) return;
  fifoPush(c);
}

// ===================== G40 ACK / NAK (classic) =====================
static const uint16_t ACK_TIMEOUT_MS = 300;
static const uint8_t  ACK_MAX_RETRY  = 10;

struct G40TxState {
  bool waiting = false;
  uint8_t lastBody[16];
  uint32_t lastSendMs = 0;
  uint8_t retries = 0;
} g40tx;

inline bool isAckBody(const uint8_t body16[16]) {
  return body16[0] == 0x06;
}
inline bool isNakBody(const uint8_t body16[16]) {
  return body16[0] == 0x15;
}

void sendBodyWithAck(const uint8_t body[16]) {
  memcpy(g40tx.lastBody, body, 16);
  g40tx.waiting = true;
  g40tx.retries = 0;
  g40tx.lastSendMs = millis();
  sendFrameBody(body);
}

void g40TxTick() {
  if (mode != MODE_TCP_G40 && mode != MODE_BBS_G40) return;
  if (useShortProto) return; // short mode uses separate engine

  if (g40tx.waiting) {
    if (millis() - g40tx.lastSendMs >= ACK_TIMEOUT_MS) {
      if (g40tx.retries >= ACK_MAX_RETRY) {
        if (optLogSerial) Serial.println("[G40 TX] ACK timeout -> drop");
        g40tx.waiting = false;
        g40tx.retries = 0;
      } else {
        g40tx.retries++;
        g40tx.lastSendMs = millis();
        if (optLogSerial) Serial.println("[G40 TX] resend");
        sendFrameBody(g40tx.lastBody);
      }
    }
    return;
  }

  if (fifoCount() == 0) return;

  uint8_t body[16];
  memset(body, G40_PAD, 16);

  uint8_t n = 0;
  while (n < 16) {
    uint8_t c;
    if (!fifoPop(c)) break;
    body[n++] = c;
    if (c == '\r') break;
  }

  sendBodyWithAck(body);
}

// ===================== Short ACK / NAK TX state =====================
struct ShortTxState {
  bool     waiting = false;
  uint8_t  lastPayload[48];
  uint8_t  lastLen = 0;
  uint8_t  retries = 0;
  uint32_t lastMs  = 0;
} shortTx;

static const uint16_t SHORT_ACK_TIMEOUT_MS = 300;
static const uint8_t  SHORT_ACK_MAX_RETRY  = 10;

void sendShortPayloadWithAck(const uint8_t *payload, uint8_t len) {
  if (len == 0) return;
  if (len > 48) len = 48;

  memcpy(shortTx.lastPayload, payload, len);
  shortTx.lastLen = len;
  shortTx.waiting = true;
  shortTx.retries = 0;
  shortTx.lastMs  = millis();

  sendShortFrame(shortTx.lastPayload, shortTx.lastLen);
}

void shortTxTick() {
  if (!useShortProto) return;
  if (mode != MODE_TCP_G40 && mode != MODE_BBS_G40) return;

  if (shortTx.waiting) {
    uint32_t now = millis();
    if (now - shortTx.lastMs >= SHORT_ACK_TIMEOUT_MS) {
      if (shortTx.retries >= SHORT_ACK_MAX_RETRY) {
        if (optLogSerial) Serial.println("[SHORT TX] ACK timeout drop");
        shortTx.waiting = false;
      } else {
        shortTx.retries++;
        shortTx.lastMs = now;
        if (optLogSerial) Serial.println("[SHORT TX] resend");
        sendShortFrame(shortTx.lastPayload, shortTx.lastLen);
      }
    }
    return;
  }

  if (fifoCount() == 0) return;

  uint8_t pay[48];
  uint8_t len = 0;
  bool sawCR  = false;

  while (len < 48) {
    uint8_t c;
    if (!fifoPop(c)) break;
    pay[len++] = c;
    if (c == '\r') {
      sawCR = true;
      break;
    }
  }
  if (len == 0) return;

  sendShortPayloadWithAck(pay, len);
}

// ===================== SYN heartbeat (classic only) =====================
static const uint32_t SYN_INTERVAL_MS = 500000;

void synTick() {
  return;
  if (useShortProto) return; // disabled in short mode
  if (mode != MODE_TCP_G40 && mode != MODE_BBS_G40) return;
  if (g40tx.waiting) return;

  uint32_t now = millis();
  if (now - lastFrameToGalMs < SYN_INTERVAL_MS) return;

  uint8_t synBody[16];
  synBody[0] = 0x16;
  for (int i=1;i<16;i++) synBody[i]=G40_PAD;

  if (optLogSerial) Serial.println("[SYN] sending heartbeat");
  sendFrameBody(synBody);
}

// ===================== LIST helper =====================
void handleListCommand(const String& cmd) {
  String u = cmd;
  u.toUpperCase();

  String pattern = "";
  if (u.length() > 8) {
    pattern = u.substring(8);
    pattern.trim();
    while (pattern.endsWith("_")) {
      pattern.remove(pattern.length() - 1);
    }
  }

  auto matches = [&](const String& base)->bool {
    if (pattern.length() == 0) return true;
    String up = base;
    up.toUpperCase();
    return up.indexOf(pattern) >= 0;
  };

  if (lastUploadedGtpUpper.length() > 0 && matches(lastUploadedGtpUpper)) {
    String path = "/" + lastUploadedGtpUpper + ".gtp";
    if (LittleFS.exists(path)) {
      String name16 = lastUploadedGtpUpper;
      if (name16.length() > 16) name16 = name16.substring(0, 16);
      sendFrameText16(name16);
    }
  }

  Dir d = LittleFS.openDir("/");
  while (d.next()) {
    String fn = d.fileName();
    if (!fn.endsWith(".gtp") && !fn.endsWith(".GTP")) continue;

    String base = fn;
    int dot = base.lastIndexOf('.');
    if (dot >= 0) base = base.substring(0, dot);
    base = galfname(base);

    if (base == lastUploadedGtpUpper) continue;
    if (!matches(base)) continue;

    String name16 = base;
    if (name16.length() > 16) name16 = name16.substring(0, 16);
    sendFrameText16(name16);
  }

  sendFrameText16("LIST DONE");
}

// ===================== SHORT RX handler from Gal =====================
void handleShortPayloadFromGal(const uint8_t *payload, uint8_t len) {
  if (len == 0) return;

  uint8_t first = payload[0];

  if (optLogSerial) {
    Serial.println("[SHORT GAL->ESP]");
    Serial.print("[PAYL] '");
    for (uint8_t i=0;i<len;i++) {
      uint8_t b = payload[i];
      if (b == '\r') Serial.print("<R>");
      if (b == 4) Serial.print("<end>\\r");
      else if (b >= 32 && b <= 126) Serial.write((char)b);
      else Serial.printf("\\x%02X", b);
    }
    Serial.println("'");
    for (uint8_t i=0;i<len;i++) {
      uint8_t b = payload[i];
      if (b == '\r') Serial.print("<R>");
      if (b == 4) Serial.print("<end>\\r");
      Serial.printf("\\x%02X", b);
    }
  }

  // ACK from Gal
  if (len == 1 && first == 0x06) {
    if (optLogSerial) Serial.println("[SHORT RX] ACK 0x06");
    shortTx.waiting = false;
    shortTx.retries = 0;
    return;
  }

  // NAK from Gal
  if (len == 1 && first == 0x15) {
    if (optLogSerial) Serial.println("[SHORT RX] NAK 0x15");
    if (shortTx.retries >= SHORT_ACK_MAX_RETRY) {
      shortTx.waiting = false;
      return;
    }
    shortTx.retries++;
    shortTx.lastMs = millis();
    sendShortFrame(shortTx.lastPayload, shortTx.lastLen);
    return;
  }

  // Data from Gal (user input) – we ACK it here
  {
    uint8_t ackPay[1] = { 0x06 };
    sendShortFrame(ackPay, 1);
  }

  if (mode == MODE_BBS_G40) {
    if (!ensureBbsConnected()) return;

    char line[64];
    uint8_t llen = 0;
    bool sawCR = false;

    for (uint8_t i=0;i<len;i++) {
      uint8_t c = payload[i];
      if (c == G40_PAD || c == 0x00) continue;
      if (c == '\r') {
        sawCR = true;
        break;
      }
      if (c >= 'a' && c <= 'z') c = (uint8_t)(c - 32);
      if (llen < sizeof(line) - 2) line[llen++] = (char)c;
    }

    if (llen > 0) {
      bbsClient.write((uint8_t*)line, llen);
      if (optLogSerial) {
        Serial.print("--------------->[BBS<-GAL] '");
        for (uint8_t i=0;i<llen;i++) Serial.write(line[i]);
        Serial.println("'");
      }
    }
    if (sawCR) {
      //bbsClient.write('\r');
      bbsClient.write('\n');
      if (optLogSerial) Serial.println("--------------->[BBS<-GAL] <CRLF>");
      lastBbsEnqSent = false;
    }
    bbsClient.flush();
  } else if (mode == MODE_TCP_G40) {
    acceptTcpClient();
    if (!(tcpClient && tcpClient.connected())) return;

    bool sawCR = false;
    for (uint8_t i=0;i<len;i++) {
      uint8_t c = payload[i];
      if (c == G40_PAD || c == 0x00) continue;
      if (c == '\r') {
        sawCR = true;
        tcpClient.write('\n');
        continue;
      }
      if (c >= 'a' && c <= 'z') c = (uint8_t)(c - 32);
      tcpClient.write(&c, 1);
    }
    tcpClient.flush();
  }
}

// ===================== Handle frames from Gal (classic 16-byte) =====================
void handleFrameFromGalClassic(const uint8_t body16[16]) {
  if (optLogSerial) {
    Serial.println("[************G40 GAL->ESP************]");
    logAscii16("[BODY]", body16);
    logHex("[HEX ]", body16, 16);
  }

  // Detect 0xD7 as "short protocol ON" control in G40 modes
  if (!useShortProto && (mode == MODE_BBS_G40 || mode == MODE_TCP_G40)) {
    bool seenNonPad = false;
    bool onlyD7 = false;
    for (int i = 0; i < 16; i++) {
      uint8_t c = body16[i];
      if (c == 0x00 || c == G40_PAD) continue;
      if (!seenNonPad) {
        seenNonPad = true;
        onlyD7 = (c == 0xD7);
      } else {
        onlyD7 = false;
        break;
      }
    }
    if (onlyD7 && seenNonPad) {
      useShortProto = true;
      if (optLogSerial) Serial.println("[SHORT] Activated by 0xD7 frame");
      return;
    }
  }

  // Classic ACK/NAK for G40 ACK engine
  if (isAckBody(body16)) {
    if (g40tx.waiting) {
      if (optLogSerial) Serial.println("[G40 RX] ACK (0x06) OK");
      g40tx.waiting = false;
      g40tx.retries = 0;
    }
    return;
  }
  if (isNakBody(body16)) {
    if (g40tx.waiting) {
      if (optLogSerial) Serial.println("[G40 RX] NAK (0x15) -> immediate resend");
      if (g40tx.retries >= ACK_MAX_RETRY) {
        if (optLogSerial) Serial.println("[G40 RX] NAK retry limit reached, dropping");
        g40tx.waiting = false;
      } else {
        g40tx.retries++;
        g40tx.lastSendMs = millis();
        sendFrameBody(g40tx.lastBody);
      }
    }
    return;
  }

  String cmd;
cmd.reserve(16);
for (int i = 0; i < 16; i++) {
  cmd += (char)body16[i];
}
  cmd.trim();
  String u = cmd; u.toUpperCase();

  if (u == "__PROTO__") {
    mode = MODE_PROTO;
    stopRemoteConnections();
    useShortProto = false;
    sendFrameText16("PROTO OK");
    return;
  }
  if (u == "__SERIAL__") {
    mode = MODE_TCP_RAW;
    stopRemoteConnections();
    useShortProto = false;
    sendFrameText16("RAW OK");
    return;
  }
  if (u == "__SERIAL_B__") {
    mode = MODE_TCP_G40;
    stopRemoteConnections();
    g40tx.waiting = false; g40tx.retries = 0;
    useShortProto = false;          // start in classic; 0xD7 switches to short
    sendFrameText16("G40 OK");
    return;
  }
  if (u == "__BBS_SHORT__") {
    mode = MODE_BBS_G40;      // same BBS mode as before
    stopRemoteConnections();
    g40tx.waiting = false;
    g40tx.retries = 0;
    useShortProto = true;    // <-- new boolean flag
    bool ok = ensureBbsConnected();
    sendFrameText16(ok ? "BBS SHORT OK" : "BBS SHORT FAIL");
    return;
}
  if (u == "__BBS__") {
    mode = MODE_BBS_G40;
    stopRemoteConnections();
    g40tx.waiting = false; g40tx.retries = 0;
    useShortProto = false;          // start in classic; 0xD7 switches to short
    bool ok = ensureBbsConnected();
    sendFrameText16(ok ? "BBS OK" : "BBS FAIL");
    lastBbsEnqSent = false;
    return;
  }
  if (u == "__SOUND__") {
    mode = MODE_SOUND;
    stopRemoteConnections();
    g40tx.waiting = false; g40tx.retries = 0;
    useShortProto = false;
    sendFrameText16("SOUND OK");
    return;
  }
  if (u.startsWith("__LIST__")) {
    handleListCommand(cmd);
    return;
  }

  if (mode == MODE_SOUND) {
    return;
  }

  if (mode == MODE_TCP_G40) {
    acceptTcpClient();
    if (tcpClient && tcpClient.connected()) {
      bool sawCR = false;
      for (int i = 0; i < 16; i++) {
        uint8_t c = body16[i];
        if (sawCR) continue;
        if (c == 0x00 || c == G40_PAD) continue;
        if (c == 0x0D) {
          tcpClient.write('\n');
          tcpClient.flush();
          sawCR = true;
          continue;
        }
        if (c >= 'a' && c <= 'z') c = (uint8_t)(c - 32);
        tcpClient.write(c);
      }
      tcpClient.flush();
    }
    return;
  }

  if (mode == MODE_BBS_G40) {
    if (ensureBbsConnected()) {
      char line[32];
      uint8_t len = 0;
      bool sawCR = false;

      for (int i = 0; i < 16; i++) {
        uint8_t c = body16[i];
        if (sawCR) continue;
        if (c == 0x00 || c == G40_PAD) continue;

        if (c == 0x0D) {
          sawCR = true;
          break;
        }

        if (c >= 'a' && c <= 'z') c = (uint8_t)(c - 32);

        if (len < sizeof(line) - 2) {
          line[len++] = (char)c;
        }
      }

      if (len > 0) {
        bbsClient.write((uint8_t*)line, len);
        if (optLogSerial) {
          Serial.print("--------------->[BBS<-GAL] '");
          for (uint8_t i = 0; i < len; i++) Serial.write(line[i]);
          Serial.println("'");
        }
      }

      if (sawCR) {
        bbsClient.write('\r');
        bbsClient.write('\n');
        if (optLogSerial) Serial.println("--------------->[BBS<-GAL] <CRLF>");
        lastBbsEnqSent = false;
      }

      bbsClient.flush();
    }
    return;
  }

  // other modes ignore
}

// ===================== Galaksija IO (PROTO + G40) =====================
void handleGalaksijaIO() {
  if (mode == MODE_TCP_RAW) return;

  static uint8_t b16[16];
  static uint8_t shortBuf[48];
  static uint8_t shortLen = 0;

  while (gal.available()) {
    uint8_t b = (uint8_t)gal.read();

    if (!gtpBusy) {
      if (!useShortProto) {
        if (parseG40FrameByte(b, b16)) {
          handleFrameFromGalClassic(b16);
          continue;
        }
      } else {
        if (parseShortFrameByte(b, shortBuf, shortLen)) {
          handleShortPayloadFromGal(shortBuf, shortLen);
          continue;
        }
      }
    }

    if (mode != MODE_PROTO) continue;

    if (b == 0xA3) {
      gtpBusy = true;
      String req = readName14(gal, 5000);

      if (req.length() == 0) {
        if (lastUploadedGtpUpper.length() == 0) {
          const uint8_t nofile[4] = {0xCC,0xDD,0xEE,0xF2};
          galWrite(nofile, 4);
          gtpBusy = false;
          return;
        }
        req = lastUploadedGtpUpper;
      }

      String fsPath;
      if (!findFileCaseInsensitive(req, fsPath)) {
        const uint8_t nofile[4] = {0xCC,0xDD,0xEE,0xF2};
        galWrite(nofile, 4);
        gtpBusy = false;
        return;
      }

      const uint8_t ok[4] = {0xCC,0xDD,0xEE,0xF0};
      galWrite(ok, 4);

      if (!sendGTPFromLittleFS(fsPath, req)) {
        const uint8_t badfmt[4] = {0xCC,0xDD,0xEE,0xF5};
        galWrite(badfmt, 4);
      }
      gtpBusy = false;
      return;
    }

    if (b == 0xC7) {
      gtpBusy = true;
      String req = readName14(gal, 5000);
      if (req.length() == 0) { gtpBusy = false; return; }

      const uint8_t ok[4] = {0xCC,0xDD,0xEE,0xF0};
      galWrite(ok, 4);

      if (!receiveGTPToLittleFS(req)) {
        const uint8_t err[4] = {0xCC,0xDD,0xEE,0xF3};
        galWrite(err, 4);
      }
      gtpBusy = false;
      return;
    }
  }
}

// ===================== RAW bridge + ACK =====================
static const uint16_t RAW_ACK_TIMEOUT_MS = 100;
static const uint16_t RAW_ACK_MAX_RETRY  = 1000;

struct RawEchoTxState {
  bool     waiting      = false;
  uint8_t  last         = 0;
  uint32_t lastMs       = 0;
  uint16_t retries      = 0;
  bool     sendNullNext = false;
} rawtx;

void rawEchoAckTick() {
  if (mode != MODE_TCP_RAW) return;
  if (!optRawEcho) return;
  if (!rawtx.waiting) return;

  uint32_t now = millis();
  if (now - rawtx.lastMs < RAW_ACK_TIMEOUT_MS) return;

  if (rawtx.retries >= RAW_ACK_MAX_RETRY) {
    if (optLogSerial) Serial.println("[RAW ECHO] ACK timeout, giving up");
    rawtx.waiting = false;
    return;
  }

  rawtx.retries++;
  rawtx.lastMs = now;

  uint8_t outByte;
  if (rawtx.sendNullNext) {
    outByte = 0x00;
    rawtx.sendNullNext = false;
  } else {
    outByte = rawtx.last;
    rawtx.sendNullNext = true;
  }

  gal.write(outByte);
  gal.flush();

  if (optLogSerial) {
    logHex("[RAW ECHO RESEND ESP->GAL]", &outByte, 1);
  }
}

void handleTcpRawBridge() {
  if (mode != MODE_TCP_RAW) return;
  acceptTcpClient();

  uint8_t buf[128];

  if (tcpClient && tcpClient.connected()) {
    while (tcpClient.available()) {
      int n = tcpClient.read(buf, sizeof(buf));
      if (n <= 0) break;
      gal.write(buf, (size_t)n);
      gal.flush();
      if (optLogSerial) logHex("[RAW TCP->GAL]", buf, (size_t)n);
      delay(2);
    }
  }

  while (gal.available()) {
    int bi = gal.read();
    if (bi < 0) break;
    uint8_t b = (uint8_t)bi;

    if (optRawEcho && rawtx.waiting && b == 0x06) {
      if (optLogSerial) Serial.println("[RAW GAL->ESP] ACK 0x06");
      rawtx.waiting = false;
      rawtx.retries = 0;
      rawtx.sendNullNext = false;
      continue;
    }

    if (optLogSerial) logHex("[RAW GAL->TCP]", &b, 1);

    if (tcpClient && tcpClient.connected()) {
      tcpClient.write(&b, 1);
    }

    if (optRawEcho && !rawtx.waiting) {
      gal.write(b);
      gal.flush();
      rawtx.waiting      = true;
      rawtx.last         = b;
      rawtx.lastMs       = millis();
      rawtx.retries      = 0;
      rawtx.sendNullNext = true;

      if (optLogSerial) logHex("[RAW ECHO ESP->GAL]", &b, 1);
    }
  }
}

// ===================== TCP G40 feed =====================
String tcpInLine;

void handleTcpG40Feed() {
  if (mode != MODE_TCP_G40) return;
  acceptTcpClient();
  if (!(tcpClient && tcpClient.connected())) return;

  while (tcpClient.available()) {
    int bi = tcpClient.read();
    if (bi < 0) break;
    char c = (char)bi;

    if (optTcpLineMode) {
      if (c == '\r' || c == '\n') {
        for (size_t i=0;i<tcpInLine.length();i++) fifoPush((uint8_t)tcpInLine[i]);
        fifoPush('\r');
        tcpInLine = "";
      } else {
        tcpInLine += c;
        if (tcpInLine.length() > 120) {
          for (size_t i=0;i<tcpInLine.length();i++) fifoPush((uint8_t)tcpInLine[i]);
          tcpInLine = "";
        }
      }
    } else {
      fifoPush((uint8_t)c);
    }
  }
}

// ===================== BBS feed (remote->FIFO with TELNET + UTF-8 YU) =====================
void handleBbsFeed() {
  if (mode != MODE_BBS_G40) return;
  if (!ensureBbsConnected()) return;

  static uint8_t utfLead = 0;
  static uint8_t utfSkip = 0;

  while (bbsClient.available()) {
    int bi = bbsClient.read();
    if (bi < 0) break;
    uint8_t b = (uint8_t)bi;

    // <--- ADD HERE
    // Every received byte means "BBS is active just now":
    lastBbsRxMs = millis();
    lastBbsEnqSent = false;  // optional but nice: allow a new ENQ after this page

    if (utfSkip > 0) {
      utfSkip--;
      continue;
    }

    uint8_t galByte = 0;
    bool matched = false;

    if (utfLead) {
      if (utfLead == 0xC5) {
        if (b == 0xA0 || b == 0xA1) { galByte = GAL_YU_S_PLACE; matched = true; }
        else if (b == 0xBD || b == 0xBE) { galByte = GAL_YU_Z_PLACE; matched = true; }
      } else if (utfLead == 0xC4) {
        if (b == 0x8C || b == 0x8D) { galByte = GAL_YU_CCAR_PLACE; matched = true; }
        else if (b == 0x86 || b == 0x87) { galByte = GAL_YU_CAC_PLACE; matched = true; }
        else if (b == 0x90 || b == 0x91) {
          pushRemoteByte('D', optUppercaseFromBBS);
          pushRemoteByte('J', optUppercaseFromBBS);
          matched = true;
        }
      }

      utfLead = 0;
      if (matched) {
        pushRemoteByte(galByte, optUppercaseFromBBS);
        continue;
      }
    } else {
      if (b == 0xC5 || b == 0xC4) {
        utfLead = b;
        continue;
      } else if (b == 0xC3) {
        utfSkip = 1;
        continue;
      }
    }

    pushRemoteByte(b, optUppercaseFromBBS);
  }
}

// ===================== Web UI =====================
File uploadFile;

String htmlHeader(const String& title) {
  String css =
    "body{background:#fff;color:#000;font-family:Courier New,Lucida Console,monospace;"
    "max-width:980px;margin:24px auto;padding:0 12px;}"
    ".card{border:1px solid #000;padding:14px;margin:12px 0;}"
    "h1,h2{margin:0 0 10px 0;}"
    "a{color:#000;}"
    "button{font-family:inherit;padding:6px 10px;border:1px solid #000;background:#eee;cursor:pointer;}"
    "small{opacity:.85;}"
    ".row{display:flex;gap:10px;flex-wrap:wrap;align-items:center;}"
    ".pill{display:inline-block;border:1px solid #000;padding:2px 8px;margin-left:6px;}";
  return "<!doctype html><html><head><meta charset='utf-8'>"
         "<meta name='viewport' content='width=device-width, initial-scale=1'>"
         "<title>" + title + "</title>"
         "<style>" + css + "</style>"
         "</head><body>";
}

String deviceBaseURL() {
  auto m = WiFi.getMode();
  if (m == WIFI_AP || m == WIFI_AP_STA) return "http://192.168.4.1/";
  return String("http://") + WiFi.localIP().toString() + "/";
}

String modeName() {
  switch (mode) {
    case MODE_PROTO:   return "PROTO";
    case MODE_TCP_RAW: return "TCP RAW";
    case MODE_TCP_G40: return "TCP G40";
    case MODE_BBS_G40: return "BBS G40";
    case MODE_SOUND:   return "SOUND";
  }
  return "?";
}

void handleRoot() {
  String s = htmlHeader("Galaksija Loader");
  s += "<h1>GALAKSIJA LOADER</h1>";

  s += "<div class='card'>";
  s += "<div class='row'><b>Mode:</b> <span class='pill'>" + modeName() + "</span>";
  s += "<span class='pill'>G40 proto: ";
  s += useShortProto ? "SHORT" : "CLASSIC";
  s += "</span></div>";

  s += "<p><small>"
       "TCP port: <b>2323</b>. Framed control (G40): send a frame with body "
       "<b>__SERIAL__</b> (RAW), <b>__SERIAL_B__</b> (G40), <b>__BBS__</b>, <b>__SOUND__</b>, <b>__PROTO__</b>, or <b>__LIST__</b>/<b>__LIST__XXX__</b>."
       " In G40 modes, send a frame whose only non-padding byte is <b>0xD7</b> to switch to SHORT protocol."
       "</small></p>";

  s += "<div class='row'>"
       "<a href='/set?m=PROTO'><button>Mode: PROTO</button></a>"
       "<a href='/set?m=RAW'><button>Mode: TCP RAW</button></a>"
       "<a href='/set?m=G40'><button>Mode: TCP G40</button></a>"
       "<a href='/set?m=BBS'><button>Mode: BBS G40</button></a>"
       "<a href='/set?m=SOUND'><button>Mode: SOUND</button></a>"
       "</div>";

  s += "<div class='row' style='margin-top:10px'>"
       "<a href='/opt?log=" + String(optLogSerial ? "0" : "1") + "'><button>Log "
       + String(optLogSerial ? "ON" : "OFF") + "</button></a>"
       "<a href='/opt?linemode=" + String(optTcpLineMode ? "0" : "1") + "'><button>TCP line-mode "
       + String(optTcpLineMode ? "ON" : "OFF") + "</button></a>"
       "<a href='/opt?upper=" + String(optUppercaseFromBBS ? "0" : "1") + "'><button>BBS uppercase "
       + String(optUppercaseFromBBS ? "ON" : "OFF") + "</button></a>"
       "<a href='/opt?rawecho=" + String(optRawEcho ? "0" : "1") + "'><button>RAW echo "
       + String(optRawEcho ? "ON" : "OFF") + "</button></a>"
       "</div>";

  FsInfoLite fi = getFsInfoLite();
  s += "<p><b>Base URL:</b> " + deviceBaseURL() + "</p>";
  s += "<p><b>LittleFS:</b> total " + fmtBytes(fi.totalBytes) +
       " | used " + fmtBytes(fi.usedBytes) +
       " | free " + fmtBytes(fi.freeBytes) + "</p>";

  if (lastUploadedGtpUpper.length() > 0) {
    s += "<p><b>Last uploaded GTP:</b> " + lastUploadedGtpUpper + ".gtp</p>";
  }

  s += "<p><a href='/upload'>Upload</a> | "
       "<a href='/format' onclick='return confirm(\"FORMAT LittleFS?\")'>Format FS</a></p>";
  s += "</div>";

  s += "<div class='card'><h2>Files</h2><ul>";
  Dir d = LittleFS.openDir("/");
  while (d.next()) {
    String fn = d.fileName();
    s += "<li>" + fn + " (" + String(d.fileSize()) + " bytes) "
         "<a href='/download?f=" + fn + "'>download</a> "
         "<a href='/delete?f=" + fn + "' onclick='return confirm(\"Delete " + fn + "?\")'>delete</a></li>";
  }
  s += "</ul>";
  s += "<p><small>PROTO mode: <b>OLD # NAME</b> loads /NAME.gtp, "
       "<b>SAVE # NAME</b> stores /NAME.gtp. Bare <b>OLD #</b> reloads last uploaded GTP.</small></p>";
  s += "</div></body></html>";
  server.send(200, "text/html", s);
}

void handleSetMode() {
  String m = server.arg("m");
  m.toUpperCase();
  if (m == "PROTO") {
    mode = MODE_PROTO;
    stopRemoteConnections();
    useShortProto = false;
  } else if (m == "RAW") {
    mode = MODE_TCP_RAW;
    stopRemoteConnections();
    useShortProto = false;
  } else if (m == "G40") {
    mode = MODE_TCP_G40;
    stopRemoteConnections();
    g40tx.waiting=false; g40tx.retries=0;
    useShortProto = false;
  } else if (m == "BBS") {
    mode = MODE_BBS_G40;
    stopRemoteConnections();
    g40tx.waiting=false; g40tx.retries=0;
    useShortProto = false;
    ensureBbsConnected();
    lastBbsEnqSent = false;
  } else if (m == "SOUND") {
    mode = MODE_SOUND;
    stopRemoteConnections();
    useShortProto = false;
  }
  server.sendHeader("Location", "/");
  server.send(303);
}

void handleOpt() {
  if (server.hasArg("log"))      optLogSerial        = (server.arg("log") == "1");
  if (server.hasArg("linemode")) optTcpLineMode      = (server.arg("linemode") == "1");
  if (server.hasArg("upper"))    optUppercaseFromBBS = (server.arg("upper") == "1");
  if (server.hasArg("rawecho"))  optRawEcho          = (server.arg("rawecho") == "1");
  server.sendHeader("Location", "/");
  server.send(303);
}

void handleUploadPage() {
  String s = htmlHeader("Upload");
  s += "<div class='card'><h2>Upload .gtp (multi)</h2>";
  if (fsBusy) s += "<p><b>Busy:</b> receiving from Galaksija. Try again.</p>";

  FsInfoLite fi = getFsInfoLite();
  s += "<p><b>Free space:</b> " + fmtBytes(fi.freeBytes) + "</p>";

  s += "<form method='POST' action='/upload' enctype='multipart/form-data'>"
       "<input type='file' name='file' accept='.gtp,.GTP' multiple> "
       "<input type='submit' value='Upload'></form>"
       "<p><a href='/'>Back</a></p></div></body></html>";
  server.send(200, "text/html", s);
}

void handleUpload() {
  if (fsBusy) return;
  HTTPUpload& up = server.upload();

  if (up.status == UPLOAD_FILE_START) {
    if (uploadFile) uploadFile.close();
    String fn = galfname(up.filename);
    String path = "/" + fn + ".gtp";
    uploadFile = LittleFS.open(path, "w");
    lastUploadedGtpUpper = fn;
  } else if (up.status == UPLOAD_FILE_WRITE) {
    if (uploadFile) uploadFile.write(up.buf, up.currentSize);
  } else if (up.status == UPLOAD_FILE_END) {
    if (uploadFile) uploadFile.close();
  }
}

void handleUploadDone() {
  mode = MODE_PROTO;
  stopRemoteConnections();
  useShortProto = false;
  server.sendHeader("Location", "/");
  server.send(303);
}

void handleDelete() {
  if (fsBusy) { server.send(409, "text/plain", "Busy"); return; }
  String f = server.arg("f");
  if (f.length() && LittleFS.exists(f)) LittleFS.remove(f);
  server.sendHeader("Location", "/");
  server.send(303);
}

void handleDownload() {
  String f = server.arg("f");
  if (!f.length() || !LittleFS.exists(f)) { server.send(404, "text/plain", "Not found"); return; }
  File file = LittleFS.open(f, "r");
  server.streamFile(file, "application/octet-stream");
  file.close();
}

void handleFormatFS() {
  if (fsBusy) { server.send(409, "text/plain", "Busy"); return; }
  LittleFS.format();
  server.sendHeader("Location", "/");
  server.send(303);
}

// ===================== WiFi =====================
bool connectSTAorFallbackAP() {
  WiFi.persistent(false);
  WiFi.setAutoReconnect(true);

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);

  Serial.print("Connecting STA to: ");
  Serial.println(WIFI_SSID);

  uint32_t t0 = millis();
  while (WiFi.status() != WL_CONNECTED && (millis() - t0) < WIFI_CONNECT_TIMEOUT_MS) {
    delay(300);
    Serial.print(".");
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("Connected! DHCP IP: ");
    Serial.println(WiFi.localIP());
    return true;
  }

  Serial.println("STA failed -> starting AP fallback.");
  WiFi.disconnect(true);
  delay(200);

  WiFi.mode(WIFI_AP);
  bool ok = WiFi.softAP(AP_SSID, AP_PASS);
  Serial.print("AP started: ");
  Serial.println(ok ? "OK" : "FAIL");
  Serial.print("AP SSID: ");
  Serial.println(AP_SSID);
  Serial.println("AP IP: 192.168.4.1");
  return false;
}

// ===================== BBS ENQ tick =====================
void bbsEnqTick() {
  if (mode != MODE_BBS_G40) return;
  if (fifoCount() != 0) return;
  if (lastBbsRxMs == 0) return;

  static const uint32_t BBS_ENQ_IDLE_MS = 1000;
  uint32_t now = millis();
  if (now - lastBbsRxMs < BBS_ENQ_IDLE_MS) return;
  if (lastBbsEnqSent) return;

  if (!useShortProto) {
    uint8_t enqBody[16];
    enqBody[0] = 0x05;
    for (int i=1;i<16;i++) enqBody[i] = G40_PAD;
    if (optLogSerial) Serial.println("[BBS] ENQ classic");
    sendBodyWithAck(enqBody);
  } else {
    uint8_t enqPay[1] = {0x05};
    if (optLogSerial) Serial.println("[BBS] ENQ short");
    sendShortPayloadWithAck(enqPay, 1);
  }

  lastBbsEnqSent = true;
}

// ===================== Setup / Loop =====================
void setup() {
  Serial.begin(115200);
  delay(200);

  gal.begin(19200, SWSERIAL_8N1, GAL_RX_PIN, GAL_TX_PIN, false, 256);

  if (!LittleFS.begin()) {
    LittleFS.format();
    LittleFS.begin();
  }

  FsInfoLite fi0 = getFsInfoLite();
  Serial.print("LittleFS total: "); Serial.print(fmtBytes(fi0.totalBytes));
  Serial.print(" | used: ");        Serial.print(fmtBytes(fi0.usedBytes));
  Serial.print(" | free: ");        Serial.println(fmtBytes(fi0.freeBytes));

  connectSTAorFallbackAP();
  WiFi.setSleepMode(WIFI_NONE_SLEEP);

  server.on("/", HTTP_GET, handleRoot);
  server.on("/set", HTTP_GET, handleSetMode);
  server.on("/opt", HTTP_GET, handleOpt);

  server.on("/upload", HTTP_GET, handleUploadPage);
  server.on("/upload", HTTP_POST, handleUploadDone, handleUpload);

  server.on("/delete", HTTP_GET, handleDelete);
  server.on("/download", HTTP_GET, handleDownload);
  server.on("/format", HTTP_GET, handleFormatFS);

  server.begin();
  tcpServer.begin();

  Serial.println();
  Serial.print("Web: ");
  Serial.println(deviceBaseURL());
  Serial.println("TCP: 2323");
  Serial.println("Control frames: __PROTO__ / __SERIAL__ / __SERIAL_B__ / __BBS__ / __SOUND__ / __LIST__");
}

void loop() {
  server.handleClient();

  handleGalaksijaIO();   // PROTO + G40 control sniff
  handleTcpRawBridge();  // RAW
  handleTcpG40Feed();    // TCP->FIFO (G40)
  handleBbsFeed();       // BBS->FIFO (telnet)

  if (!useShortProto) {
    g40TxTick();         // classic G40
    synTick();           // SYN only in classic mode
  } else {
    shortTxTick();       // short 48-byte protocol
  }

  bbsEnqTick();          // ENQ handshake when idle (classic or short)
  rawEchoAckTick();      // RAW echo ACK
}
