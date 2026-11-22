// Govee Bluetooth thermo-hygrometer (H5102 and friends) in Apple Home: the bridge listens to its
// broadcasts like a Govee gateway would. Decoding from DewPoint's bridge (soum91/dewpoint), after govee-ble.
// On first boot it locks onto the strongest Govee sensor it hears for 30 s, then restarts once so Home
// sees it. Serial @G forgets it and picks again.
#pragma once
#if !defined(CONFIG_IDF_TARGET_ESP32C3)   // the C3 build is out of flash room for Bluetooth
#define HAS_GOVEE 1
#include <NimBLEDevice.h>
#include <WiFiUdp.h>
#include <stdlib.h>
#include <math.h>
#include <ctype.h>

#define GOVEE_PICK_MS 30000UL
#define GOVEE_STALE_MS (15UL * 60UL * 1000UL)
#define GOVEE_PUSH_MS 15000UL
#define GOVEE_FEED_PORT 8092
#define GOVEE_FEED_TIMEOUT_MS 90000UL
#define GOVEE_FEED_SAMPLE_MAX_AGE_MS 120000UL

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
// DewPoint's iPhone app forwards BLE observations while iOS keeps it running.
// If the feed expires, the existing memory-gated local NimBLE scanner is the fallback.
static WiFiUDP feedUdp;
static bool feedOpen = false;
static volatile uint32_t remotePacketMs = 0, remoteHeardMs = 0;
static uint32_t feedAccepted = 0, feedRejected = 0;
static char feedHost[16] = "";
static uint32_t pickStartedMs = 0;  // delay local BLE selection while awaiting DewPoint
static volatile uint32_t localHeardMs = 0;
static volatile bool latestFromPhone = false;

static bool remoteFresh() {
  uint32_t now = millis(), received = remotePacketMs, heard = remoteHeardMs;
  return received != 0 && heard != 0 && now - received <= GOVEE_FEED_TIMEOUT_MS &&
         now - heard <= GOVEE_FEED_SAMPLE_MAX_AGE_MS;
}


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

// Receive small iOS UDP frames only from the same LAN. Sensor pinning is not authentication;
// don't run the feed on untrusted networks or forward this port to the internet.
static bool sameSubnet(const IPAddress &sender) {
  IPAddress me = WiFi.localIP(), mask = WiFi.subnetMask();
  for (int i = 0; i < 4; ++i)
    if ((sender[i] & mask[i]) != (me[i] & mask[i])) return false;
  return true;
}

static bool decimal(const char *s, float &value) {
  if (!s || !*s) return false;
  char *end = nullptr;
  value = strtof(s, &end);
  return end != s && *end == 0 && isfinite(value);
}

static bool unsignedNumber(const char *s, uint32_t &value) {
  if (!s || !*s || *s == '-') return false;
  char *end = nullptr;
  unsigned long n = strtoul(s, &end, 10);
  if (end == s || *end != 0) return false;
  value = (uint32_t)n;
  return true;
}

static bool validMac(const char *mac) {
  if (!mac || strlen(mac) != 17) return false;
  for (int i = 0; i < 17; i++) {
    if ((i + 1) % 3 == 0) { if (mac[i] != ':') return false; }
    else if (!isxdigit((unsigned char)mac[i])) return false;
  }
  return true;
}

// Runs on Keystone's network worker, never in the HomeSpan or NimBLE callbacks.
static bool acceptFeed(char *message, const IPAddress &sender) {
  if (!sameSubnet(sender)) return false;

  // DewPoint is an iOS app. CoreBluetooth intentionally hides BLE MAC addresses,
  // so a DPG2 packet identifies its Govee by the advertised sensor name instead.
  char *fields[7] = {};
  char *context = nullptr;
  char *p = strtok_r(message, ",", &context);
  int count = 0;
  while (p && count < 7) { fields[count++] = p; p = strtok_r(nullptr, ",", &context); }
  if (count != 7 || p || strcmp(fields[0], "DPG2") != 0) return false;

  const char *name = fields[1];
  size_t nameLen = strlen(name);
  if (!nameLen || nameLen >= sizeof(lockedName)) return false;
  if (strncmp(name, "GV", 2) && strncmp(name, "Govee", 5)) return false;
  for (size_t i = 0; i < nameLen; i++)
    if (!isalnum((unsigned char)name[i]) && name[i] != '_' && name[i] != '-') return false;

  float t, h;
  uint32_t battery, age, sampleSeq;
  if (!decimal(fields[2], t) || !decimal(fields[3], h) ||
      !unsignedNumber(fields[4], battery) || !unsignedNumber(fields[5], age) ||
      !unsignedNumber(fields[6], sampleSeq)) return false;
  if (t < -40 || t > 100 || h < 0 || h > 100 || battery > 100 ||
      age > GOVEE_FEED_SAMPLE_MAX_AGE_MS || sampleSeq == 0) return false;
  // Never let a different Govee override the accessory already paired in Home.
  if (locked && strcasecmp(name, lockedName)) return false;

  if (!locked) {
    // Use the advertised name for a stable HomeKit identity. iOS does not
    // expose the real BLE MAC, and we must not assume the UUID is a MAC.
    uint32_t hash = 2166136261UL;
    for (const char *q = name; *q; ++q) {
      hash ^= (uint8_t)toupper((unsigned char)*q);
      hash *= 16777619UL;
    }
    snprintf(lockedAddr, sizeof(lockedAddr), "ios:%08lx", (unsigned long)hash);
    strlcpy(lockedName, name, sizeof(lockedName));
    locked = true;
    prefs.putString("gv_addr", lockedAddr);
    prefs.putString("gv_name", lockedName);
    // HomeSpan accessories are created only at boot. One settings-preserving
    // restart adds the first discovered sensor without changing other pairings.
    Serial.printf("[keystone] pinned Govee %s from DewPoint iOS; restarting once\n", lockedName);
    delay(150);
    ESP.restart();
    return true;
  }

  uint32_t now = millis();
  portENTER_CRITICAL(&mux);
  temp = t; hum = h; batt = (int)battery;
  lastHeard = now - age;  // preserve measurement age, not just network receipt time
  latestFromPhone = true;
  seq++;
  remoteHeardMs = now - age;
  remotePacketMs = now;
  portEXIT_CRITICAL(&mux);
  strlcpy(feedHost, sender.toString().c_str(), sizeof(feedHost));
  feedAccepted++;
  return true;
}

static void pollFeed() {
  if (WiFi.status() != WL_CONNECTED) {
    if (feedOpen) { feedUdp.stop(); feedOpen = false; }
    return;
  }
  if (!feedOpen) feedOpen = feedUdp.begin(GOVEE_FEED_PORT) != 0;
  if (!feedOpen) return;
  // Limit processing to keep other devices and web requests responsive.
  for (int i = 0; i < 3; ++i) {
    int length = feedUdp.parsePacket();
    if (length <= 0) break;
    char packet[160];
    IPAddress sender = feedUdp.remoteIP();
    if (length >= (int)sizeof(packet)) {
      while (feedUdp.available()) feedUdp.read();
      feedRejected++;
      continue;
    }
    int received = feedUdp.read((uint8_t *)packet, length);
    if (received != length) { feedRejected++; continue; }
    packet[received] = 0;
    if (!acceptFeed(packet, sender)) feedRejected++;
  }
}

class Callbacks : public NimBLEScanCallbacks {
  void onResult(const NimBLEAdvertisedDevice *dev) override {
    if (dev->getManufacturerDataCount() == 0) return;
    std::string addr = dev->getAddress().toString();
    std::string name = dev->getName();
    // A locked H5102 can broadcast its measurement without its device name.
    if (name.empty() && locked && strcasecmp(addr.c_str(), lockedAddr) == 0)
      name = lockedName;
    float t, h;
    int b;
    if (!parse(name, dev->getManufacturerData(), t, h, b)) return;
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
    // An iOS-pinned sensor has no BLE MAC, so fall back by advertised name.
    bool fromIOS = strncmp(lockedAddr, "ios:", 4) == 0;
    bool sameSensor = fromIOS ? strcasecmp(name.c_str(), lockedName) == 0
                              : strcasecmp(addr.c_str(), lockedAddr) == 0;
    if (!sameSensor || remoteFresh()) return;
    portENTER_CRITICAL(&mux);
    temp = t; hum = h; batt = b;
    seq = seq + 1;
    lastHeard = millis();
    localHeardMs = lastHeard;
    latestFromPhone = false;
    portEXIT_CRITICAL(&mux);
  }
  void onScanEnd(const NimBLEScanResults &, int) override { NimBLEDevice::getScan()->start(0, false, true); }
};
static Callbacks callbacks;

static bool stale() {
  // If the last measurement came from the iPhone, it expires with its feed.
  // A previous local BLE measurement must not extend that remote reading's lifetime.
  if (latestFromPhone) return !remoteFresh();
  uint32_t l = localHeardMs;
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
static uint32_t scanUntil = 0, nextScan = 0, seqAtStart = 0;
static uint16_t bursts = 0, burstsHeard = 0, skippedLowMem = 0, borrowedRelay = 0;
static uint32_t lastLowFree = 0, lastLowBlock = 0;

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
  // Give DewPoint time to report before starting a memory-hungry local BLE scan.
  // If no remote data arrives, tick() starts a guarded local scanner after 60s.
}

static void addAccessory(std::vector<uint32_t> &used) {
  // Avoid an unconfigured ghost accessory; first discovery restarts once to add it.
  if (!locked) return;
  inHome = true;
  new SpanAccessory(aidFor(String("govee:") + lockedAddr, used));
    new Service::AccessoryInformation();
      new Characteristic::Identify();
      new Characteristic::Name("Thermometer");
      new Characteristic::Manufacturer("Govee");
      new Characteristic::Model(lockedName[0] ? lockedName : "H5102");
      new Characteristic::SerialNumber(lockedAddr);
    new Temperature();
    new Humidity();
    new Battery();
}

// From the worker: finish the first-boot pick.
static void tick() {
  if (otaActive) { radioStop(); return; }
  if (remoteFresh()) { if (radioOn) radioStop(); return; }
  if (locked) {
    if (radioOn) {
      if ((int32_t)(millis() - scanUntil) >= 0) {
        radioStop();
        bool heard = seq != seqAtStart;
        if (heard) burstsHeard++;
        nextScan = millis() + (heard ? 90000UL : 20000UL);   // missed it: try again soon, not in 2.5 minutes
      }
    } else if (millis() > 45000UL && (int32_t)(millis() - nextScan) >= 0) {
      // Bluetooth takes ~50 KB the moment it starts; starting it with less free tipped the bridge over.
      // Return the MQTT socket/buffer to the heap before refusing the BLE scan.
      // Keep the crash-protection thresholds unchanged.
      if ((ESP.getFreeHeap() <= 75000 || ESP.getMaxAllocHeap() <= 40000) &&
          relayHolding && relayLetGo) {
        relayLetGo();
        borrowedRelay++;
      }
      uint32_t freeNow = ESP.getFreeHeap(), largest = ESP.getMaxAllocHeap();
      if (freeNow > 75000 && largest > 40000) {
        seqAtStart = seq;
        radioStart();
        scanUntil = millis() + 20000UL;
        bursts++;
      } else {
        skippedLowMem++;
        lastLowFree = freeNow; lastLowBlock = largest;
        nextScan = millis() + 10000UL;
      }
    }
    return;
  }
  if (!radioOn) {
    if (millis() - bootMs < 60000UL) return; // wait for remote feed first
    uint32_t available = ESP.getFreeHeap(), block = ESP.getMaxAllocHeap();
    if (available <= 75000 || block <= 40000) {
      skippedLowMem++;
      lastLowFree = available; lastLowBlock = block;
      return;
    }
    radioStart();
    pickStartedMs = millis();
  }
  if (millis() - pickStartedMs < GOVEE_PICK_MS || bestAddr[0] == 0) return;
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
  g["source"] = !stale() ? (latestFromPhone ? "dewpoint" : "localBLE") : "stale";
  g["feedPackets"] = feedAccepted;
  g["feedRejected"] = feedRejected;
  g["feedHost"] = feedHost;
  g["feedAge"] = remotePacketMs ? (int)((millis() - remotePacketMs) / 1000) : -1;
  g["feedActive"] = remoteFresh();
  if (locked) {
    g["name"] = lockedName;
    if (!stale()) { g["temp"] = (float)temp; g["humidity"] = (float)hum; g["battery"] = (int)batt; }
    g["heardAgo"] = lastHeard ? (int)((millis() - lastHeard) / 1000) : -1;
    g["bursts"] = bursts; g["burstsHeard"] = burstsHeard; g["lowMem"] = skippedLowMem;
    g["borrowedRelay"] = borrowedRelay;
    g["freeHeap"] = ESP.getFreeHeap(); g["maxBlock"] = ESP.getMaxAllocHeap();
    if (skippedLowMem) { g["lastSkippedFree"] = lastLowFree; g["lastSkippedBlock"] = lastLowBlock; }
  }
}

}  // namespace govee
#else
namespace govee {   // no Bluetooth on this chip
static const bool radioOn = false;
static const bool inHome = false;
static void radioStop() {}
}  // namespace govee
#endif
