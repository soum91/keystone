// Status screen for boards with a built-in 0.96" SSD1306 OLED (ideaspark, Heltec-style, etc.).
// Finds the display by probing the usual I2C pin pairs; boards without one just skip it.
// Full-frame graphics (U8g2): every frame is redrawn whole, so an I2C glitch never sticks around.
#pragma once
#include <Arduino.h>
#include <Wire.h>
#include <U8g2lib.h>

namespace oled {

static U8G2 *g = nullptr;

struct Pins { int sda, scl, rst; };

static bool probe(int sda, int scl, uint8_t &addr) {
  Wire.end();
  if (!Wire.begin(sda, scl, 400000)) return false;
  for (uint8_t a : {0x3C, 0x3D}) {
    Wire.beginTransmission(a);
    if (Wire.endTransmission() == 0) { addr = a; return true; }
  }
  return false;
}

static void begin() {
#if defined(CONFIG_IDF_TARGET_ESP32)
  const Pins tries[] = {{21, 22, -1}, {22, 21, -1}, {4, 15, 16}, {5, 4, -1}, {4, 5, -1}};
#elif defined(CONFIG_IDF_TARGET_ESP32S3)
  const Pins tries[] = {{17, 18, 21}, {8, 9, -1}, {41, 42, -1}, {5, 6, -1}};
#else
  const Pins tries[] = {{5, 6, -1}, {8, 9, -1}, {4, 5, -1}};
#endif
  for (const Pins &p : tries) {
    if (p.rst >= 0) {
      pinMode(p.rst, OUTPUT);
      digitalWrite(p.rst, LOW); delay(20); digitalWrite(p.rst, HIGH); delay(20);
    }
    uint8_t addr = 0;
    if (!probe(p.sda, p.scl, addr)) continue;
    g = new U8G2_SSD1306_128X64_NONAME_F_HW_I2C(U8G2_R0, U8X8_PIN_NONE, p.scl, p.sda);
    g->setI2CAddress(addr << 1);
    g->setBusClock(400000);
    g->begin();
    g->setPowerSave(0);
    g->clearBuffer();
    g->sendBuffer();
    Serial.printf("[afterglow] OLED found on SDA %d SCL %d (0x%02x)\n", p.sda, p.scl, addr);
    return;
  }
  Wire.end();
}

static bool present() { return g != nullptr; }

}  // namespace oled
