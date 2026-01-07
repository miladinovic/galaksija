## ESP Web Loader – Overview & Setup

This project is an **ESP8266‑based web loader for the Galaksija** home computer.

It has been tested on a **LOLIN (Wemos) D1 R1** board (ESP8266), but it should work with most other ESP8266 boards that:
- support **LittleFS**, and  
- have enough flash for both the sketch and filesystem.

### 1. Tools you need
 
You need:

- **Arduino IDE** (or PlatformIO, if you prefer)
- **ESP8266 board support** installed in Arduino IDE  
  (via *Boards Manager* → search for “LOLIN(WeMos) D1 R1” and install it)

### 2. Required libraries / headers

These headers are used in the sketch (they come with the ESP8266 core and LittleFS support):

```cpp
#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <FS.h>
#include <LittleFS.h>
#include <SoftwareSerial.h>
```

### 3. Wi‑Fi configuration

Edit the sketch and set your Wi‑Fi credentials:

```cpp
// ===================== WiFi =====================
const char* WIFI_SSID = "_ADD_YOUR_WIFI_SSID_";
const char* WIFI_PASS = "_ADD_YOUR_WIFI_PASSWORD_";
```

- If you leave these as the default placeholders, the ESP will **start in AP mode** with its own SSID/password (described later in this file).
- If you set them to your router credentials, make sure the network is **2.4 GHz** (ESP8266 does not support 5 GHz).

### 4. Board & flash settings in Arduino IDE

In **Tools → Board**, select:

- `LOLIN(Wemos) D1 R1` – or the ESP8266 board you are actually using.

In **Tools → Flash Size**, choose a layout that gives enough space for the filesystem. For example:

- **3MB (FS)** and **1MB (sketch)** – this is what I use.

Any similar partition that provides at least a couple of MB for **LittleFS** will work fine.

## How to Use the ESP Web Loader

### 1️⃣ Power and connect the ESP

#### 🔌 Galaksija UART pins

The sketch uses these pin definitions for the serial link between **ESP** and **Galaksija**:

```cpp
// ===================== Galaksija UART pins =====================
static const int8_t GAL_RX_PIN = D5; // ESP RX  <- Galaksija TX
static const int8_t GAL_TX_PIN = D6; // ESP TX  -> Galaksija RX
```

- **GAL_RX_PIN (D5)**: this is the **ESP’s RX** pin. It must be connected to **Galaksija’s TX / SAVE output**.  
- **GAL_TX_PIN (D6)**: this is the **ESP’s TX** pin. It must be connected to **Galaksija’s RX / LOAD input**.

> RX and TX are always **crossed**:  
> Galaksija TX ➜ ESP RX (`GAL_RX_PIN`),  
> ESP TX ➜ Galaksija RX (`GAL_TX_PIN`).

Don’t forget to connect **GND ↔ GND** between ESP and Galaksija, and (if needed) protect the ESP RX with a small resistor divider if Galaksija’s TX is at 5 V.

If you **don’t configure Wi‑Fi**, the ESP will start its **own Access Point (AP)** automatically.

**Default AP credentials:**
- **SSID:** GALAKSIJA-LOADER
- **Password:** 12345678

Just connect to that network from your phone or computer.

If you *do* want it on your home Wi‑Fi, edit the sketch:

```cpp
const char* WIFI_SSID = "YOUR_WIFI";
const char* WIFI_PASS = "YOUR_PASSWORD";
```

> ⚠️ **Important:** Wemos D1 R1 / ESP8266 only supports **2.4 GHz Wi‑Fi**.  
> If your router is 5 GHz only, the ESP will never connect.

---

### 2️⃣ Find the ESP’s IP address

If it connects to your Wi‑Fi, look it up using one of these methods:

- Check the **router’s device list**
- Use the **FING** mobile app (Android/iOS) to scan your network
- Watch the serial monitor — the IP is printed at boot

---

### 3️⃣ Open the Web Loader

Open any browser (Chrome, Edge, Firefox, Safari) and go to:

```
http://<ESP_IP_ADDRESS>
```

If you're using AP mode, the default IP is usually:

```
http://192.168.4.1
```

You should now see the **ESP Web Loader page**.

---

### 4️⃣ Upload your GTP files

Click:

```
Upload file
```

Select your `.GTP` files — they will be stored in the ESP filesystem.

You can also view or delete uploaded files directly from the page.

---

### 5️⃣ Load/Save from Galaksija

From your Galaksija, use the standard commands:

```
OLD#NAMEOFYOURGTP
```

to load a program, and:

```
SAVE#NAMEOFYOURGTP
```

to save one.

> The ESP emulates tape storage — but is **way faster and more reliable**.

---

### Done!

You now have a working wireless loader for Galaksija 🎉  
If something doesn’t work, check: USB power, Wi‑Fi band (2.4 GHz), and the IP address.
