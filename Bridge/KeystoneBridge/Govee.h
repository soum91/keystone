// Govee Bluetooth thermo-hygrometer (H5102 and friends) in Apple Home: the bridge listens to its
// broadcasts like a Govee gateway would. Decoding from DewPoint's bridge (soum91/dewpoint), after govee-ble.
// On first boot it locks onto the strongest Govee sensor it hears for 30 s, then restarts once so Home
// sees it. Serial @G forgets it and picks again.
#pragma once
#if !defined(CONFIG_IDF_TARGET_ESP32C3)   // the C3 build is out of flash room for Bluetooth
#define HAS_GOVEE 1
#include <NimBLEDevice.h>

#define GOVEE_PICK_MS 30000UL
#define GOVEE_STALE_MS (10UL * 60UL * 1000UL)
#define GOVEE_PUSH_MS 15000UL

namespace govee {

static portMUX_TYPE mux = portMUX_INITIALIZER_UNLOCKED;
static volatile float temp = 0, hum = 0;
static volatile int batt = 100;
static volatile uint32_t seq = 0, lastHeard = 0;
static char lockedAddr[18] = "", lockedName[32] = "";
static volatile bool locked = false;
static char bestAddr[18] = "", bestName[32] = "";
static volatile int bestRssi = -127;
static uint32_t bootMs = 0;
static bool inHome = false;

static bool decodePacked(uint8_t a, uint8_t b, uint8_t c, float &t, float &h) {
  int32_t base = ((int32_t)a << 16) | ((int32_t)b << 8) | c;
  if (base == 0xFFFFFF) return false;
  bool neg = base & 0x800000;
  int32_t v = base & 0x7FFFFF;
  t = (float)(v / 1000) / 10.0f;
  if (neg) t = -t;
  h = (float)(v % 1000) / 10.0f;
  return t >= -40 && t <= 100 && h >= 0 && h <= 100;
}

static bool parse(const std::string &name, const std::string &md, float &t, float &h, int &b) {
  if (md.size() < 3) return false;
  const uint8_t *d = (const uint8_t *)md.data();
  uint16_t company = d[0] | (d[1] << 8);
  const uint8_t *p = d + 2;
  size_t n = md.size() - 2;
  if (name.rfind("GV", 0) != 0 && name.rfind("Govee", 0) != 0) return false;
  bool is5075 = name.find("H5072") != std::string::npos || name.find("H5075") != std::string::npos;
  if (n == 6 && (is5075 || company == 0xEC88)) {
    if (p[4] & 0x80) return false;
    b = p[4] & 0x7F;
    return decodePacked(p[1], p[2], p[3], t, h);
  }
  if (n == 6) {   // H5100/H5101/H5102/H5104/H5174/H5177
    if (p[5] & 0x80) return false;
    b = p[5] & 0x7F;
    return decodePacked(p[2], p[3], p[4], t, h);
  }
  return false;
}

class Callbacks : public NimBLEScanCallbacks {
  void onResult(const NimBLEAdvertisedDevice *dev) override {
    if (dev->getManufacturerDataCount() == 0) return;
    std::string name = dev->getName();
    float t, h;
    int b;
    if (!parse(name, dev->getManufacturerData(), t, h, b)) return;
    std::string addr = dev->getAddress().toString();
    if (!locked) {
      int rssi = dev->getRSSI();
      if (rssi > bestRssi) {
        portENTER_CRITICAL(&mux);
        strlcpy(bestAddr, addr.c_str(), sizeof(bestAddr));
        strlcpy(bestName, name.c_str(), sizeof(bestName));
        bestRssi = rssi;
        portEXIT_CRITICAL(&mux);
      }
      return;
    }
    if (strcasecmp(addr.c_str(), lockedAddr) != 0) return;
    portENTER_CRITICAL(&mux);
    temp = t; hum = h; batt = b;
    seq = seq + 1;
    lastHeard = millis();
    portEXIT_CRITICAL(&mux);
  }
  void onScanEnd(const NimBLEScanResults &, int) override { NimBLEDevice::getScan()->start(0, false, true); }
};
static Callbacks callbacks;

static bool stale() {
  uint32_t l = lastHeard;
  return l == 0 || millis() - l > GOVEE_STALE_MS;
}

struct Temperature : Service::TemperatureSensor {
  SpanCharacteristic *t, *active;
  uint32_t seen = 0;
  Temperature() : Service::TemperatureSensor() {
    t = new Characteristic::CurrentTemperature(20.0);
    t->setRange(-40, 100);
    active = new Characteristic::StatusActive(0);
  }
  void loop() override {
    bool s = stale();
    if (active->getVal() == (int)s) active->setVal(!s);
    if (s || seq == seen || t->timeVal() < GOVEE_PUSH_MS) return;
    portENTER_CRITICAL(&mux);
    float v = temp; seen = seq;
    portEXIT_CRITICAL(&mux);
    if (fabs(t->getVal<float>() - v) >= 0.05f) t->setVal(v);
  }
};

struct Humidity : Service::HumiditySensor {
  SpanCharacteristic *h, *active;
  uint32_t seen = 0;
  Humidity() : Service::HumiditySensor() {
    h = new Characteristic::CurrentRelativeHumidity(50.0);
    active = new Characteristic::StatusActive(0);
  }
  void loop() override {
    bool s = stale();
    if (active->getVal() == (int)s) active->setVal(!s);
    if (s || seq == seen || h->timeVal() < GOVEE_PUSH_MS) return;
    portENTER_CRITICAL(&mux);
    float v = hum; seen = seq;
    portEXIT_CRITICAL(&mux);
    if (fabs(h->getVal<float>() - v) >= 0.5f) h->setVal(v);
  }
};

struct Battery : Service::BatteryService {
  SpanCharacteristic *level, *low;
  uint32_t seen = 0;
  Battery() : Service::BatteryService() {
    level = new Characteristic::BatteryLevel(100);
    new Characteristic::ChargingState(2);
    low = new Characteristic::StatusLowBattery(0);
  }
  void loop() override {
    if (stale() || seq == seen || level->timeVal() < 60000) return;
    int b = batt; seen = seq;
    if (level->getVal() != b) level->setVal(b);
    int l = b <= 15 ? 1 : 0;
    if (low->getVal() != l) low->setVal(l);
  }
};

// Bluetooth costs ~50 KB of RAM while on. Once the sensor is picked, listen in 25 s bursts every
// 2.5 minutes and switch the radio off in between, so Wi-Fi, HomeKit and the AC's TLS have room.
static volatile bool radioOn = false;
static uint32_t scanUntil = 0, nextScan = 0;

static void radioStart() {
  NimBLEDevice::init("");
  NimBLEScan *scan = NimBLEDevice::getScan();
  scan->setScanCallbacks(&callbacks, true);
  scan->setActiveScan(true);
  scan->setInterval(160);
  scan->setWindow(60);
  scan->setMaxResults(0);
  scan->start(0, false, true);
  radioOn = true;
}

static void radioStop() {
  if (!radioOn) return;
  NimBLEDevice::getScan()->stop();
  NimBLEDevice::deinit(true);
  radioOn = false;
}

static void begin() {
  bootMs = millis();
  String a = prefs.getString("gv_addr", ""), n = prefs.getString("gv_name", "");
  if (a.length()) {
    strlcpy(lockedAddr, a.c_str(), sizeof(lockedAddr));
    strlcpy(lockedName, n.c_str(), sizeof(lockedName));
    locked = true;
  }
  if (!locked) radioStart();   // picking: listen continuously for 30 s
}

static void addAccessory(std::vector<uint32_t> &used) {
  if (!locked) return;
  inHome = true;
  new SpanAccessory(aidFor(String("govee:") + lockedAddr, used));
    new Service::AccessoryInformation();
      new Characteristic::Identify();
      new Characteristic::Name("Thermometer");
      new Characteristic::Manufacturer("Govee");
      new Characteristic::Model(lockedName);
      new Characteristic::SerialNumber(lockedAddr);
    new Temperature();
    new Humidity();
    new Battery();
}

// From the worker: finish the first-boot pick.
static void tick() {
  if (otaActive) { radioStop(); return; }
  if (locked) {
    if (radioOn) {
      if ((int32_t)(millis() - scanUntil) >= 0) { radioStop(); nextScan = millis() + 150000UL; }
    } else if (millis() > 45000UL && (int32_t)(millis() - nextScan) >= 0 && ESP.getMaxAllocHeap() > 30000) {
      radioStart();
      scanUntil = millis() + 25000UL;
    }
    return;
  }
  if (millis() - bootMs < GOVEE_PICK_MS || bestAddr[0] == 0) return;
  portENTER_CRITICAL(&mux);
  String a = bestAddr, n = bestName;
  portEXIT_CRITICAL(&mux);
  prefs.putString("gv_addr", a);
  prefs.putString("gv_name", n);
  logEvent("Govee: picked " + n + ", restarting to add it to Home");
  delay(500);
  ESP.restart();
}

static void forget(const char *) {
  prefs.remove("gv_addr");
  prefs.remove("gv_name");
  Serial.println("Forgot the Govee sensor. Restarting; keep the bridge next to the right one for 30 s.");
  delay(500);
  ESP.restart();
}

static void info(JsonDocument &d) {
  JsonObject g = d["govee"].to<JsonObject>();
  g["locked"] = (bool)locked;
  if (locked) {
    g["name"] = lockedName;
    if (!stale()) { g["temp"] = (float)temp; g["humidity"] = (float)hum; g["battery"] = (int)batt; }
    g["heardAgo"] = lastHeard ? (int)((millis() - lastHeard) / 1000) : -1;
  }
}

}  // namespace govee
#else
namespace govee {   // no Bluetooth on this chip
static const bool radioOn = false;
static void radioStop() {}
}  // namespace govee
#endif
