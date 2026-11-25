/*
  Keystone Bridge (started as the Afterglow bridge)
  ESP32 firmware that puts Tuya / Smart Life lights in Apple Home (HomeKit, via HomeSpan) and talks to them
  over the Tuya LAN protocol, no cloud. It also watches a Sony Bravia TV and runs the TV automations you set
  in the Afterglow app (lights off when the TV turns off, with a delay it learns from you), so they work
  without a HomePod / Apple TV and without your phone. Since 1.1 it also switches a Vizio sound bar with the TV
  (set from the Subwave app): SmartCast over Wi-Fi, or a Tuya IR blaster, plus a Sound Bar switch in Home.

  Libraries: HomeSpan 2.x, ArduinoJson 7.x. Board core: arduino-esp32 3.x. Partition: Minimal SPIFFS.

  First boot:
    1. Join the open Wi-Fi "Keystone-Setup" (the page pops up), or use the web installer's Connect to Wi-Fi.
    2. In Afterglow: Settings > Apple Home bridge. It finds the bridge and sends your lights.
    3. Home app > + > Add Accessory > More options > "Keystone Bridge".
  Serial (115200): @i shows status, @R forgets the paired phone so another can pair, @B does the same for Subwave.
*/

#include "HomeSpan.h"
#include <WiFi.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <Preferences.h>
#define ARDUINOJSON_ENABLE_STD_STREAM 0   // no iostreams: keeps the C++ locale code out of flash
#include <ArduinoJson.h>
#include <time.h>
#include <vector>
#include <algorithm>
#include "TuyaLan.h"
#include "Display.h"

#define FW_VERSION "1.11.12"
#include <esp_system.h>
#if __has_include("esp_bt.h")
#include "esp_bt.h"
#define HAVE_BT_RELEASE 1
#endif
#include <nvs.h>
// Crash-loop guard: after two crash restarts in a row the bridge boots without the AC cloud client and the
// remote relay, so lights, Home and the web API (and firmware updates) keep working.
static bool safeMode = false;
static int crashCount = 0;
static const char *bootReason = "power on";
// Breadcrumbs that survive a crash (RTC memory isn't cleared on a panic restart): what each core was doing
// and how much memory was free, so the next boot can say "crashed during X with Y KB free".
struct Crumb { uint32_t magic; char what[20]; uint32_t heap, block, up; };
RTC_NOINIT_ATTR static Crumb crumbWork, crumbHome;
#define CRUMB_MAGIC 0x4B53C0DEu
// A macro, not a function: a function this early makes the Arduino builder put its prototypes above the structs.
// Cheap on purpose: a label and the free-heap counter (O(1)). getMaxAllocHeap() walks the whole heap under its
// lock; calling that in HomeSpan's tight loop starved Wi-Fi on the other core and the bridge went unreachable.
#define markAt(c, w) do { (c).what[0] = 0; strlcpy((c).what, (w), sizeof((c).what)); (c).heap = ESP.getFreeHeap(); \
  (c).block = 0; (c).up = millis() / 1000; (c).magic = CRUMB_MAGIC; } while (0)
// HomeSpan's loop only gets a label, set when it changes: no heap calls there at all.
#define labelAt(c, w) do { if ((c).what[0] != (w)[0]) { strlcpy((c).what, (w), sizeof((c).what)); (c).up = millis() / 1000; (c).magic = CRUMB_MAGIC; } } while (0)
#define mark(w) markAt(crumbWork, w)
static String crashDuring;                       // from the crumbs, at boot
static uint32_t heapAtStart = 0, heapAfterHome = 0, heapEntry = 0, btFreed = 0;   // what Apple Home's accessory list costs
// No Wi-Fi saved yet: boot lean (no Bluetooth, no AC client, no relay) so the setup hotspot has the
// radio and the memory to itself. Everything starts normally on the restart after Wi-Fi is set.
static bool setupOnly = false;
static volatile uint32_t workerBeat = 0;   // the worker's heartbeat (see worker())
// The AC's HTTPS calls need ~50 KB at once. While one runs, the remote relay steps aside (drops its
// connection and its message buffer) so the memory is there.
static volatile bool acNetBusy = false;
static volatile bool relayHolding = false;
static void (*relayLetGo)() = nullptr;
static volatile uint32_t webBeat = 0;
// Track whether HomeSpan has any secure HomeKit controller connections.
// RTC memory bounds automatic recovery to ONE restart per prolonged outage.
RTC_NOINIT_ATTR static uint32_t hapRecoveryMagic, hapRecoveryAttempts;
static const uint32_t HAP_RECOVERY_MAGIC = 0x4B534850UL;
static uint32_t recoveryCount = 0, wifiDrops = 0, wifiReconnects = 0;
static String lastRecovery = "";
static uint32_t wifiConnectedSince = 0;

// Devices switched off in Keystone (prefs "en_<key>"). Off = not in Apple Home, never polled, its memory
// stays free. Read once at boot (turning one on or off restarts the bridge) because Home's accessory list
// is built at boot. The AC and camera switch live, they only gate cloud calls.
static bool enLights = true, enTV = true, enBar = true, enPur = true, enIR = true, enStrip = true, enRouter = true, enGovee = true;
struct Feature { const char *key; bool *flag; };
static Feature features[] = {{"lights", &enLights}, {"tv", &enTV}, {"bar", &enBar}, {"purifier", &enPur},
                             {"ir", &enIR}, {"strip", &enStrip}, {"router", &enRouter}, {"govee", &enGovee}};
static bool acEnabled = true, camEnabled = true;   // switched in Keystone: off = no cloud calls, more free memory   // set by Relay.h: drop the relay and its buffer right now
#define API_PORT 8080
#define POLL_MS 15000UL          // per light when reachable
#define POLL_FAIL_MS 60000UL     // per light after repeated failures
#define TV_POLL_MS 4000UL
#define ECHO_IGNORE_MS 4000UL    // ignore polled state this long after we sent something
#define MAX_SAMPLES 9
#define BAR_POLL_MS 15000UL

// ---------------------------------------------------------------------------------------------
// Config and shared state

struct Light {
  // From the app
  String id, name, key, ip;
  float ver = 3.3;
  bool ks = false;   // added by Keystone (not Afterglow)
  String sw, mode, bri, ct, col;
  int briMin = 10, briMax = 1000, ctMin = 0, ctMax = 1000;
  bool colV1 = false;
  bool relay = false;       // a plain on/off relay or plug: a Switch tile in Home instead of a bulb
  // Live state (guarded by stateLock)
  bool known = false, on = false, colourMode = false, ok = false;
  int pct = 100;            // 1...100
  int mired = 300;          // 153...370
  float hue = 0, sat = 0;   // 0...360, 0...100
  uint32_t lastPoll = 0, lastSent = 0;
  int fails = 0;
};

struct Action {
  String id;
  String dps;   // JSON object text
  bool turnsOff = false;
};

struct Rule {
  bool enabled = false;
  int delay = -1;      // -1 learn
  bool window = false;
  int from = 0, to = 0;
  std::vector<Action> actions;
};

struct Cmd {
  int idx;
  String dps;
  bool manual;     // a person did it (Home app, Siri)
  bool powerOff;   // it switches the light off
  bool powerOn;
};

static std::vector<Light> lights;
static Rule tvOff, tvOn;
static bool lateOffEnabled = false;
static int lateOffAt = 150;
static String tvHost, tvPsk;
static long utcOffset = 0;
static String token;
static bool followTV = true;

// Vizio sound bar, set from the Subwave app (separate token from Afterglow's).
struct BarCfg {
  bool configured = false;
  String name = "Sound Bar", ip, auth, route = "auto";
  int port = 7345;
  String blId, blKey, blIp, blPower;   // blPower: data points that make the blaster send the remote's power toggle
  float blVer = 3.3;
  bool offEnabled = false, offWindow = false, irToggle = false;
  int offDelay = 5, offFrom = 0, offTo = 0;
  bool onEnabled = false, onWindow = false;
  int onFrom = 0, onTo = 0;
  String tvIp, tvPsk;                  // used when Afterglow hasn't set a TV
};
static BarCfg bar;
static String barToken;
static bool barFollow = true;
static bool barInHome = false;         // accessories created at boot
static String barHomeName;
static uint32_t barOffDueMs = 0;
static uint32_t lastBarPoll = 0;
static volatile int barKnown = -1;     // 1 on, 0 off, -1 unknown
static volatile int barWant = -1;      // asked for from Home: 1 on, 0 off
static String barLabel = "not set";
static std::vector<String> barEvents;

static SemaphoreHandle_t stateLock;
static std::vector<Cmd> queue;
static Preferences prefs;
static WebServer server(API_PORT);
// A request can also come from the relay, handled right here without a trip through the web server.
static bool relayFlag = false;
static TaskHandle_t relayTask = nullptr;
#define viaRelay (relayFlag && xTaskGetCurrentTaskHandle() == relayTask)   // only for the task handling it
static String relayTok, relayBody, relayOut, relayMethod;
static int relayCode = 0;
static String reqHeader(const char *n) { return viaRelay ? (String(n) == "X-Device-Token" ? relayTok : String()) : server.header(n); }
static String reqBody() { return viaRelay ? relayBody : server.arg("plain"); }
static bool reqLite() { return viaRelay || server.hasArg("lite"); }
static bool reqPost() { return viaRelay ? relayMethod == "POST" : server.method() == HTTP_POST; }
static void respond(int code, const String &body) {
  if (viaRelay) { relayCode = code; relayOut = body; } else server.send(code, "application/json", body);
}
static bool serverUp = false, mdnsUp = false;

// Events log for the app
static std::vector<String> events;

static String clockText() {
  time_t now = time(nullptr);
  if (now < 1700000000) return "--:--";
  now += utcOffset;
  struct tm t;
  gmtime_r(&now, &t);
  char b[8];
  snprintf(b, sizeof(b), "%02d:%02d", t.tm_hour, t.tm_min);
  return String(b);
}

static void logEvent(const String &s) {
  String line = clockText() + " " + s;
  Serial.println("[afterglow] " + line);
  xSemaphoreTake(stateLock, portMAX_DELAY);
  events.push_back(line);
  if (events.size() > 20) events.erase(events.begin());
  xSemaphoreGive(stateLock);
}

static int minutesNow() {
  time_t now = time(nullptr);
  if (now < 1700000000) return -1;
  now += utcOffset;
  struct tm t;
  gmtime_r(&now, &t);
  return t.tm_hour * 60 + t.tm_min;
}

static bool inWindow(bool use, int from, int to) {
  if (!use) return true;
  int m = minutesNow();
  if (m < 0) return true;   // no clock yet: don't block
  if (from == to) return true;
  if (from < to) return m >= from && m < to;
  return m >= from || m < to;
}

static int findLight(const String &id) {
  for (size_t i = 0; i < lights.size(); i++) if (lights[i].id == id) return (int)i;
  return -1;
}

static void enqueue(const Cmd &c) {
  xSemaphoreTake(stateLock, portMAX_DELAY);
  // A newer command for the same light replaces an unsent one (slider drags).
  for (auto &q : queue) {
    if (q.idx == c.idx && q.manual == c.manual) { q = c; xSemaphoreGive(stateLock); return; }
  }
  queue.push_back(c);
  xSemaphoreGive(stateLock);
}

// ---------------------------------------------------------------------------------------------
// Colour helpers

static void hsvToRgb(float h, float s, float v, int &r, int &g, int &b) {
  float hh = fmodf(h, 360.0f) / 60.0f;
  int i = (int)hh;
  float f = hh - i, p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f));
  float rr, gg, bb;
  switch (i) {
    case 0: rr = v; gg = t; bb = p; break;
    case 1: rr = q; gg = v; bb = p; break;
    case 2: rr = p; gg = v; bb = t; break;
    case 3: rr = p; gg = q; bb = v; break;
    case 4: rr = t; gg = p; bb = v; break;
    default: rr = v; gg = p; bb = q; break;
  }
  r = (int)(rr * 255); g = (int)(gg * 255); b = (int)(bb * 255);
}

// h 0..360, s 0..1, v 0..1
static String colourHex(const Light &L, float h, float s, float v) {
  char buf[20];
  if (L.colV1) {
    int r, g, b;
    hsvToRgb(h, s, v, r, g, b);
    snprintf(buf, sizeof(buf), "%02x%02x%02x%04x%02x%02x", r, g, b, ((int)h) % 361, (int)(s * 255), (int)(v * 255));
  } else {
    snprintf(buf, sizeof(buf), "%04x%04x%04x", ((int)h) % 361, (int)(s * 1000), (int)(max(0.01f, v) * 1000));
  }
  return String(buf);
}

static bool parseColour(const Light &L, const String &hex, float &h, float &s, float &v) {
  if (hex.length() == 14) {
    h = strtol(hex.substring(6, 10).c_str(), nullptr, 16);
    s = strtol(hex.substring(10, 12).c_str(), nullptr, 16) / 255.0f;
    v = strtol(hex.substring(12, 14).c_str(), nullptr, 16) / 255.0f;
    return true;
  }
  if (hex.length() == 12) {
    h = strtol(hex.substring(0, 4).c_str(), nullptr, 16);
    s = strtol(hex.substring(4, 8).c_str(), nullptr, 16) / 1000.0f;
    v = strtol(hex.substring(8, 12).c_str(), nullptr, 16) / 1000.0f;
    return true;
  }
  return false;
}

static int miredFromRaw(const Light &L, int raw) {
  float t = (float)(raw - L.ctMin) / max(1, L.ctMax - L.ctMin);   // 0 warm .. 1 cool
  return (int)(370 - t * (370 - 153));
}

static int rawFromMired(const Light &L, int mired) {
  float t = (370.0f - constrain(mired, 153, 370)) / (370 - 153);
  return L.ctMin + (int)(t * (L.ctMax - L.ctMin));
}

// Applies a dps object (as reported by the light) to its live state.
static void applyDps(Light &L, JsonObject d) {
  if (L.sw.length() && d[L.sw].is<bool>()) L.on = d[L.sw].as<bool>();
  if (L.mode.length() && d[L.mode].is<const char *>()) L.colourMode = String(d[L.mode].as<const char *>()) == "colour";
  if (L.bri.length() && d[L.bri].is<int>() && !L.colourMode) {
    int raw = d[L.bri].as<int>();
    L.pct = constrain((int)lroundf((raw - L.briMin) * 100.0f / max(1, L.briMax - L.briMin)), 1, 100);
  }
  if (L.ct.length() && d[L.ct].is<int>()) L.mired = miredFromRaw(L, d[L.ct].as<int>());
  if (L.col.length() && d[L.col].is<const char *>()) {
    float h, s, v;
    if (parseColour(L, String(d[L.col].as<const char *>()), h, s, v)) {
      L.hue = h; L.sat = s * 100;
      if (L.colourMode) L.pct = constrain((int)lroundf(v * 100), 1, 100);
    }
  }
  if (!L.mode.length() && L.col.length() && !L.bri.length()) L.colourMode = true;
  L.known = true;
}

// ---------------------------------------------------------------------------------------------
// HomeKit

struct AGLight : Service::LightBulb {
  int idx;
  SpanCharacteristic *power;
  SpanCharacteristic *level = nullptr;
  SpanCharacteristic *temp = nullptr;
  SpanCharacteristic *hueC = nullptr;
  SpanCharacteristic *satC = nullptr;

  AGLight(int i) : Service::LightBulb(), idx(i) {
    Light &L = lights[i];
    power = new Characteristic::On(0);
    if (L.bri.length() || L.col.length()) {
      level = new Characteristic::Brightness(100);
      level->setRange(1, 100, 1);
    }
    if (L.ct.length()) {
      temp = new Characteristic::ColorTemperature(300);
      temp->setRange(153, 370, 1);
    }
    if (L.col.length()) {
      hueC = new Characteristic::Hue(0);
      satC = new Characteristic::Saturation(0);
    }
  }

  boolean update() override {
    Light &L = lights[idx];
    JsonDocument d;
    bool wantOn = power->getNewVal();
    bool powerChanged = power->updated();
    if (powerChanged || wantOn) d[L.sw] = wantOn;
    bool colourChange = (hueC && hueC->updated()) || (satC && satC->updated());
    bool tempChange = temp && temp->updated();
    bool levelChange = level && level->updated();

    xSemaphoreTake(stateLock, portMAX_DELAY);
    bool colourMode = L.colourMode;
    float h = L.hue, s = L.sat;
    xSemaphoreGive(stateLock);

    float v = level ? level->getNewVal() / 100.0f : 1.0f;
    if (colourChange && L.col.length()) {
      h = hueC->getNewVal<float>();
      s = satC->getNewVal<float>();
      if (L.mode.length()) d[L.mode] = "colour";
      d[L.col] = colourHex(L, h, s / 100.0f, v);
      colourMode = true;
    } else if (tempChange) {
      if (L.mode.length()) d[L.mode] = "white";
      d[L.ct] = rawFromMired(L, temp->getNewVal());
      if (levelChange && L.bri.length()) d[L.bri] = L.briMin + (int)((L.briMax - L.briMin) * v);
      colourMode = false;
    } else if (levelChange) {
      if (colourMode && L.col.length()) d[L.col] = colourHex(L, h, s / 100.0f, v);
      else if (L.bri.length()) d[L.bri] = L.briMin + (int)((L.briMax - L.briMin) * v);
    }

    xSemaphoreTake(stateLock, portMAX_DELAY);
    L.on = wantOn;
    if (level) L.pct = level->getNewVal();
    if (temp && tempChange) L.mired = temp->getNewVal();
    if (colourChange) { L.hue = h; L.sat = s; }
    L.colourMode = colourMode;
    L.lastSent = millis();
    xSemaphoreGive(stateLock);

    String body;
    serializeJson(d, body);
    enqueue(Cmd{idx, body, true, powerChanged && !wantOn, powerChanged && wantOn});
    return true;
  }

  // Push what polling learned into Home, unless a write is in flight.
  void loop() override {
    Light &L = lights[idx];
    if (millis() - L.lastSent < ECHO_IGNORE_MS) return;
    xSemaphoreTake(stateLock, portMAX_DELAY);
    bool known = L.known, on = L.on;
    int pct = L.pct, mired = L.mired;
    float h = L.hue, s = L.sat;
    xSemaphoreGive(stateLock);
    if (!known) return;
    if (power->getVal() != (int)on) power->setVal(on);
    if (level && level->getVal() != pct) level->setVal(pct);
    if (temp && abs(temp->getVal() - mired) > 2) temp->setVal(mired);
    if (hueC && fabs(hueC->getVal<float>() - h) > 1) hueC->setVal(h);
    if (satC && fabs(satC->getVal<float>() - s) > 1) satC->setVal(s);
  }
};

// A plain relay or plug (no dimming or colour): a Switch tile, so Home and Siri treat it as a switch.
struct AGRelay : Service::Switch {
  int idx;
  SpanCharacteristic *power;
  AGRelay(int i) : Service::Switch(), idx(i) {
    power = new Characteristic::On(0);
    new Characteristic::Name(lights[i].name.c_str());
  }
  boolean update() override {
    Light &L = lights[idx];
    bool wantOn = power->getNewVal();
    String body = String("{\"") + L.sw + "\":" + (wantOn ? "true" : "false") + "}";
    xSemaphoreTake(stateLock, portMAX_DELAY);
    L.on = wantOn;
    L.lastSent = millis();
    xSemaphoreGive(stateLock);
    enqueue(Cmd{idx, body, true, !wantOn, wantOn});
    return true;
  }
  void loop() override {
    Light &L = lights[idx];
    if (millis() - L.lastSent < ECHO_IGNORE_MS) return;
    xSemaphoreTake(stateLock, portMAX_DELAY);
    bool known = L.known, on = L.on;
    xSemaphoreGive(stateLock);
    if (known && power->getVal() != (int)on) power->setVal(on);
  }
};

// "Lights follow TV": lets you pause the TV automation from Home or Siri.
struct FollowSwitch : Service::Switch {
  SpanCharacteristic *on;
  FollowSwitch() : Service::Switch() {
    on = new Characteristic::On(followTV ? 1 : 0);
    new Characteristic::Name("Lights Follow TV");
  }
  boolean update() override {
    followTV = on->getNewVal();
    prefs.putBool("follow", followTV);
    logEvent(String("Lights follow TV ") + (followTV ? "on" : "off"));
    return true;
  }
  void loop() override {   // changed from Keystone
    if (on->getVal() != (int)followTV) on->setVal(followTV);
  }
};

static uint32_t aidFor(const String &id, std::vector<uint32_t> &used) {
  uint32_t a = 2 + (tuya::crc32((const uint8_t *)id.c_str(), id.length()) % 60000);
  while (std::find(used.begin(), used.end(), a) != used.end()) a = 2 + ((a + 1) % 60000);
  used.push_back(a);
  return a;
}

// ---------------------------------------------------------------------------------------------
// Config load / save

static String lightSignature() {
  String s;
  for (auto &L : lights) s += L.id + "|" + L.name + "|" + L.sw + L.mode + L.bri + L.ct + L.col + (L.relay ? "r" : "") + ";";
  return s;
}

static void parseRule(JsonObject o, Rule &r) {
  r.enabled = o["enabled"] | false;
  r.delay = o["delay"] | -1;
  r.window = o["window"] | false;
  r.from = o["from"] | 0;
  r.to = o["to"] | 0;
  r.actions.clear();
  for (JsonObject a : o["actions"].as<JsonArray>()) {
    Action act;
    act.id = a["id"].as<String>();
    JsonObject dps = a["dps"].as<JsonObject>();
    serializeJson(dps, act.dps);
    int i = findLight(act.id);
    if (i >= 0 && lights[i].sw.length() && dps[lights[i].sw].is<bool>()) act.turnsOff = !dps[lights[i].sw].as<bool>();
    r.actions.push_back(act);
  }
}

// Builds `out` from the stored JSON. Rules reference lights by id, so lights load first.
static bool parseConfig(const String &json, std::vector<Light> &out, bool rulesToo) {
  JsonDocument doc;
  if (deserializeJson(doc, json)) return false;
  out.clear();
  for (JsonObject o : doc["lights"].as<JsonArray>()) {
    Light L;
    L.id = o["id"].as<String>();
    L.name = o["name"].as<String>();
    L.key = o["key"].as<String>();
    L.ip = o["ip"].as<String>();
    L.ver = o["ver"] | 3.3f;
    L.sw = o["sw"] | "";
    L.mode = o["mode"] | "";
    L.bri = o["bri"] | "";
    L.ct = o["ct"] | "";
    L.col = o["col"] | "";
    L.briMin = o["briMin"] | 10;
    L.briMax = o["briMax"] | 1000;
    L.ctMin = o["ctMin"] | 0;
    L.ctMax = o["ctMax"] | 1000;
    L.colV1 = o["colV1"] | false;
    L.relay = String(o["kind"] | "") == "switch" && !L.bri.length() && !L.ct.length() && !L.col.length();
    if (L.id.length() && L.sw.length()) out.push_back(L);
  }
  if (rulesToo) {
    utcOffset = doc["utcOffset"] | 0L;
    tvHost = doc["tv"]["ip"] | "";
    tvPsk = doc["tv"]["psk"] | "";
    parseRule(doc["tvOff"].as<JsonObject>(), tvOff);
    parseRule(doc["tvOn"].as<JsonObject>(), tvOn);
    lateOffEnabled = doc["lateOff"]["enabled"] | false;
    lateOffAt = doc["lateOff"]["at"] | 150;
  }
  return true;
}

static String loadStoredConfig() {
  size_t n = prefs.getBytesLength("cfg");
  if (!n) return "";
  String s;
  std::vector<char> b(n + 1, 0);
  prefs.getBytes("cfg", b.data(), n);
  return String(b.data());
}

// Lights and switches Keystone added straight from Smart Life (prefs "kscfg", same JSON as Afterglow's
// "lights" list). They sit alongside Afterglow's; when both have the same device, Keystone's wins.
static String loadKsConfig() {
  size_t n = prefs.getBytesLength("kscfg");
  if (!n) return "";
  std::vector<char> b(n + 1, 0);
  prefs.getBytes("kscfg", b.data(), n);
  return String(b.data());
}

static void mergeKsLights(std::vector<Light> &out) {
  String ks = loadKsConfig();
  if (!ks.length()) return;
  std::vector<Light> mine;
  if (!parseConfig(ks, mine, false)) return;
  for (auto &k : mine) {
    k.ks = true;
    bool replaced = false;
    for (auto &L : out) if (L.id == k.id) {
      // Keystone's generic cloud import may call a relay a Switch while
      // Afterglow explicitly marks that SAME device as lighting. Preserve
      // Keystone's updated IP/local key and DP map, but never erase the
      // user's lighting designation on duplicate-device reconciliation.
      // This does NOT make cloud-only Matter devices controllable via LAN.
      bool isAfterglowLight = !L.relay;
      String customLightName = L.name;
      L = k;
      if (isAfterglowLight && k.relay) {
        L.relay = false;
        if (customLightName.length()) L.name = customLightName;
      }
      replaced = true;
      break;
    }
    if (!replaced) out.push_back(k);
  }
}

// ---------------------------------------------------------------------------------------------
// Learning: how long after the TV goes off do you turn the lights off yourself?

static std::vector<int> samples;
static uint32_t tvOffAtMs = 0;       // when the TV last went off (0 = not in a TV-off episode)
static uint32_t ruleDueMs = 0;       // pending TV-off rule
static uint32_t ruleFiredMs = 0;     // when the TV-off rule last fired
static bool sampledThisEpisode = false;

static void loadSamples() {
  samples.clear();
  int16_t raw[MAX_SAMPLES];
  size_t n = prefs.getBytes("samples", raw, sizeof(raw)) / sizeof(int16_t);
  for (size_t i = 0; i < n; i++) samples.push_back(raw[i]);
}

static void addSample(int secs) {
  secs = constrain(secs, 0, 900);
  samples.push_back(secs);
  while (samples.size() > MAX_SAMPLES) samples.erase(samples.begin());
  int16_t raw[MAX_SAMPLES];
  for (size_t i = 0; i < samples.size(); i++) raw[i] = samples[i];
  prefs.putBytes("samples", raw, samples.size() * sizeof(int16_t));
  logEvent("Learned: lights off " + String(secs) + " s after TV");
}

static int learnedDelay() {
  if (samples.size() < 2) return 60;
  std::vector<int> s = samples;
  std::sort(s.begin(), s.end());
  return s[s.size() / 2];
}

static bool isRuleLight(int idx) {
  for (auto &a : tvOff.actions) if (findLight(a.id) == idx && a.turnsOff) return true;
  return false;
}

// Something switched a light off that the bridge didn't ask for.
static void noteManualOff(int idx) {
  if (!tvOffAtMs || sampledThisEpisode || !isRuleLight(idx)) return;
  uint32_t gap = millis() - tvOffAtMs;
  if (gap > 20UL * 60UL * 1000UL) return;
  sampledThisEpisode = true;
  if (ruleDueMs) { ruleDueMs = 0; logEvent("You beat the timer; skipped"); }
  addSample(gap / 1000);
}

// Turned back on soon after the rule fired: the rule was too early.
static void noteManualOn(int idx) {
  if (!ruleFiredMs || !isRuleLight(idx)) return;
  uint32_t since = millis() - ruleFiredMs;
  if (since > 3UL * 60UL * 1000UL || !tvOffAtMs) return;
  uint32_t firedAfter = (ruleFiredMs - tvOffAtMs) / 1000;
  ruleFiredMs = 0;
  addSample(firedAfter + 180);
}

static void runActions(const Rule &r, const char *why) {
  int n = 0;
  for (auto &a : r.actions) {
    int i = findLight(a.id);
    if (i < 0) continue;
    enqueue(Cmd{i, a.dps, false, a.turnsOff, !a.turnsOff});
    n++;
  }
  logEvent(String(why) + ": " + n + " light" + (n == 1 ? "" : "s"));
}

// ---------------------------------------------------------------------------------------------
// Sound bar

static String tvAddr() { return tvHost.length() ? tvHost : bar.tvIp; }
static String tvKey() { return tvHost.length() ? tvPsk : bar.tvPsk; }

static void barEvent(const String &s) {
  logEvent("Bar: " + s);
  xSemaphoreTake(stateLock, portMAX_DELAY);
  barEvents.push_back(clockText() + " " + s);
  if (barEvents.size() > 12) barEvents.erase(barEvents.begin());
  xSemaphoreGive(stateLock);
}

static bool barHasWifi() { return bar.ip.length() && bar.route != "ir"; }
static bool barHasIR() {
  return bar.blId.length() && bar.blKey.length() == 16 && bar.blIp.length() && bar.blPower.length() && bar.route != "wifi";
}

// SmartCast is HTTPS with a self-signed certificate, on your own network.
// The TLS handshake needs about 35 KB in one piece. With less than that it doesn't fail politely, it takes the
// whole bridge down (crash during "bar poll" at 7 KB free), so it waits for room instead.
#define BAR_TLS_ROOM 40000
static uint32_t barLowMemAt = 0;
static int barHttp(const char *method, const String &path, const String &body, String &out) {
  if (ESP.getMaxAllocHeap() < BAR_TLS_ROOM) {
    if (!barLowMemAt || millis() - barLowMemAt > 600000UL) barEvent("not enough free memory for the sound bar's secure link (" + String(ESP.getMaxAllocHeap() / 1024) + " KB block)");
    barLowMemAt = millis();
    out = "";
    return -1;
  }
  WiFiClientSecure c;
  c.setInsecure();
  HTTPClient http;
  http.setConnectTimeout(1500);
  http.setTimeout(3000);
  if (!http.begin(c, "https://" + bar.ip + ":" + String(bar.port) + path)) return -1;
  if (bar.auth.length()) http.addHeader("AUTH", bar.auth);
  int code;
  if (body.length()) {
    http.addHeader("Content-Type", "application/json");
    code = http.sendRequest(method, body);
  } else {
    code = http.sendRequest(method);
  }
  out = code > 0 ? http.getString() : "";
  http.end();
  return code;
}

static int barReadPower() {   // 1 on, 0 standby, -1 not answering (deep standby drops off Wi-Fi)
  if (!bar.ip.length()) return -1;
  String out;
  if (barHttp("GET", "/state/device/power_mode", "", out) <= 0) return -1;
  JsonDocument d;
  if (deserializeJson(d, out)) return -1;
  JsonVariant items = d["ITEMS"];
  if (items.isNull()) items = d["items"];
  JsonVariant v = items[0]["VALUE"];
  if (v.isNull()) v = items[0]["value"];
  if (v.isNull()) return -1;
  return v.as<int>() ? 1 : 0;
}

static bool barKey(int codeset, int code) {
  String out;
  String body = "{\"KEYLIST\":[{\"CODESET\":" + String(codeset) + ",\"CODE\":" + String(code) + ",\"ACTION\":\"KEYPRESS\"}]}";
  int rc = barHttp("PUT", "/key_command/", body, out);
  out.toUpperCase();
  return rc > 0 && out.indexOf("SUCCESS") >= 0;
}

static bool barIRToggle() {
  tuya::Conn conn;
  bool ok = false;
  for (int attempt = 0; attempt < 2 && !ok; attempt++) {
    if (conn.open(bar.blIp, bar.blId, bar.blKey, bar.blVer)) {
      ok = conn.set(bar.blPower);
      conn.close();
    }
    if (!ok) delay(200);
  }
  if (!ok) barEvent("IR blaster: " + conn.lastError);
  return ok;
}

// Switches the bar and says how, for the log and the app's test buttons.
static String barPower(bool on, bool fromRule) {
  int known = -1;
  if (barHasWifi()) {
    if (barKey(11, on ? 1 : 0)) {
      barKnown = on ? 1 : 0;
      barLabel = on ? "on" : "standby";
      return "Wi-Fi";
    }
    known = barReadPower();
    if (!on && known == -1) { barKnown = 0; barLabel = "off (not answering)"; return "nothing, already asleep"; }
    if (known == (on ? 1 : 0)) { barKnown = known; return String("nothing, already ") + (on ? "on" : "off"); }
  }
  if (barHasIR()) {
    // The remote's power button is a toggle, so only press it when it will go the right way.
    bool press;
    if (known != -1) press = known != (on ? 1 : 0);
    else if (barHasWifi()) press = on;                // on Wi-Fi but not answering: asleep, so only waking needs it
    else press = !fromRule || bar.irToggle;           // no way to read it: rules only if you said the bar ignores the TV
    if (!press) return "nothing (IR toggle is off for TV rules)";
    if (barIRToggle()) {
      barKnown = on ? 1 : 0;
      barLabel = on ? "on (IR)" : "off (IR)";
      return "IR";
    }
    return "failed over IR";
  }
  return barHasWifi() ? "failed over Wi-Fi" : "nothing, not set up";
}

static void pollBar() {
  if (!bar.configured || !barHasWifi()) return;
  if (millis() - lastBarPoll < BAR_POLL_MS) return;
  lastBarPoll = millis();
  if (ESP.getMaxAllocHeap() < BAR_TLS_ROOM) return;   // keep what we knew; don't call it "not answering"
  int r = barReadPower();
  barKnown = r == 1 ? 1 : 0;
  barLabel = r == 1 ? "on" : r == 0 ? "standby" : "off (not answering)";
}

static void barTvOff() {
  if (!bar.configured || !barFollow || !bar.offEnabled || !inWindow(bar.offWindow, bar.offFrom, bar.offTo)) return;
  barOffDueMs = millis() + (uint32_t)max(0, bar.offDelay) * 1000UL;
  if (!barOffDueMs) barOffDueMs = 1;
  barEvent("TV off, bar off in " + String(bar.offDelay) + " s");
}

static void barTvOn() {
  if (barOffDueMs) { barOffDueMs = 0; barEvent("TV back on, kept the bar on"); }
  if (!bar.configured || !barFollow || !bar.onEnabled || !inWindow(bar.onWindow, bar.onFrom, bar.onTo)) return;
  barEvent("TV on, bar on: " + barPower(true, true));
}

static bool parseBarConfig(const String &json) {
  JsonDocument d;
  if (deserializeJson(d, json)) return false;
  BarCfg b;
  b.name = d["bar"]["name"] | "Sound Bar";
  if (!b.name.length()) b.name = "Sound Bar";
  b.ip = d["bar"]["ip"] | "";
  b.port = d["bar"]["port"] | 7345;
  b.auth = d["bar"]["auth"] | "";
  b.route = d["bar"]["route"] | "auto";
  if (d["blaster"].is<JsonObject>()) {
    b.blId = d["blaster"]["id"] | "";
    b.blKey = d["blaster"]["key"] | "";
    b.blIp = d["blaster"]["ip"] | "";
    b.blVer = d["blaster"]["ver"] | 3.3f;
    serializeJson(d["blaster"]["power"], b.blPower);
    if (b.blPower == "null") b.blPower = "";
  }
  b.offEnabled = d["off"]["enabled"] | false;
  b.offDelay = d["off"]["delay"] | 5;
  b.offWindow = d["off"]["window"] | false;
  b.offFrom = d["off"]["from"] | 0;
  b.offTo = d["off"]["to"] | 0;
  b.irToggle = d["off"]["irToggle"] | false;
  b.onEnabled = d["on"]["enabled"] | false;
  b.onWindow = d["on"]["window"] | false;
  b.onFrom = d["on"]["from"] | 0;
  b.onTo = d["on"]["to"] | 0;
  b.tvIp = d["tv"]["ip"] | "";
  b.tvPsk = d["tv"]["psk"] | "";
  b.configured = b.ip.length() > 0 || b.blId.length() > 0;
  if (!d["utcOffset"].isNull() && lights.empty()) utcOffset = d["utcOffset"].as<long>();
  bar = b;
  if (!bar.configured) barLabel = "not set";
  return true;
}

static String loadStoredBarConfig() {
  size_t n = prefs.getBytesLength("barcfg");
  if (!n) return "";
  std::vector<char> b(n + 1, 0);
  prefs.getBytes("barcfg", b.data(), n);
  return String(b.data());
}

// Sound bar in Home: a switch, and one that pauses the TV rule.
struct BarSwitch : Service::Switch {
  SpanCharacteristic *on;
  uint32_t setAt = 0;
  BarSwitch() : Service::Switch() {
    on = new Characteristic::On(0);
    new Characteristic::Name(bar.name.c_str());
  }
  boolean update() override {
    barWant = on->getNewVal() ? 1 : 0;
    setAt = millis();
    return true;
  }
  void loop() override {
    if (millis() - setAt < 10000UL) return;
    int k = barKnown;
    if (k != -1 && on->getVal() != k) on->setVal(k);
  }
};

struct BarFollowSwitch : Service::Switch {
  SpanCharacteristic *on;
  BarFollowSwitch() : Service::Switch() {
    on = new Characteristic::On(barFollow ? 1 : 0);
    new Characteristic::Name("Sound Bar Follows TV");
  }
  boolean update() override {
    barFollow = on->getNewVal();
    prefs.putBool("barFollow", barFollow);
    barEvent(String("follows TV ") + (barFollow ? "on" : "off"));
    if (!barFollow) barOffDueMs = 0;
    return true;
  }
  void loop() override {
    if (on->getVal() != (int)barFollow) on->setVal(barFollow);
  }
};

// ---------------------------------------------------------------------------------------------
// TV

enum TVState { TV_UNKNOWN, TV_ON, TV_OFF };
static TVState tvState = TV_UNKNOWN;
static String tvLabel = "not set";
static int offVotes = 0, onVotes = 0;
static uint32_t lastTvPoll = 0;

static int readTV() {   // 1 on, 0 standby, -1 unreachable
  String host = tvAddr(), psk = tvKey();
  if (!host.length()) return -1;
  WiFiClient c;
  HTTPClient http;
  http.setConnectTimeout(900);
  http.setTimeout(1500);
  if (!http.begin(c, "http://" + host + "/sony/system")) return -1;
  http.addHeader("Content-Type", "application/json");
  if (psk.length()) http.addHeader("X-Auth-PSK", psk);
  int code = http.POST("{\"method\":\"getPowerStatus\",\"id\":50,\"params\":[],\"version\":\"1.0\"}");
  String body = code > 0 ? http.getString() : "";
  http.end();
  if (code <= 0) return -1;
  if (body.indexOf("\"active\"") >= 0) return 1;
  if (body.indexOf("standby") >= 0) return 0;
  return body.indexOf("error") >= 0 ? 1 : -1;
}

static void pollTV() {
  if (!tvAddr().length()) { tvLabel = "not set"; return; }
  if (millis() - lastTvPoll < TV_POLL_MS) return;
  lastTvPoll = millis();
  int r = readTV();
  tvLabel = r == 1 ? "on" : r == 0 ? "standby" : "off (not answering)";
  if (r == 1) { onVotes++; offVotes = 0; } else { offVotes++; onVotes = 0; }
  int needOff = r == -1 ? 3 : 2;

  if (tvState != TV_ON && onVotes >= 2) {
    bool first = tvState == TV_UNKNOWN;
    tvState = TV_ON;
    ruleDueMs = 0;
    tvOffAtMs = 0;
    if (!first) {
      logEvent("TV on");
      barTvOn();
      if (followTV && tvOn.enabled && inWindow(tvOn.window, tvOn.from, tvOn.to)) runActions(tvOn, "TV on");
    }
  } else if (tvState != TV_OFF && offVotes >= needOff) {
    bool first = tvState == TV_UNKNOWN;
    tvState = TV_OFF;
    if (!first) {
      tvOffAtMs = millis();
      sampledThisEpisode = false;
      ruleFiredMs = 0;
      logEvent("TV off");
      barTvOff();
      if (followTV && tvOff.enabled && inWindow(tvOff.window, tvOff.from, tvOff.to)) {
        int d = tvOff.delay < 0 ? learnedDelay() : tvOff.delay;
        ruleDueMs = millis() + (uint32_t)d * 1000UL;
        if (!ruleDueMs) ruleDueMs = 1;
        logEvent("Lights off in " + String(d) + " s" + (tvOff.delay < 0 ? " (learned)" : ""));
      }
    }
  }
}

static void runTimers() {
  if (ruleDueMs && (int32_t)(millis() - ruleDueMs) >= 0) {
    ruleDueMs = 0;
    bool anyOn = false;
    for (auto &a : tvOff.actions) {
      int i = findLight(a.id);
      if (i >= 0 && lights[i].on) anyOn = true;
    }
    if (tvState == TV_OFF && anyOn) {
      ruleFiredMs = millis();
      sampledThisEpisode = true;
      runActions(tvOff, "TV off rule");
    }
  }
  // Late-night sweep, once a day.
  static int lastSweepDay = -1;
  if (lateOffEnabled) {
    int m = minutesNow();
    time_t now = time(nullptr) + utcOffset;
    int day = (int)(now / 86400);
    if (m >= 0 && m >= lateOffAt && m < lateOffAt + 5 && day != lastSweepDay) {
      lastSweepDay = day;
      if (tvState != TV_ON) {
        int n = 0;
        for (size_t i = 0; i < lights.size(); i++) {
          if (!lights[i].on) continue;
          enqueue(Cmd{(int)i, "{\"" + lights[i].sw + "\":false}", false, true, false});
          n++;
        }
        if (n) logEvent("Late-night sweep: " + String(n) + " off");
      }
    }
  }
}

static void runBarTimers() {
  if (barOffDueMs && (int32_t)(millis() - barOffDueMs) >= 0) {
    barOffDueMs = 0;
    if (tvState == TV_OFF) barEvent("TV off rule: " + barPower(false, true));
  }
  int w = barWant;
  if (w != -1) {
    barWant = -1;
    barEvent(String("Home: ") + (w ? "on" : "off") + ", " + barPower(w == 1, false));
  }
}

namespace ac { static bool applyConfig(const String &body); }
namespace cam { static bool applyConfig(const String &body); }
namespace sceneauto { static void loadEquinox(const String &json); }
static void stopBluetoothForOta();
#include "Extras.h"
#include "Govee.h"
static void stopBluetoothForOta() {
  govee::radioStop();
}
#include "AC.h"
#include "Automation.h"
#include "Camera.h"
namespace provision { static String status; }   // Wi-Fi setup progress, drawn by Screen.h, set by Provision.h
#include "Screen.h"
#include "Strip.h"
#include "TuyaDiscover.h"
#include "TuyaApply.h"
static void handleInfo();
namespace control { static void handle(); }
#include "RemoteOTA.h"
#include "LocalOTA.h"
#include "Relay.h"
#include "Provision.h"
#include "Router.h"
#include "Control.h"

// Drop switched-off devices from memory before Home's accessories are built (their saved settings stay).
static void applyFeatures() {
  for (auto &f : features) *f.flag = prefs.getBool((String("en_") + f.key).c_str(), true);
  if (!enLights) lights.clear();
  if (!enTV) { tvHost = ""; bar.tvIp = ""; tvInputs.clear(); }
  if (!enBar) bar.configured = false;
  if (!enPur) pur.configured = false;
  if (!enIR) ir.remotes.clear();
  if (!enStrip) strip::cfg.configured = false;
  if (!enRouter) router::host = "";
}

// ---------------------------------------------------------------------------------------------
// Talking to lights

static void handleEcho(int idx, const String &dps) {
  if (!dps.length() || dps == "{}") return;
  JsonDocument d;
  if (deserializeJson(d, dps)) return;
  Light &L = lights[idx];
  xSemaphoreTake(stateLock, portMAX_DELAY);
  applyDps(L, d.as<JsonObject>());
  L.ok = true;
  L.fails = 0;
  xSemaphoreGive(stateLock);
}

static bool sendCmd(const Cmd &c) {
  if (c.manual) sceneauto::cancelFade(c.idx);
  Light &L = lights[c.idx];
  tuya::Conn conn;
  bool ok = false;
  String echo;
  for (int attempt = 0; attempt < 2 && !ok; attempt++) {
    if (conn.open(L.ip, L.id, L.key, L.ver)) {
      ok = conn.set(c.dps, &echo);
      conn.close();
    }
    if (!ok) delay(150);
  }
  xSemaphoreTake(stateLock, portMAX_DELAY);
  L.lastSent = millis();
  bool before = L.on;
  if (ok) {
    JsonDocument d;
    if (!deserializeJson(d, c.dps)) applyDps(L, d.as<JsonObject>());
    L.ok = true;
    L.fails = 0;
  } else {
    L.fails++;
    if (L.fails >= 3) L.ok = false;
  }
  xSemaphoreGive(stateLock);
  if (ok) handleEcho(c.idx, echo);
  else logEvent(L.name + ": " + conn.lastError);
  if (c.manual && c.powerOff) noteManualOff(c.idx);
  if (c.manual && c.powerOn && !before) noteManualOn(c.idx);
  return ok;
}

static void pollLight(int idx) {
  Light &L = lights[idx];
  uint32_t every = L.fails >= 3 ? POLL_FAIL_MS : POLL_MS;
  if (L.lastPoll && millis() - L.lastPoll < every) return;
  L.lastPoll = millis();
  if (millis() - L.lastSent < ECHO_IGNORE_MS) return;
  std::vector<String> known;
  for (String *dp : {&L.sw, &L.mode, &L.bri, &L.ct, &L.col}) if (dp->length()) known.push_back(*dp);
  tuya::Conn conn;
  String dps;
  if (conn.open(L.ip, L.id, L.key, L.ver)) {
    dps = conn.query(known);
    conn.close();
  }
  if (!dps.length()) {
    xSemaphoreTake(stateLock, portMAX_DELAY);
    L.fails++;
    if (L.fails >= 3) L.ok = false;
    xSemaphoreGive(stateLock);
    return;
  }
  JsonDocument d;
  if (deserializeJson(d, dps)) return;
  xSemaphoreTake(stateLock, portMAX_DELAY);
  bool wasKnown = L.known, wasOn = L.on;
  applyDps(L, d.as<JsonObject>());
  L.ok = true;
  L.fails = 0;
  bool nowOn = L.on;
  xSemaphoreGive(stateLock);
  // Changed outside the bridge (Afterglow app, Smart Life, wall switch).
  if (wasKnown && wasOn && !nowOn) noteManualOff(idx);
  if (wasKnown && !wasOn && nowOn) noteManualOn(idx);
}

// ---------------------------------------------------------------------------------------------
// HTTP API for the app

static bool authorized() {
  return token.length() && server.header("X-Afterglow-Token") == token;
}

static void handleInfo() {
  JsonDocument d;
  d["app"] = "afterglow-bridge";
  d["version"] = FW_VERSION;
  d["claimed"] = token.length() > 0;
  JsonArray ls = d["lights"].to<JsonArray>();
  xSemaphoreTake(stateLock, portMAX_DELAY);
  for (auto &L : lights) {
    JsonObject o = ls.add<JsonObject>();
    o["id"] = L.id;
    o["name"] = L.name;
    if (L.known) { o["on"] = L.on; o["bri"] = L.pct; }
    o["ok"] = L.ok;
    if (L.ks) o["ks"] = true;
    if (!L.ip.length()) o["noIP"] = true;
  }
  bool lite = reqLite();
  if (!lite) {
    JsonArray ev = d["events"].to<JsonArray>();
    for (auto &e : events) ev.add(e);
  }
  xSemaphoreGive(stateLock);
  d["tv"]["state"] = tvLabel;
  d["tv"]["host"] = tvHost;
  d["learnedDelay"] = learnedDelay();
  d["samples"] = (int)samples.size();
  d["uptime"] = (int)(millis() / 1000);
  d["time"] = clockText();
  d["followTV"] = followTV;
  extrasInfo(d);
  screen::info(d);
  ac::info(d);
  strip::info(d);
  cam::info(d);
  d["boot"]["reason"] = bootReason;
  d["boot"]["crashes"] = crashCount;
  d["boot"]["safeMode"] = safeMode;
  auto hap = homeSpan.getStatus();
  d["homekit"]["status"] = homeSpan.statusString(hap.first);
  d["homekit"]["connected"] = (hap.first == HS_CONNECTED);
  d["homekit"]["statusSeconds"] = hap.second;
  d["homekit"]["recoveries"] = recoveryCount;
  d["homekit"]["recoveryUsedThisOutage"] = (hapRecoveryAttempts != 0);
  d["homekit"]["wifiDrops"] = wifiDrops;
  d["homekit"]["wifiReconnects"] = wifiReconnects;
  if (lastRecovery.length()) d["homekit"]["lastRecovery"] = lastRecovery;
  d["boot"]["minHeap"] = ESP.getMinFreeHeap();
  d["heap"] = ESP.getFreeHeap();
  d["heapBlock"] = ESP.getMaxAllocHeap();
  if (crashDuring.length()) d["boot"]["during"] = crashDuring;
  if (heapAtStart) { d["boot"]["heapEntry"] = heapEntry; d["boot"]["btFreed"] = btFreed; d["boot"]["heapStart"] = heapAtStart; d["boot"]["heapAfterHome"] = heapAfterHome; }
#ifdef HAS_GOVEE
  d["boot"]["bluetooth"] = (bool)govee::radioOn;
#endif
  if (safeMode && d["ac"].is<JsonObject>()) d["ac"]["error"] = "paused: bridge was crash-looping (safe mode)";
  relay::info(d);
  remoteota::info(d);
  router::info(d);
  d["auth"] = screen::adminOK();
  d["features"]["ac"] = acEnabled; d["features"]["cam"] = camEnabled;
  for (auto &f : features) d["features"][f.key] = *f.flag;   // does the bridge know the phone asking? (false after a reset)
#ifdef HAS_GOVEE
  govee::info(d);
#endif
  JsonObject b = d["bar"].to<JsonObject>();
  b["claimed"] = barToken.length() > 0;
  b["configured"] = bar.configured;
  b["state"] = barLabel;
  b["follow"] = barFollow;
  if (!lite) {
    JsonArray be = b["events"].to<JsonArray>();
    xSemaphoreTake(stateLock, portMAX_DELAY);
    for (auto &e : barEvents) be.add(e);
    xSemaphoreGive(stateLock);
  }
  String out;
  serializeJson(d, out);
  respond(200, out);
}

static void handleClaim() {
  if (token.length()) { server.send(409, "application/json", "{\"error\":\"already paired\"}"); return; }
  char b[33];
  for (int i = 0; i < 16; i++) snprintf(b + i * 2, 3, "%02x", (unsigned)(esp_random() & 0xff));
  token = String(b);
  prefs.putString("token", token);
  logEvent("Paired with a phone");
  server.send(200, "application/json", "{\"token\":\"" + token + "\"}");
}

static void handleConfig() {
  if (!authorized()) { server.send(401, "application/json", "{\"error\":\"unauthorized\"}"); return; }
  String body = server.arg("plain");
  std::vector<Light> fresh;
  if (!parseConfig(body, fresh, false)) { server.send(400, "application/json", "{\"error\":\"bad json\"}"); return; }
  prefs.putBytes("cfg", body.c_str(), body.length());
  mergeKsLights(fresh);
  if (!enLights) fresh.clear();   // switched off in Keystone: saved for later, not used

  String oldSig = lightSignature();
  String newSig;
  for (auto &L : fresh) newSig += L.id + "|" + L.name + "|" + L.sw + L.mode + L.bri + L.ct + L.col + (L.relay ? "r" : "") + ";";
  bool restart = oldSig != newSig;
  {
    // The TV tile (name, inputs, or TV added/removed) also needs a restart for Home.
    JsonDocument td;
    String host;
    if (!deserializeJson(td, body)) host = td["tv"]["ip"] | "";
    if (!host.length()) host = bar.tvIp;
    String n;
    std::vector<TVInput> ins;
    parseTVExtras(body, n, ins);
    if (enTV && tvSignature(host, n, ins) != tvHomeSig) restart = true;
  }
  if (!restart) {
    // Same accessories: update addresses, keys and rules in place.
    xSemaphoreTake(stateLock, portMAX_DELAY);
    for (size_t i = 0; i < lights.size() && i < fresh.size(); i++) {
      lights[i].ip = fresh[i].ip;
      lights[i].key = fresh[i].key;
      lights[i].ver = fresh[i].ver;
      lights[i].briMin = fresh[i].briMin; lights[i].briMax = fresh[i].briMax;
      lights[i].ctMin = fresh[i].ctMin; lights[i].ctMax = fresh[i].ctMax;
      lights[i].colV1 = fresh[i].colV1;
      lights[i].fails = 0;
    }
    xSemaphoreGive(stateLock);
    std::vector<Light> scratch;
    parseConfig(body, scratch, true);
    sceneauto::loadAfterglow(body);
    logEvent("Config updated");
  } else {
    logEvent("Lights changed, restarting");
  }
  server.send(200, "application/json", String("{\"ok\":true,\"restart\":") + (restart ? "true" : "false") + "}");
  if (restart) {
    delay(800);
    ESP.restart();
  }
}

// Keystone's own list of lights and switches: {"lights":[...]} in Afterglow's format. Replaces the
// previous Keystone list; Afterglow's lights stay. Restarts only if Home's accessory list changes.
static void handleKsLights() {
  if (!screen::adminOK()) { respond(401, "{\"error\":\"unauthorized\"}"); return; }
  String body = reqBody();
  std::vector<Light> check;
  if (!parseConfig(body, check, false)) { respond(400, "{\"error\":\"bad json\"}"); return; }
  JsonDocument requested;
  if (deserializeJson(requested, body) || !requested["lights"].is<JsonArray>() ||
      requested["lights"].as<JsonArray>().size() != check.size()) {
    respond(422, "{\"error\":\"one or more devices lacks a valid ID or on/off data point; existing Home configuration was not changed\"}");
    return;
  }
  if (!enLights && !check.empty()) {
    respond(409, "{\"error\":\"Lights and switches are disabled under Bridge features; enable them before sending\"}");
    return;
  }
  // Never acknowledge an unsaved configuration. An NVS write failure previously
  // returned 200 and restarted, losing the requested devices.
  if (check.empty()) {
    prefs.remove("kscfg");
  } else if (prefs.putBytes("kscfg", body.c_str(), body.length()) != body.length()) {
    respond(507, "{\"error\":\"could not save Keystone accessory list (NVS full or write failed)\"}");
    return;
  }
  std::vector<Light> fresh;
  String cfg = loadStoredConfig();
  if (cfg.length()) parseConfig(cfg, fresh, false);
  mergeKsLights(fresh);
  if (!enLights) fresh.clear();
  String newSig;
  for (auto &L : fresh) newSig += L.id + "|" + L.name + "|" + L.sw + L.mode + L.bri + L.ct + L.col + (L.relay ? "r" : "") + ";";
  bool restart = lightSignature() != newSig;
  if (!restart) {
    xSemaphoreTake(stateLock, portMAX_DELAY);
    for (size_t i = 0; i < lights.size() && i < fresh.size(); i++) {
      lights[i].ip = fresh[i].ip; lights[i].key = fresh[i].key; lights[i].ver = fresh[i].ver;
      lights[i].fails = 0;
    }
    xSemaphoreGive(stateLock);
    logEvent("Keystone updated its lights");
  } else {
    logEvent("Keystone changed the lights, restarting");
  }
  respond(200, String("{\"ok\":true,\"restart\":") + (restart ? "true" : "false") + ",\"count\":" + String(check.size()) + "}");
  if (restart) { if (viaRelay) screen::pendingAction = 1; else { delay(800); ESP.restart(); } }
}

static void handleRun() {
  if (!authorized()) { server.send(401, "application/json", "{\"error\":\"unauthorized\"}"); return; }
  JsonDocument d;
  if (deserializeJson(d, server.arg("plain"))) { server.send(400, "application/json", "{\"error\":\"bad json\"}"); return; }
  Rule r;
  parseRule(d.as<JsonObject>(), r);
  int fade = constrain(d["fade"] | 0, 0, 1800);
  if (fade >= 10) {
    sceneauto::RuleEntry scene;
    scene.name = d["name"] | "Scene";
    scene.fade = fade;
    scene.lightAction = r;
    sceneauto::runLights(scene);
  } else {
    runActions(r, "App");
  }
  server.send(200, "application/json", "{\"ok\":true}");
}

static bool barAuthorized() {
  return barToken.length() && server.header("X-Subwave-Token") == barToken;
}

static void handleBarClaim() {
  if (barToken.length()) { server.send(409, "application/json", "{\"error\":\"already paired\"}"); return; }
  char b[33];
  for (int i = 0; i < 16; i++) snprintf(b + i * 2, 3, "%02x", (unsigned)(esp_random() & 0xff));
  barToken = String(b);
  prefs.putString("bartoken", barToken);
  barEvent("paired with Subwave");
  server.send(200, "application/json", "{\"token\":\"" + barToken + "\"}");
}

static void handleBarConfig() {
  if (!barAuthorized()) { server.send(401, "application/json", "{\"error\":\"unauthorized\"}"); return; }
  String body = server.arg("plain");
  if (!parseBarConfig(body)) { server.send(400, "application/json", "{\"error\":\"bad json\"}"); return; }
  prefs.putBytes("barcfg", body.c_str(), body.length());
  lastBarPoll = 0;
  // Home only learns about new or renamed accessories on a restart.
  if (!enBar) bar.configured = false;   // switched off in Keystone: saved, not used
  bool restart = bar.configured != barInHome || (barInHome && bar.name != barHomeName);
  barEvent(restart ? "set up, restarting for Home" : "config updated");
  server.send(200, "application/json", String("{\"ok\":true,\"restart\":") + (restart ? "true" : "false") + "}");
  if (restart) {
    delay(800);
    ESP.restart();
  }
}

static void handleBarPower() {
  if (!barAuthorized()) { server.send(401, "application/json", "{\"error\":\"unauthorized\"}"); return; }
  JsonDocument d;
  if (deserializeJson(d, server.arg("plain"))) { server.send(400, "application/json", "{\"error\":\"bad json\"}"); return; }
  bool on = d["on"] | false;
  String via = barPower(on, false);
  barEvent(String("app test ") + (on ? "on" : "off") + ": " + via);
  JsonDocument r;
  r["ok"] = true;
  r["via"] = via;
  String out;
  serializeJson(r, out);
  server.send(200, "application/json", out);
}

// Wi-Fi can recover on a new DHCP address while HomeSpan's independent HAP
// listener already works. The old one-shot serverUp flag left port 8080 bound
// to a dead socket forever; keep routes registered, but re-open the TCP listener.
static bool webRoutesRegistered = false;
static IPAddress webBoundIP;
static uint32_t webRebinds = 0;
static void startNetworkServices() {
  if (WiFi.status() != WL_CONNECTED) return;
  const IPAddress currentIP = WiFi.localIP();
  if (serverUp && currentIP != webBoundIP) {
    server.stop();
    serverUp = false;
    webRebinds++;
    logEvent("API: DHCP address changed; reopening HTTP listener");
  }
  if (!webRoutesRegistered) {
    const char *headers[] = {"X-Afterglow-Token", "X-Subwave-Token", "X-Device-Token"};
    server.collectHeaders(headers, 3);
    server.on("/api/info", HTTP_GET, handleInfo);
    server.on("/api/claim", HTTP_POST, handleClaim);
    server.on("/api/config", HTTP_POST, handleConfig);
    server.on("/api/ks/lights", HTTP_POST, handleKsLights);
    server.on("/api/tuya/seen", HTTP_GET, handleTuyaSeen);
    server.on("/api/run", HTTP_POST, handleRun);
    server.on("/api/bar/claim", HTTP_POST, handleBarClaim);
    server.on("/api/bar/config", HTTP_POST, handleBarConfig);
    server.on("/api/bar/power", HTTP_POST, handleBarPower);
    registerExtraRoutes();
    screen::registerRoutes();
    strip::registerRoutes();
    server.on("/api/remote", HTTP_GET, relay::handleApi);
    server.on("/api/remote", HTTP_POST, relay::handleApi);
    server.on("/api/control", HTTP_POST, control::handle);
    server.onNotFound([]() { server.send(404, "text/plain", "Keystone Bridge"); });
    webRoutesRegistered = true;
    tuyadisc::onSeen = applySeen;
    tuyadisc::busy = []() { return (bool)otaActive; };
    otaStarting = tuyadisc::close;
    configTime(0, 0, "pool.ntp.org", "time.google.com");
  }
  if (!serverUp) {
    server.begin();
    serverUp = true;
    webBoundIP = currentIP;
    logEvent("API listening at " + currentIP.toString() + ":" + String(API_PORT));
  }
  // Do not call MDNS.end(): it would disrupt HomeSpan's working _hap._tcp
  // service. HomeSpan owns mDNS; we add our service only once.
  if (!mdnsUp) {
    mdnsUp = MDNS.addService("afterglow", "tcp", API_PORT);
    if (mdnsUp) MDNS.addServiceTxt("afterglow", "tcp", "v", FW_VERSION);
  }
}

// ---------------------------------------------------------------------------------------------
// Status screen (boards with a built-in OLED)


// ---------------------------------------------------------------------------------------------
// Worker task: everything that touches the network besides HomeKit itself.

// Watchdog for the worker: if it stops looping (a stuck socket, a hung request) the web API and the
// automations stop too, so the bridge restarts itself. Firmware uploads are allowed to take longer.
// A public DNS outage must not reset the locally connected Apple Home bridge.
// Restart only when Wi-Fi association is actually lost for three minutes.
static void netWatch() {
  static uint32_t lost = 0, last = 0;
  static bool previouslyConnected = false;
  uint32_t now = millis();
  if (otaActive || setupOnly || now - last < 10000UL) return;
  last = now;
  bool connected = WiFi.status() == WL_CONNECTED;
  if (connected != previouslyConnected) {
    previouslyConnected = connected;
    if (connected) {
      if (wifiDrops) wifiReconnects++;
      wifiConnectedSince = now;
      // Keep a mains-powered HomeKit bridge responsive to TCP and mDNS packets.
      WiFi.setSleep(false);
      logEvent("Wi-Fi associated: " + WiFi.localIP().toString());
    } else {
      wifiDrops++;
      wifiConnectedSince = 0;
      // Socket listeners created before a Wi-Fi reconnect can remain attached
      // to the defunct interface. Close just Keystone's API; never touch the
      // independent HomeKit listener or its mDNS registration.
      if (serverUp) {
        server.stop();
        serverUp = false;
        webRebinds++;
      }
      logEvent("Wi-Fi disconnected; local API will rebind after reassociation");
    }
  }
  if (connected) { lost = 0; return; }
  if (!lost) lost = now;
  if (now - lost >= 180000UL) {
    lastRecovery = "Wi-Fi disconnected for 3 minutes";
    prefs.putString("autoRecovery", lastRecovery);
    prefs.putUInt("autoRecoveryCount", ++recoveryCount);
    logEvent("Wi-Fi lost for 3 minutes; restarting without erasing settings");
    ESP.restart();
  }
}

static void worker(void *) {
  size_t next = 0;
  uint32_t lastNet = 0, lastDraw = 0;
  for (;;) {
    workerBeat = millis();
    mark("screen");
    if (millis() - lastDraw > 500) { lastDraw = millis(); screen::draw(); }
    mark("network start");
    if (millis() - lastNet > 3000) { lastNet = millis(); startNetworkServices(); }
    mark("web request");
    if (serverUp) { server.handleClient(); webBeat = millis(); }
#ifdef HAS_GOVEE
    mark("govee feed"); if (enGovee) govee::pollFeed();
#endif
    mark("remote ota"); if (remoteota::poll()) { vTaskDelay(pdMS_TO_TICKS(200)); continue; }
    mark("relay"); relay::poll();
    mark("router"); router::follow();
    mark("tuya announce"); tuyadisc::poll();
    mark("wifi watch"); netWatch();
    if (WiFi.status() != WL_CONNECTED) { vTaskDelay(pdMS_TO_TICKS(200)); continue; }

    // Commands first, they're what a person is waiting on.
    Cmd c{-1, "", false, false, false};
    xSemaphoreTake(stateLock, portMAX_DELAY);
    if (!queue.empty()) { c = queue.front(); queue.erase(queue.begin()); }
    xSemaphoreGive(stateLock);
    if (c.idx >= 0) {
      mark("light command");
      sendCmd(c);
      continue;
    }

#ifdef HAS_GOVEE
    mark("bluetooth"); if (enGovee) govee::tick();
#endif
    mark("ac"); ac::step();
    mark("camera"); cam::step();
    mark("power strip"); if (strip::step()) continue;
    mark("purifier/ir"); if (runExtras()) continue;
    mark("tv poll"); pollTV();
    mark("timers"); runTimers();
    mark("scenes"); sceneauto::tick();
    mark("bar timers"); runBarTimers();
    mark("bar poll"); pollBar();
    if (!lights.empty()) {
      mark("light poll");
      pollLight(next % lights.size());
      next++;
    }
    mark("idle");
    vTaskDelay(pdMS_TO_TICKS(40));
  }
}

// ---------------------------------------------------------------------------------------------
// Serial commands

static void showInfo(const char *) {
  Serial.printf("Keystone Bridge %s, %d lights, TV: %s, learned delay %d s (%d samples), paired: %s, follow TV: %s\n",
                FW_VERSION, (int)lights.size(), tvLabel.c_str(), learnedDelay(), (int)samples.size(),
                token.length() ? "yes" : "no", followTV ? "yes" : "no");
  for (auto &L : lights)
    Serial.printf("  %-24s %-15s v%.1f %s %s\n", L.name.c_str(), L.ip.c_str(), L.ver, L.known ? (L.on ? "on" : "off") : "?", L.ok ? "" : "(not answering)");
  for (auto &e : events) Serial.println("  " + e);
  Serial.printf("Sound bar: %s, %s, Wi-Fi %s, IR %s, follows TV: %s, Subwave paired: %s\n", bar.configured ? bar.name.c_str() : "not set",
                barLabel.c_str(), barHasWifi() ? bar.ip.c_str() : "-", barHasIR() ? bar.blIp.c_str() : "-",
                barFollow ? "yes" : "no", barToken.length() ? "yes" : "no");
}

static void resetPairing(const char *) {
  token = "";
  prefs.remove("token");
  Serial.println("Pairing cleared. Open Afterglow > Apple Home bridge to pair again.");
}

static void resetBarPairing(const char *) {
  barToken = "";
  prefs.remove("bartoken");
  Serial.println("Subwave pairing cleared. Open Subwave > Follow the TV to pair again.");
}

// ---------------------------------------------------------------------------------------------

void setup() {
  // The chip keeps a block of RAM reserved for classic Bluetooth. This firmware only ever listens with
  // Bluetooth Low Energy (Govee), so hand that block back before anything else takes the heap.
  heapEntry = ESP.getFreeHeap();
#ifdef HAVE_BT_RELEASE
  esp_bt_controller_mem_release(ESP_BT_MODE_CLASSIC_BT);
#endif
  btFreed = ESP.getFreeHeap() > heapEntry ? ESP.getFreeHeap() - heapEntry : 0;
  Serial.begin(115200);
  oled::begin();
  stateLock = xSemaphoreCreateMutex();
  prefs.begin("afterglow", false);
  remoteota::begin();
  remoteota::earlyBoot(); // isolated internet OTA before HomeSpan and nonessential devices
  localota::earlyBoot();  // authenticated local upload-only boot (preserves HomeKit NVS)
  // Remember a HomeKit recovery across software restart, but not power-on.
  esp_reset_reason_t initialReason = esp_reset_reason();
  if (hapRecoveryMagic != HAP_RECOVERY_MAGIC ||
      initialReason == ESP_RST_POWERON || initialReason == ESP_RST_BROWNOUT) {
    hapRecoveryMagic = HAP_RECOVERY_MAGIC;
    hapRecoveryAttempts = 0;
  }
  lastRecovery = prefs.getString("autoRecovery", "");
  recoveryCount = prefs.getUInt("autoRecoveryCount", 0);
  token = prefs.getString("token", "");
  followTV = prefs.getBool("follow", true);
  barToken = prefs.getString("bartoken", "");
  barFollow = prefs.getBool("barFollow", true);
  String barCfg = loadStoredBarConfig();
  if (barCfg.length()) parseBarConfig(barCfg);
  loadSamples();
  String cfg = loadStoredConfig();
  if (cfg.length()) {
    parseConfig(cfg, lights, false);
    std::vector<Light> scratch;
    parseConfig(cfg, scratch, true);
    sceneauto::loadAfterglow(cfg);
  }
  mergeKsLights(lights);
  loadExtras(cfg);
  {
    esp_reset_reason_t r = esp_reset_reason();
    bool crashed = r == ESP_RST_PANIC || r == ESP_RST_INT_WDT || r == ESP_RST_TASK_WDT || r == ESP_RST_WDT;
    bootReason = r == ESP_RST_PANIC ? "crash" : r == ESP_RST_INT_WDT || r == ESP_RST_TASK_WDT || r == ESP_RST_WDT ? "watchdog"
               : r == ESP_RST_BROWNOUT ? "brownout" : r == ESP_RST_SW ? "restart" : r == ESP_RST_POWERON ? "power on" : "other";
    if (crashed) {
      auto txt = [](Crumb &c, const char *core) -> String {
        if (c.magic != CRUMB_MAGIC) return "";
        c.what[sizeof(c.what) - 1] = 0;
        String m = String(core) + ": " + c.what;
        if (c.heap) m += " (free " + String(c.heap / 1024) + " KB)";
        return m + " (up " + String(c.up) + " s)";
      };
      String w = txt(crumbWork, "worker"), h = txt(crumbHome, "home");
      crashDuring = w + (w.length() && h.length() ? "; " : "") + h;
    }
    crumbWork.magic = crumbHome.magic = 0;
    crumbHome.heap = 0; crumbHome.what[0] = 0;   // the home crumb only ever carries a label
    crashCount = crashed ? prefs.getInt("crashes", 0) + 1 : 0;
    prefs.putInt("crashes", crashCount);
    safeMode = crashCount >= 2;
    if (safeMode) Serial.println("[afterglow] crash loop: safe mode (no AC client, no relay)");
  }
  {
    nvs_handle_t h;
    size_t len = 0;
    setupOnly = !(nvs_open("WIFI", NVS_READONLY, &h) == ESP_OK && nvs_get_blob(h, "WIFIDATA", NULL, &len) == ESP_OK && len > 0);
    if (len) nvs_close(h);
    if (setupOnly) { Serial.println("[keystone] no Wi-Fi saved: lean setup boot"); }
  }
  acEnabled = prefs.getBool("en_ac", true); camEnabled = prefs.getBool("en_cam", true);
  ac::load();
  strip::load();
  sceneauto::loadEquinox(readFile("/equinox.json"));
  cam::load();
  relay::begin();
  router::begin();
  applyFeatures();
#ifdef HAS_GOVEE
  if (!setupOnly && enGovee) govee::begin();
#endif

  homeSpan.enableAutoStartAP();
  homeSpan.setApFunction(provision::run);
  homeSpan.setSketchVersion(FW_VERSION);
  screen::bridgeName = prefs.getString("bridgeName", "Keystone Bridge");
  screen::load();
  heapAtStart = ESP.getFreeHeap();
  homeSpan.begin(Category::Bridges, screen::bridgeName.c_str(), "afterglow");
  new SpanUserCommand('i', "- show lights, TV and learned delay", showInfo);
  new SpanUserCommand('R', "- forget the paired phone", resetPairing);
  new SpanUserCommand('B', "- forget the phone paired from Subwave (sound bar)", resetBarPairing);

  new SpanAccessory(1);
    new Service::AccessoryInformation();
      new Characteristic::Identify();
      new Characteristic::Name(screen::bridgeName.c_str());
      new Characteristic::Manufacturer("soum91");
      new Characteristic::Model("Keystone Bridge");
      new Characteristic::FirmwareRevision(FW_VERSION);

  std::vector<uint32_t> used = {1, 65000, 65001, 65002, 65010};
  for (size_t i = 0; i < lights.size(); i++) {
    new SpanAccessory(aidFor(lights[i].id, used));
      new Service::AccessoryInformation();
        new Characteristic::Identify();
        new Characteristic::Name(lights[i].name.c_str());
        new Characteristic::Manufacturer("Tuya");
        new Characteristic::Model(lights[i].relay ? "Switch" : "Light");
        new Characteristic::SerialNumber(lights[i].id.c_str());
      if (lights[i].relay) new AGRelay(i); else new AGLight(i);
  }

  if (enTV && enLights) {
  new SpanAccessory(65000);
    new Service::AccessoryInformation();
      new Characteristic::Identify();
      new Characteristic::Name("Lights Follow TV");
    new FollowSwitch();
  }

  if (bar.configured) {
    barInHome = true;
    barHomeName = bar.name;
    new SpanAccessory(65001);
      new Service::AccessoryInformation();
        new Characteristic::Identify();
        new Characteristic::Name(bar.name.c_str());
        new Characteristic::Manufacturer("VIZIO");
        new Characteristic::Model("Sound bar");
      new BarSwitch();
    new SpanAccessory(65002);
      new Service::AccessoryInformation();
        new Characteristic::Identify();
        new Characteristic::Name("Sound Bar Follows TV");
      new BarFollowSwitch();
  }

  addExtraAccessories(used);
  ac::addAccessory(used);
  strip::addAccessory(used);
  // The bridge itself in Home: its screen as a switch.
  new SpanAccessory(65020);
    new Service::AccessoryInformation();
      new Characteristic::Identify();
      new Characteristic::Name("Bridge Screen");
      new Characteristic::Manufacturer("soum91");
      new Characteristic::Model("Keystone Bridge");
    new screen::HomeSwitch();
  cam::addAccessory(used);
#ifdef HAS_GOVEE
  if (enGovee) govee::addAccessory(used);
  new SpanUserCommand('G', "- forget the Govee thermometer and pick again", govee::forget);
#endif

  heapAfterHome = ESP.getFreeHeap();
  if (crashDuring.length()) logEvent("Last crash during " + crashDuring);
  xTaskCreatePinnedToCore(worker, "afterglow", 24576, nullptr, 1, nullptr, 0);   // room for the AC's TLS
  Serial.printf("Keystone Bridge %s with %d lights\n", FW_VERSION, (int)lights.size());
}

void loop() {
  labelAt(crumbHome, "apple home");
  homeSpan.poll();
  labelAt(crumbHome, "idle (home loop)");
  // HomeSpan 2.1.8: HS_PAIRED means on Wi-Fi but zero secure HAP sessions.
  // HS_CONNECTED means a HomeKit hub/controller has authenticated. A long
  // HS_PAIRED state often corresponds to all accessories showing No Response.
  static uint32_t lastHapCheck = 0;
  uint32_t now = millis();
  if (!otaActive && !setupOnly && now - lastHapCheck >= 15000UL) {
    lastHapCheck = now;
    auto hap = homeSpan.getStatus();
    if (hap.first == HS_CONNECTED && hap.second >= 300) {
      // Five uninterrupted minutes of health arms recovery for the next outage.
      hapRecoveryAttempts = 0;
    } else if (hap.first == HS_PAIRED && hap.second >= 600 &&
               now >= 900000UL && WiFi.status() == WL_CONNECTED &&
               wifiConnectedSince && now - wifiConnectedSince > 180000UL &&
               hapRecoveryAttempts == 0) {
      // Exactly one settings-preserving reboot during a single outage.
      // If the HomePod/router is down, never reboot in a loop.
      hapRecoveryAttempts = 1;
      lastRecovery = "No secure Apple Home connection for 10 minutes";
      prefs.putString("autoRecovery", lastRecovery);
      prefs.putUInt("autoRecoveryCount", ++recoveryCount);
      Serial.println("[keystone] prolonged HomeKit disconnect; one recovery restart");
      delay(100);
      ESP.restart();
    }
  }
  uint32_t beat = workerBeat;
  uint32_t wb = webBeat;
  if (!otaActive && serverUp && wb && millis() - wb > 60000UL) {
    Serial.println("[keystone] web server stuck for 60 s, restarting");
    delay(100);
    ESP.restart();
  }
  if (beat && millis() - beat > (otaActive ? 300000UL : 90000UL)) {
    Serial.println("[afterglow] worker stuck, restarting");
    delay(100);
    ESP.restart();
  }
  screen::runPending();

  static bool stable = false;
  if (!stable && millis() > 180000UL) { stable = true; if (crashCount) prefs.putInt("crashes", 0); }
}
