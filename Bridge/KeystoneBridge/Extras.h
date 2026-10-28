// More of the house in Apple Home:
//   - Air purifier, sent from Exhale (Tuya local protocol): purifier tile with speed and auto/manual,
//     PM2.5 air quality sensor, filter life, child lock, display switch, and keep-the-display-off.
//   - IR remotes, sent from Redshift (through the Tuya IR blaster): a power switch per remote, plus
//     one-tap buttons. IR can't report state, so the power switch shows what the bridge last sent.
//   - Sony TV (Bravia REST + IRCC), from Afterglow's TV settings: a real Television tile with power,
//     inputs, the Control Center remote and volume.
//   - Firmware updates over Wi-Fi (uploaded by Afterglow).
// Included from AfterglowBridge.ino after its globals; it uses them directly.
#pragma once
#include <LittleFS.h>
#include <Update.h>

#ifndef FW_BUILD
#define FW_BUILD 0
#endif
#if defined(CONFIG_IDF_TARGET_ESP32S3)
#define FW_CHIP "esp32s3"
#elif defined(CONFIG_IDF_TARGET_ESP32C3)
#define FW_CHIP "esp32c3"
#else
#define FW_CHIP "esp32"
#endif

#define PUR_POLL_MS 10000UL

// ---------------------------------------------------------------------------------------------
// Storage (LittleFS on the spiffs partition: IR codes are too big for NVS)

static bool fsUp = false;

static String readFile(const char *path) {
  if (!fsUp) return "";
  File f = LittleFS.open(path, "r");
  if (!f) return "";
  String s = f.readString();
  f.close();
  return s;
}

static void writeFile(const char *path, const String &s) {
  if (!fsUp) return;
  File f = LittleFS.open(path, "w");
  if (!f) return;
  f.print(s);
  f.close();
}

// ---------------------------------------------------------------------------------------------
// Air purifier

struct PurCfg {
  bool configured = false;
  String name = "Air Purifier", id, key, ip;
  float ver = 3.3;
  String sw, pm, mode, modeAuto, modeManual, fan, lock, filter, display;
  std::vector<String> fanVals;   // JSON text of each fan value, slowest first
  float pmDiv = 1;
  int filterMax = 100;
  bool displayInverted = false, keepDisplayOff = false;
};
static PurCfg pur;
static bool purInHome = false;
static String purHomeSig;

struct PurState {
  bool known = false, ok = false, on = false, autoMode = false, locked = false, displayOn = false;
  int fanIdx = -1;
  float pm = -1;
  int filterPct = -1;
  uint32_t lastPoll = 0, lastSent = 0;
  int fails = 0;
};
static PurState ps;

static String purSignature(const PurCfg &p) {
  if (!p.configured) return "";
  return p.id + "|" + p.name + "|" + (p.pm.length() ? "pm" : "") + (p.filter.length() ? "f" : "") + (p.lock.length() ? "l" : "") +
         (p.display.length() ? "d" : "") + (p.fan.length() ? "s" : "") + (p.mode.length() ? "m" : "");
}

static bool parsePurifier(const String &json, PurCfg &out) {
  JsonDocument d;
  if (deserializeJson(d, json)) return false;
  JsonObject o = d["purifier"];
  PurCfg p;
  if (!o.isNull()) {
    p.name = o["name"] | "Air Purifier";
    if (!p.name.length()) p.name = "Air Purifier";
    p.id = o["id"] | ""; p.key = o["key"] | ""; p.ip = o["ip"] | ""; p.ver = o["ver"] | 3.3f;
    p.sw = o["sw"] | ""; p.pm = o["pm"] | ""; p.pmDiv = o["pmDiv"] | 1.0f;
    p.mode = o["mode"] | ""; p.modeAuto = o["modeAuto"] | ""; p.modeManual = o["modeManual"] | "";
    p.fan = o["fan"] | ""; p.lock = o["lock"] | ""; p.filter = o["filter"] | ""; p.filterMax = o["filterMax"] | 100;
    p.display = o["display"] | ""; p.displayInverted = o["displayInverted"] | false; p.keepDisplayOff = o["keepDisplayOff"] | false;
    for (JsonVariant v : o["fanValues"].as<JsonArray>()) { String t; serializeJson(v, t); p.fanVals.push_back(t); }
    if (p.pmDiv <= 0) p.pmDiv = 1;
    p.configured = p.id.length() && p.key.length() == 16 && p.ip.length() && p.sw.length();
  }
  if (!d["utcOffset"].isNull() && lights.empty()) utcOffset = d["utcOffset"].as<long>();
  out = p;
  return true;
}

static void purApply(JsonObject d) {
  if (pur.sw.length() && !d[pur.sw].isNull()) ps.on = d[pur.sw].as<bool>();
  if (pur.mode.length() && d[pur.mode].is<const char *>()) ps.autoMode = String(d[pur.mode].as<const char *>()) == pur.modeAuto;
  if (pur.lock.length() && !d[pur.lock].isNull()) ps.locked = d[pur.lock].as<bool>();
  if (pur.display.length() && !d[pur.display].isNull()) ps.displayOn = d[pur.display].as<bool>() != pur.displayInverted;
  if (pur.pm.length() && !d[pur.pm].isNull()) ps.pm = d[pur.pm].as<float>() / pur.pmDiv;
  if (pur.filter.length() && !d[pur.filter].isNull())
    ps.filterPct = constrain((int)lroundf(d[pur.filter].as<float>() * 100.0f / max(1, pur.filterMax)), 0, 100);
  if (pur.fan.length() && !d[pur.fan].isNull()) {
    String t; serializeJson(d[pur.fan], t);
    for (size_t i = 0; i < pur.fanVals.size(); i++) if (pur.fanVals[i] == t) ps.fanIdx = i;
  }
  ps.known = true;
}

static String purDps(std::initializer_list<std::pair<String, String>> kv) {   // values are JSON text
  String s = "{";
  bool first = true;
  for (auto &p : kv) {
    if (!p.first.length()) continue;
    s += (first ? "\"" : ",\"") + p.first + "\":" + p.second;
    first = false;
  }
  return s + "}";
}

// Queue of things for the purifier, IR blaster and TV. Light commands have their own queue.
struct XCmd {
  int kind;      // 0 purifier dps, 1 IR dps, 2 TV power, 3 TV IRCC, 4 TV input uri
  String a;
  int n = 0;
};
static std::vector<XCmd> xqueue;

static void xenqueue(const XCmd &c, bool replaceSameKind = false) {
  xSemaphoreTake(stateLock, portMAX_DELAY);
  if (replaceSameKind) {
    for (auto &q : xqueue) if (q.kind == c.kind) { q = c; xSemaphoreGive(stateLock); return; }
  }
  if (xqueue.size() < 24) xqueue.push_back(c);
  xSemaphoreGive(stateLock);
}

static int aqLevel(float pm) {   // HomeKit AirQuality 1 excellent .. 5 poor, from US EPA PM2.5 bands
  if (pm < 0) return 0;
  if (pm <= 5) return 1;
  if (pm <= 9) return 2;
  if (pm <= 35.4) return 3;
  if (pm <= 55.4) return 4;
  return 5;
}

struct AGPurifier : Service::AirPurifier {
  SpanCharacteristic *active, *current, *target = nullptr, *speed = nullptr, *lock = nullptr;
  AGPurifier() : Service::AirPurifier() {
    active = new Characteristic::Active(0);
    current = new Characteristic::CurrentAirPurifierState(0);
    if (pur.mode.length() && pur.modeAuto.length() && pur.modeManual.length()) target = new Characteristic::TargetAirPurifierState(0);
    if (pur.fan.length() && !pur.fanVals.empty()) {
      speed = new Characteristic::RotationSpeed(0);
      speed->setRange(0, 100, max(1, 100 / (int)pur.fanVals.size()));
    }
    if (pur.lock.length()) lock = new Characteristic::LockPhysicalControls(0);
    new Characteristic::Name(pur.name.c_str());
  }
  boolean update() override {
    String s = "{";
    auto add = [&](const String &k, const String &v) { if (k.length()) s += (s.length() > 1 ? ",\"" : "\"") + k + "\":" + v; };
    if (active->updated()) { add(pur.sw, active->getNewVal() ? "true" : "false"); ps.on = active->getNewVal(); }
    if (target && target->updated()) {
      bool a = target->getNewVal() == 1;
      add(pur.mode, "\"" + (a ? pur.modeAuto : pur.modeManual) + "\"");
      ps.autoMode = a;
    }
    if (speed && speed->updated() && speed->getNewVal() > 0) {
      int n = pur.fanVals.size();
      int idx = constrain((int)ceilf(speed->getNewVal() * n / 100.0f) - 1, 0, n - 1);
      if (!active->updated() && !ps.on) { add(pur.sw, "true"); ps.on = true; }
      if (!(target && target->updated()) && pur.mode.length() && pur.modeManual.length() && ps.autoMode) {
        add(pur.mode, "\"" + pur.modeManual + "\"");
        ps.autoMode = false;
      }
      add(pur.fan, pur.fanVals[idx]);
      ps.fanIdx = idx;
    }
    if (lock && lock->updated()) { add(pur.lock, lock->getNewVal() ? "true" : "false"); ps.locked = lock->getNewVal(); }
    s += "}";
    ps.lastSent = millis();
    if (s.length() > 2) xenqueue(XCmd{0, s}, false);
    return true;
  }
  void loop() override {
    if (!ps.known || millis() - ps.lastSent < 6000) return;
    if (active->getVal() != (int)ps.on) active->setVal(ps.on);
    int cur = ps.on ? 2 : 0;
    if (current->getVal() != cur) current->setVal(cur);
    if (target && target->getVal() != (int)ps.autoMode) target->setVal(ps.autoMode);
    if (speed && ps.fanIdx >= 0) {
      int v = (int)lroundf((ps.fanIdx + 1) * 100.0f / pur.fanVals.size());
      if (abs(speed->getVal() - v) > 1) speed->setVal(v);
    }
    if (lock && lock->getVal() != (int)ps.locked) lock->setVal(ps.locked);
  }
};

struct AGAirQuality : Service::AirQualitySensor {
  SpanCharacteristic *aq, *pm, *activeC;
  AGAirQuality() : Service::AirQualitySensor() {
    aq = new Characteristic::AirQuality(0);
    pm = new Characteristic::PM25Density(0);
    activeC = new Characteristic::StatusActive(0);
    new Characteristic::Name("Air Quality");
  }
  void loop() override {
    if (activeC->getVal() != (int)ps.ok) activeC->setVal(ps.ok);
    if (ps.pm < 0) return;
    if (fabs(pm->getVal<float>() - ps.pm) >= 0.5f) pm->setVal(ps.pm);
    int l = aqLevel(ps.pm);
    if (aq->getVal() != l) aq->setVal(l);
  }
};

struct AGFilter : Service::FilterMaintenance {
  SpanCharacteristic *life, *change;
  AGFilter() : Service::FilterMaintenance() {
    change = new Characteristic::FilterChangeIndication(0);
    life = new Characteristic::FilterLifeLevel(100);
  }
  void loop() override {
    if (ps.filterPct < 0) return;
    if (life->getVal() != ps.filterPct) life->setVal(ps.filterPct);
    int c = ps.filterPct <= 10 ? 1 : 0;
    if (change->getVal() != c) change->setVal(c);
  }
};

struct AGPurDisplay : Service::Switch {
  SpanCharacteristic *on;
  AGPurDisplay() : Service::Switch() {
    on = new Characteristic::On(0);
    new Characteristic::Name("Purifier Display");
  }
  boolean update() override {
    bool v = on->getNewVal();
    ps.displayOn = v;
    ps.lastSent = millis();
    xenqueue(XCmd{0, purDps({{pur.display, (v != pur.displayInverted) ? "true" : "false"}})});
    return true;
  }
  void loop() override {
    if (!ps.known || millis() - ps.lastSent < 6000) return;
    if (on->getVal() != (int)ps.displayOn) on->setVal(ps.displayOn);
  }
};

static bool tuyaSend(const String &ip, const String &id, const String &key, float ver, const String &dps, String *echo, String &err) {
  tuya::Conn conn;
  for (int attempt = 0; attempt < 2; attempt++) {
    if (conn.open(ip, id, key, ver)) {
      bool ok = conn.set(dps, echo);
      conn.close();
      if (ok) return true;
    }
    delay(150);
  }
  err = conn.lastError;
  return false;
}

static void purHandleDps(const String &dps) {
  if (!dps.length() || dps == "{}") return;
  JsonDocument d;
  if (deserializeJson(d, dps)) return;
  purApply(d.as<JsonObject>());
}

static void pollPurifier() {
  if (!pur.configured) return;
  if (ps.lastPoll && millis() - ps.lastPoll < (ps.fails >= 3 ? 60000UL : PUR_POLL_MS)) return;
  ps.lastPoll = millis();
  if (millis() - ps.lastSent < 4000) return;
  std::vector<String> known;
  for (String *dp : {&pur.sw, &pur.pm, &pur.mode, &pur.fan, &pur.lock, &pur.filter, &pur.display}) if (dp->length()) known.push_back(*dp);
  tuya::Conn conn;
  String dps;
  if (conn.open(pur.ip, pur.id, pur.key, pur.ver)) { dps = conn.query(known); conn.close(); }
  if (!dps.length()) {
    if (++ps.fails >= 3) ps.ok = false;
    return;
  }
  ps.fails = 0;
  ps.ok = true;
  purHandleDps(dps);
  // The firmware lights the display up on its own (setting changes, Wi-Fi drops). Turn it back off.
  if (pur.keepDisplayOff && pur.display.length() && ps.on && ps.displayOn) {
    String err;
    if (tuyaSend(pur.ip, pur.id, pur.key, pur.ver, purDps({{pur.display, pur.displayInverted ? "true" : "false"}}), nullptr, err)) {
      ps.displayOn = false;
      logEvent("Purifier display came on, turned it off");
    }
  }
}

// ---------------------------------------------------------------------------------------------
// IR remotes (Redshift)

struct IRButton { String name, dps; };
struct IRRemote { String id, name, kind, power; std::vector<IRButton> buttons; };
struct IRCfg {
  String id, key, ip;
  float ver = 3.3;
  std::vector<IRRemote> remotes;
  bool configured() const { return id.length() && key.length() == 16 && ip.length() && !remotes.empty(); }
};
static IRCfg ir;
static bool irInHome = false;
static String irHomeSig;

static String irSignature(const IRCfg &c) {
  if (!c.configured()) return "";
  String s;
  for (auto &r : c.remotes) {
    s += r.id + "|" + r.name + "|" + (r.power.length() ? "p" : "");
    for (auto &b : r.buttons) s += "," + b.name;
    s += ";";
  }
  return s;
}

static bool parseIR(const String &json, IRCfg &out) {
  JsonDocument d;
  if (deserializeJson(d, json)) return false;
  IRCfg c;
  c.id = d["blaster"]["id"] | ""; c.key = d["blaster"]["key"] | ""; c.ip = d["blaster"]["ip"] | ""; c.ver = d["blaster"]["ver"] | 3.3f;
  for (JsonObject o : d["remotes"].as<JsonArray>()) {
    IRRemote r;
    r.id = o["id"] | ""; r.name = o["name"] | "Remote"; r.kind = o["kind"] | "custom";
    if (!o["power"].isNull()) serializeJson(o["power"], r.power);
    for (JsonObject b : o["buttons"].as<JsonArray>()) {
      IRButton btn;
      btn.name = b["name"] | "Button";
      serializeJson(b["dps"], btn.dps);
      if (btn.dps.length() > 2 && r.buttons.size() < 8) r.buttons.push_back(btn);
    }
    if (r.id.length() && (r.power.length() || !r.buttons.empty()) && c.remotes.size() < 6) c.remotes.push_back(r);
  }
  out = c;
  return true;
}

struct AGIRPower : Service::Switch {
  int idx;
  SpanCharacteristic *on;
  AGIRPower(int i) : Service::Switch(), idx(i) {
    on = new Characteristic::On(prefs.getBool(("ir" + String(i)).c_str(), false));
    new Characteristic::Name(ir.remotes[i].name.c_str());
  }
  boolean update() override {
    // Power is a toggle on almost every IR remote: one press either way.
    xenqueue(XCmd{1, ir.remotes[idx].power});
    prefs.putBool(("ir" + String(idx)).c_str(), on->getNewVal());
    return true;
  }
};

struct AGIRButton : Service::Switch {
  int r, b;
  SpanCharacteristic *on;
  uint32_t pressedAt = 0;
  AGIRButton(int ri, int bi) : Service::Switch(), r(ri), b(bi) {
    on = new Characteristic::On(0);
    new Characteristic::Name(ir.remotes[ri].buttons[bi].name.c_str());
  }
  boolean update() override {
    if (on->getNewVal()) {
      xenqueue(XCmd{1, ir.remotes[r].buttons[b].dps});
      pressedAt = millis();
    }
    return true;
  }
  void loop() override {   // a button, not a switch: pop back off
    if (pressedAt && millis() - pressedAt > 1200) { pressedAt = 0; on->setVal(0); }
  }
};

// ---------------------------------------------------------------------------------------------
// Sony TV

struct TVInput { String uri, name; };
static std::vector<TVInput> tvInputs;
static String tvName = "TV";
static bool tvInHome = false;
static String tvHomeSig;
static volatile int tvActiveInput = -1;   // index into tvInputs, from polling
static uint32_t tvSetAt = 0;
static uint32_t lastInputPoll = 0;

static String tvSignature(const String &host, const String &name, const std::vector<TVInput> &inputs) {
  if (!host.length()) return "";
  String s = name + "|";
  for (auto &i : inputs) s += i.name + ";";
  return s;
}

static void parseTVExtras(const String &json, String &name, std::vector<TVInput> &inputs) {
  JsonDocument d;
  inputs.clear();
  name = "TV";
  if (deserializeJson(d, json)) return;
  name = d["tv"]["name"] | "TV";
  if (!name.length()) name = "TV";
  for (JsonObject o : d["tv"]["inputs"].as<JsonArray>()) {
    TVInput i;
    i.uri = o["uri"] | "";
    i.name = o["name"] | "";
    if (i.uri.length() && i.name.length() && inputs.size() < 12) inputs.push_back(i);
  }
}

static int braviaCall(const char *service, const String &body, String &out) {
  String host = tvAddr(), psk = tvKey();
  if (!host.length()) return -1;
  WiFiClient c;
  HTTPClient http;
  http.setConnectTimeout(1200);
  http.setTimeout(2500);
  if (!http.begin(c, "http://" + host + "/sony/" + service)) return -1;
  http.addHeader("Content-Type", "application/json");
  if (psk.length()) http.addHeader("X-Auth-PSK", psk);
  int code = http.POST(body);
  out = code > 0 ? http.getString() : "";
  http.end();
  return code;
}

static const char *B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static String b64(const uint8_t *d, size_t n) {
  String s;
  for (size_t i = 0; i < n; i += 3) {
    uint32_t v = d[i] << 16 | (i + 1 < n ? d[i + 1] << 8 : 0) | (i + 2 < n ? d[i + 2] : 0);
    s += B64[(v >> 18) & 63];
    s += B64[(v >> 12) & 63];
    s += i + 1 < n ? B64[(v >> 6) & 63] : '=';
    s += i + 2 < n ? B64[v & 63] : '=';
  }
  return s;
}

// Sony IRCC code: [kind][address][command][03], kind 1 = 12-bit TV, kind 2 = 15-bit with extended address.
static String ircc(int address, int command, bool ext) {
  uint8_t b[13] = {0, 0, 0, (uint8_t)(ext ? 2 : 1), 0, 0, 0, (uint8_t)address, 0, 0, 0, (uint8_t)command, 3};
  return b64(b, sizeof(b));
}

static bool sendIRCC(const String &code) {
  String host = tvAddr(), psk = tvKey();
  if (!host.length()) return false;
  WiFiClient c;
  HTTPClient http;
  http.setConnectTimeout(1200);
  http.setTimeout(2500);
  if (!http.begin(c, "http://" + host + "/sony/IRCC")) return false;
  http.addHeader("Content-Type", "text/xml; charset=UTF-8");
  http.addHeader("SOAPACTION", "\"urn:schemas-sony-com:service:IRCC:1#X_SendIRCC\"");
  if (psk.length()) http.addHeader("X-Auth-PSK", psk);
  String body = "<?xml version=\"1.0\"?><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" "
                "s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body>"
                "<u:X_SendIRCC xmlns:u=\"urn:schemas-sony-com:service:IRCC:1\"><IRCCCode>" + code +
                "</IRCCCode></u:X_SendIRCC></s:Body></s:Envelope>";
  int rc = http.POST(body);
  http.end();
  return rc == 200;
}

// HomeKit RemoteKey -> IRCC
static String remoteKeyCode(int k) {
  switch (k) {
    case 4: return ircc(1, 116, false);    // up
    case 5: return ircc(1, 117, false);    // down
    case 6: return ircc(1, 52, false);     // left
    case 7: return ircc(1, 51, false);     // right
    case 8: return ircc(1, 101, false);    // select
    case 9: return ircc(0x97, 35, true);   // back
    case 10: return ircc(1, 96, false);    // exit -> home
    case 11: return ircc(0x97, 26, true);  // play/pause -> play
    case 15: return ircc(1, 58, false);    // info -> display
  }
  return "";
}

static void pollTVInput() {
  if (tvInputs.empty() || tvState != TV_ON) return;
  if (millis() - lastInputPoll < 15000UL || millis() - tvSetAt < 8000) return;
  lastInputPoll = millis();
  String out;
  if (braviaCall("avContent", "{\"method\":\"getPlayingContentInfo\",\"id\":103,\"params\":[],\"version\":\"1.0\"}", out) != 200) return;
  int found = -1;
  for (size_t i = 0; i < tvInputs.size(); i++) if (out.indexOf("\"" + tvInputs[i].uri + "\"") >= 0) found = i;
  if (found >= 0) tvActiveInput = found;
}

struct AGTV : Service::Television {
  SpanCharacteristic *active, *activeId, *remoteKey;
  AGTV() : Service::Television() {
    active = new Characteristic::Active(0);
    activeId = new Characteristic::ActiveIdentifier(tvInputs.empty() ? 0 : 1);
    remoteKey = new Characteristic::RemoteKey();
    new Characteristic::ConfiguredName(tvName.c_str());
    new Characteristic::SleepDiscoveryMode(1);
    new Characteristic::PowerModeSelection();
  }
  boolean update() override {
    tvSetAt = millis();
    if (active->updated()) xenqueue(XCmd{2, "", active->getNewVal()}, true);
    if (activeId->updated()) {
      int i = activeId->getNewVal() - 1;
      if (i >= 0 && i < (int)tvInputs.size()) { xenqueue(XCmd{4, tvInputs[i].uri}, true); tvActiveInput = i; }
    }
    if (remoteKey->updated()) {
      String c = remoteKeyCode(remoteKey->getNewVal());
      if (c.length()) xenqueue(XCmd{3, c});
    }
    return true;
  }
  void loop() override {
    if (millis() - tvSetAt < 10000UL) return;
    int on = tvState == TV_ON ? 1 : 0;
    if (tvState != TV_UNKNOWN && active->getVal() != on) active->setVal(on);
    int a = tvActiveInput;
    if (a >= 0 && activeId->getVal() != a + 1) activeId->setVal(a + 1);
  }
};

struct AGTVSpeaker : Service::TelevisionSpeaker {
  SpanCharacteristic *vol;
  AGTVSpeaker() : Service::TelevisionSpeaker() {
    new Characteristic::Mute(0);
    new Characteristic::VolumeControlType(1);   // relative
    vol = new Characteristic::VolumeSelector();
  }
  boolean update() override {
    if (vol->updated()) xenqueue(XCmd{3, vol->getNewVal() == 0 ? ircc(1, 18, false) : ircc(1, 19, false)});
    return true;
  }
};

static void addTVAccessory() {
  new SpanAccessory(65010);
    new Service::AccessoryInformation();
      new Characteristic::Identify();
      new Characteristic::Name(tvName.c_str());
      new Characteristic::Manufacturer("Sony");
      new Characteristic::Model("Bravia");
    SpanService *tv = new AGTV();
    SpanService *sp = new AGTVSpeaker();
    tv->addLink(sp);
    for (size_t i = 0; i < tvInputs.size(); i++) {
      SpanService *in = new Service::InputSource();
        new Characteristic::ConfiguredName(tvInputs[i].name.c_str());
        new Characteristic::Identifier(i + 1);
        new Characteristic::IsConfigured(1);
        new Characteristic::CurrentVisibilityState(0);
        new Characteristic::TargetVisibilityState(0);
        new Characteristic::InputSourceType(tvInputs[i].uri.indexOf("hdmi") >= 0 ? 3 : 10);
      tv->addLink(in);
    }
}

// ---------------------------------------------------------------------------------------------
// Running the queue (called from the worker task)

static void runXCmd(const XCmd &c) {
  String err;
  switch (c.kind) {
    case 0: {
      if (!pur.configured) return;
      String echo;
      if (tuyaSend(pur.ip, pur.id, pur.key, pur.ver, c.a, &echo, err)) { ps.ok = true; ps.fails = 0; purHandleDps(echo); }
      else logEvent("Purifier: " + err);
      ps.lastSent = millis();
      break;
    }
    case 1:
      if (!tuyaSend(ir.ip, ir.id, ir.key, ir.ver, c.a, nullptr, err)) logEvent("IR blaster: " + err);
      break;
    case 2: {
      String out;
      String body = String("{\"method\":\"setPowerStatus\",\"id\":55,\"params\":[{\"status\":") + (c.n ? "true" : "false") + "}],\"version\":\"1.0\"}";
      int rc = braviaCall("system", body, out);
      if (rc != 200 || out.indexOf("error") >= 0) {
        // Power via IRCC works even when the API refuses (no PSK / remote start off).
        sendIRCC(c.n ? ircc(1, 46, false) : ircc(1, 47, false));
      }
      logEvent(String("TV ") + (c.n ? "on" : "off") + " from Home");
      break;
    }
    case 3:
      if (!sendIRCC(c.a)) logEvent("TV remote key failed (check IP control and the PSK)");
      break;
    case 4: {
      String out;
      braviaCall("avContent", "{\"method\":\"setPlayContent\",\"id\":101,\"params\":[{\"uri\":\"" + c.a + "\"}],\"version\":\"1.0\"}", out);
      break;
    }
  }
}

static bool runExtras() {   // true if it did something that took time
  XCmd c{-1, ""};
  xSemaphoreTake(stateLock, portMAX_DELAY);
  if (!xqueue.empty()) { c = xqueue.front(); xqueue.erase(xqueue.begin()); }
  xSemaphoreGive(stateLock);
  if (c.kind >= 0) { runXCmd(c); return true; }
  pollPurifier();
  pollTVInput();
  return false;
}

// ---------------------------------------------------------------------------------------------
// API for Exhale and Redshift (each pairs with its own token)

static String devToken(const String &app) { return prefs.getString(("tok_" + app).c_str(), ""); }

static bool devAppOK(const String &app) { return app == "exhale" || app == "redshift" || app == "keystone" || app == "equinox" || app == "nightjar"; }

static void handleDevClaim() {
  String app = server.arg("app");
  if (!devAppOK(app)) { server.send(400, "application/json", "{\"error\":\"unknown app\"}"); return; }
  if (devToken(app).length()) { server.send(409, "application/json", "{\"error\":\"already paired\"}"); return; }
  char b[33];
  for (int i = 0; i < 16; i++) snprintf(b + i * 2, 3, "%02x", (unsigned)(esp_random() & 0xff));
  prefs.putString(("tok_" + app).c_str(), String(b));
  logEvent("Paired with " + app);
  server.send(200, "application/json", String("{\"token\":\"") + b + "\"}");
}

// Afterglow (the owner) can clear Exhale's or Redshift's pairing, e.g. after reinstalling one of them.
static void handleDevReset() {
  String app = server.arg("app");
  if (!token.length() || server.header("X-Afterglow-Token") != token) { server.send(401, "application/json", "{\"error\":\"unauthorized\"}"); return; }
  if (!devAppOK(app)) { server.send(400, "application/json", "{\"error\":\"unknown app\"}"); return; }
  prefs.remove(("tok_" + app).c_str());
  logEvent(app + " pairing cleared");
  server.send(200, "application/json", "{\"ok\":true}");
}

static void handleDevConfig() {
  String app = server.arg("app");
  String tok = devToken(app);
  if (!devAppOK(app) || !tok.length() || server.header("X-Device-Token") != tok) {
    server.send(401, "application/json", "{\"error\":\"unauthorized\"}");
    return;
  }
  String body = server.arg("plain");
  bool restart = false;
  if (app == "keystone") { server.send(400, "application/json", "{\"error\":\"keystone has no device config\"}"); return; }
  if (app == "equinox") {
    restart = ac::applyConfig(body);
  } else if (app == "nightjar") {
    restart = cam::applyConfig(body);
  } else if (app == "exhale") {
    PurCfg p;
    if (!parsePurifier(body, p)) { server.send(400, "application/json", "{\"error\":\"bad json\"}"); return; }
    writeFile("/exhale.json", body);
    restart = purSignature(p) != purHomeSig;
    pur = p;
    ps.lastPoll = 0;
    ps.fails = 0;
  } else {
    IRCfg c;
    if (!parseIR(body, c)) { server.send(400, "application/json", "{\"error\":\"bad json\"}"); return; }
    writeFile("/redshift.json", body);
    restart = irSignature(c) != irHomeSig;
    ir = c;
  }
  logEvent(app + (restart ? " config: restarting for Home" : " config updated"));
  server.send(200, "application/json", String("{\"ok\":true,\"restart\":") + (restart ? "true" : "false") + "}");
  if (restart) { delay(800); ESP.restart(); }
}

static void handleDevTest() {
  String app = server.arg("app");
  String tok = devToken(app);
  if (!devAppOK(app) || !tok.length() || server.header("X-Device-Token") != tok) {
    server.send(401, "application/json", "{\"error\":\"unauthorized\"}");
    return;
  }
  JsonDocument d;
  if (deserializeJson(d, server.arg("plain"))) { server.send(400, "application/json", "{\"error\":\"bad json\"}"); return; }
  String dps;
  serializeJson(d["dps"], dps);
  String err, echo;
  bool ok = app == "exhale" ? tuyaSend(pur.ip, pur.id, pur.key, pur.ver, dps, &echo, err)
                            : tuyaSend(ir.ip, ir.id, ir.key, ir.ver, dps, nullptr, err);
  server.send(200, "application/json", String("{\"ok\":") + (ok ? "true" : "false") + ",\"error\":\"" + err + "\"}");
}

// Firmware update, uploaded by Afterglow (multipart, field "fw").
static bool updateAllowed = false;
static volatile bool otaActive = false;
static String updateError;

static void handleUpdateDone() {
  if (!updateAllowed) { server.send(401, "application/json", "{\"error\":\"unauthorized\"}"); return; }
  bool ok = !Update.hasError() && updateError.isEmpty();
  server.send(ok ? 200 : 500, "application/json", ok ? "{\"ok\":true}" : "{\"ok\":false,\"error\":\"" + updateError + "\"}");
  logEvent(ok ? "Updated, restarting" : "Update failed: " + updateError + ", restarting");
  delay(800);
  ESP.restart();   // either way: a clean start (Bluetooth was stopped for the upload)
}

static void handleUpdateUpload() {
  HTTPUpload &up = server.upload();
  if (up.status == UPLOAD_FILE_START) {
    String ks = devToken("keystone");
    updateAllowed = (token.length() && server.header("X-Afterglow-Token") == token) ||
                    (ks.length() && server.header("X-Device-Token") == ks);
    updateError = "";
    if (!updateAllowed) return;
    logEvent("Firmware update started");
    otaActive = true;
    stopBluetoothForOta();   // give Wi-Fi the radio for the upload
    if (!Update.begin(UPDATE_SIZE_UNKNOWN)) updateError = Update.errorString();
  } else if (up.status == UPLOAD_FILE_WRITE) {
    if (!updateAllowed || updateError.length()) return;
    if (Update.write(up.buf, up.currentSize) != up.currentSize) updateError = Update.errorString();
  } else if (up.status == UPLOAD_FILE_END) {
    if (!updateAllowed || updateError.length()) return;
    if (!Update.end(true)) updateError = Update.errorString();
  } else if (up.status == UPLOAD_FILE_ABORTED) {
    Update.abort();
    updateError = "upload aborted";
    if (otaActive) { delay(200); ESP.restart(); }
  }
}

static void registerExtraRoutes() {
  server.on("/api/dev/claim", HTTP_POST, handleDevClaim);
  server.on("/api/dev/config", HTTP_POST, handleDevConfig);
  server.on("/api/dev/test", HTTP_POST, handleDevTest);
  server.on("/api/dev/reset", HTTP_POST, handleDevReset);
  server.on("/api/update", HTTP_POST, handleUpdateDone, handleUpdateUpload);
}

static void extrasInfo(JsonDocument &d) {
  d["build"] = FW_BUILD;
  d["chip"] = FW_CHIP;
  JsonObject p = d["purifier"].to<JsonObject>();
  p["paired"] = devToken("exhale").length() > 0;
  p["configured"] = pur.configured;
  if (pur.configured) {
    p["name"] = pur.name;
    p["ok"] = ps.ok;
    if (ps.known) { p["on"] = ps.on; p["auto"] = ps.autoMode; }
    if (ps.pm >= 0) p["pm25"] = ps.pm;
    if (ps.fanIdx >= 0) p["speed"] = ps.fanIdx + 1;
    if (pur.display.length()) p["display"] = ps.displayOn;
    p["keepDisplayOff"] = pur.keepDisplayOff;
  }
  JsonObject r = d["ir"].to<JsonObject>();
  r["paired"] = devToken("redshift").length() > 0;
  JsonArray rs = r["remotes"].to<JsonArray>();
  for (auto &x : ir.remotes) {
    JsonObject o = rs.add<JsonObject>();
    o["name"] = x.name;
    o["buttons"] = (int)x.buttons.size();
    o["power"] = x.power.length() > 0;
    JsonArray bn = o["names"].to<JsonArray>();
    for (auto &b : x.buttons) bn.add(b.name);
  }
  JsonObject t = d["tvTile"].to<JsonObject>();
  t["inHome"] = tvInHome;
  JsonArray ins = t["inputs"].to<JsonArray>();
  for (auto &i : tvInputs) ins.add(i.name);
}

// Load at boot, before the accessories are built.
static void loadExtras(const String &afterglowCfg) {
  fsUp = LittleFS.begin(true);
  if (!fsUp) Serial.println("[afterglow] LittleFS unavailable, purifier and IR settings won't persist");
  parsePurifier(readFile("/exhale.json"), pur);
  parseIR(readFile("/redshift.json"), ir);
  parseTVExtras(afterglowCfg, tvName, tvInputs);
}

// Build the accessories (call inside setup, after the lights).
static void addExtraAccessories(std::vector<uint32_t> &used) {
  if (pur.configured) {
    purInHome = true;
    purHomeSig = purSignature(pur);
    new SpanAccessory(aidFor("pur:" + pur.id, used));
      new Service::AccessoryInformation();
        new Characteristic::Identify();
        new Characteristic::Name(pur.name.c_str());
        new Characteristic::Manufacturer("Tuya");
        new Characteristic::Model("Air purifier");
        new Characteristic::SerialNumber(pur.id.c_str());
      new AGPurifier();
      if (pur.pm.length()) new AGAirQuality();
      if (pur.filter.length()) new AGFilter();
      if (pur.display.length()) new AGPurDisplay();
  }
  if (ir.configured()) {
    irInHome = true;
    irHomeSig = irSignature(ir);
    for (size_t i = 0; i < ir.remotes.size(); i++) {
      IRRemote &r = ir.remotes[i];
      new SpanAccessory(aidFor("ir:" + r.id, used));
        new Service::AccessoryInformation();
          new Characteristic::Identify();
          new Characteristic::Name(r.name.c_str());
          new Characteristic::Manufacturer("IR");
          new Characteristic::Model(r.kind.c_str());
        if (r.power.length()) new AGIRPower(i);
        for (size_t b = 0; b < r.buttons.size(); b++) new AGIRButton(i, b);
    }
  }
  tvHomeSig = tvSignature(tvAddr(), tvName, tvInputs);
  if (tvHomeSig.length()) {
    tvInHome = true;
    addTVAccessory();
  }
}
