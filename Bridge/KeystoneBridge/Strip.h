// Tuya / Smart Life Wi-Fi power strip (e.g. Jolyjoy 3-outlet + USB), set up from Keystone.
// Each outlet (and the USB group) becomes its own Outlet tile in Apple Home, talks Tuya LAN (no cloud),
// and can be switched from Keystone at home or away (through /api/control, so the relay carries it).
//
// POST /api/strip  (Keystone token, home network only, like the relay settings)
//   {"action":"config", "name":..., "id":..., "key":... (blank = keep), "ip":... (blank = find it), "ver":3.3,
//    "outlets":[{"name":"Lamp","dp":"1"}, ...]}          -> saved, restarts if Home needs new tiles
//   {"action":"find"}                                      -> scan the Wi-Fi for the strip again (progress in /api/info)
//   {"action":"probe", "id":..., "key":..., "ip":..., "ver":3.3}  -> {"ok":true,"dps":{...}} raw status
//   {"action":"remove"}                                    -> forgets the strip, restarts
// POST /api/control {"device":"strip", "outlet":0, "on":true} | {"device":"strip", "all":false}
#pragma once

namespace strip {

#define STRIP_MAX 6
#define STRIP_POLL_MS 10000UL

struct Plug { String name, dp; };
struct Cfg {
  bool configured = false;
  String name = "Power Strip", id, key, ip;
  float ver = 3.3;
  std::vector<Plug> outlets;
};
static Cfg cfg;
static bool inHome = false;
static String homeSig;

struct State {
  bool known = false, ok = false;
  bool on[STRIP_MAX] = {false};
  uint32_t lastPoll = 0, lastSent = 0;
  int fails = 0;
  uint32_t lowMem = 0;
  String error;
};
static State st;

// Finding the strip on the Wi-Fi: one host per worker pass so the TV rule, lights and Home keep running.
struct Scan {
  bool on = false;
  int next = 1, done = 0, total = 0, found = 0;
  uint32_t base = 0, startedAt = 0, finishedAt = 0;
  uint32_t me = 0;
  String last;   // "found 192.168.1.50", "not found", ...
};
static Scan scan;
static SemaphoreHandle_t lock = nullptr;
static std::vector<String> pending;   // dps JSON waiting to be sent

static String signature(const Cfg &c) {
  if (!c.configured) return "";
  String s = c.id + "|" + c.name;
  for (auto &o : c.outlets) s += "|" + o.dp + "=" + o.name;
  return s;
}

static bool parseCfg(const String &json, Cfg &out) {
  JsonDocument d;
  if (!json.length() || deserializeJson(d, json)) return false;
  Cfg c;
  c.name = d["name"] | "Power Strip";
  if (!c.name.length()) c.name = "Power Strip";
  c.id = d["id"] | ""; c.key = d["key"] | ""; c.ip = d["ip"] | ""; c.ver = d["ver"] | 3.3f;
  for (JsonObject o : d["outlets"].as<JsonArray>()) {
    Plug x;
    x.dp = o["dp"].is<int>() ? String(o["dp"].as<int>()) : String(o["dp"] | "");
    x.name = o["name"] | "";
    if (!x.name.length()) x.name = c.name + " " + String(c.outlets.size() + 1);
    if (x.dp.length() && c.outlets.size() < STRIP_MAX) c.outlets.push_back(x);
  }
  c.configured = c.id.length() && c.key.length() == 16 && !c.outlets.empty();   // no IP yet = the bridge scans for it
  out = c;
  return true;
}

static String cfgJson(const Cfg &c) {
  JsonDocument d;
  d["name"] = c.name; d["id"] = c.id; d["key"] = c.key; d["ip"] = c.ip; d["ver"] = c.ver;
  JsonArray a = d["outlets"].to<JsonArray>();
  for (auto &o : c.outlets) { JsonObject x = a.add<JsonObject>(); x["name"] = o.name; x["dp"] = o.dp; }
  String s;
  serializeJson(d, s);
  return s;
}

static void save() { writeFile("/strip.json", cfgJson(cfg)); }

static void applyDps(const String &dps) {
  if (!dps.length() || dps == "{}") return;
  JsonDocument d;
  if (deserializeJson(d, dps)) return;
  xSemaphoreTake(lock, portMAX_DELAY);
  for (size_t i = 0; i < cfg.outlets.size(); i++) {
    JsonVariant v = d[cfg.outlets[i].dp];
    if (v.is<bool>()) st.on[i] = v.as<bool>();
  }
  st.known = true;
  xSemaphoreGive(lock);
}

// Queues a switch. A newer command replaces an unsent one so taps don't pile up.
static void setOutlets(const std::vector<int> &idx, bool on) {
  JsonDocument d;
  xSemaphoreTake(lock, portMAX_DELAY);
  for (int i : idx) {
    if (i < 0 || i >= (int)cfg.outlets.size()) continue;
    d[cfg.outlets[i].dp] = on;
    st.on[i] = on;
  }
  st.lastSent = millis();
  String s;
  serializeJson(d, s);
  if (s.length() > 2) {
    if (pending.size() >= 8) pending.erase(pending.begin());
    pending.push_back(s);
  }
  xSemaphoreGive(lock);
}

struct Tile : Service::Outlet {
  int idx;
  SpanCharacteristic *on;
  Tile(int i) : Service::Outlet(), idx(i) {
    on = new Characteristic::On(0);
    new Characteristic::OutletInUse(1);
    new Characteristic::ConfiguredName(cfg.outlets[i].name.c_str());
  }
  boolean update() override {
    setOutlets({idx}, on->getNewVal());
    return true;
  }
  void loop() override {
    if (!st.known || millis() - st.lastSent < 6000) return;
    bool v = st.on[idx];
    if (on->getVal() != (int)v) on->setVal(v);
  }
};


static void startScan(const char *why) {
  if (scan.on || !cfg.configured || WiFi.status() != WL_CONNECTED || ESP.getMaxAllocHeap() < 40000) return;
  IPAddress ip = WiFi.localIP();
  scan = Scan();
  scan.on = true;
  scan.me = ip[3];
  scan.base = ((uint32_t)ip[0] << 16) | ((uint32_t)ip[1] << 8) | ip[2];
  scan.total = 254;
  scan.startedAt = millis();
  scan.last = "scanning";
  logEvent(String("Power strip: looking for it on Wi-Fi (") + why + ")");
}

// IPs of other things the bridge already talks to: no point knocking on them.
static bool knownElsewhere(const String &ip) {
  if (pur.ip == ip || ir.ip == ip) return true;
  for (auto &L : lights) if (L.ip == ip) return true;
  return false;
}

static void scanStep() {
  if (!scan.on) return;
  if (scan.next > 254) {
    scan.on = false;
    scan.finishedAt = millis();
    if (!scan.found) { scan.last = "not found"; logEvent("Power strip: not found on Wi-Fi (check its Wi-Fi, key and that it is online)"); }
    return;
  }
  int n = scan.next++;
  scan.done = n;
  if ((uint32_t)n == scan.me) return;
  String host = String((scan.base >> 16) & 255) + "." + String((scan.base >> 8) & 255) + "." + String(scan.base & 255) + "." + String(n);
  if (knownElsewhere(host)) return;
  {
    WiFiClient probe;
    if (!probe.connect(host.c_str(), 6668, 250)) return;   // nothing listening: next host
    probe.stop();
  }
  std::vector<String> known;
  for (auto &o : cfg.outlets) known.push_back(o.dp);
  for (float v : {3.3f, 3.4f, 3.5f}) {
    tuya::Conn conn;
    String dps;
    if (conn.open(host, cfg.id, cfg.key, v, 1500)) { dps = conn.query(known); conn.close(); }
    if (!dps.length() || dps == "{}") continue;
    JsonDocument d;
    if (deserializeJson(d, dps)) continue;
    bool mine = false;
    for (auto &o : cfg.outlets) if (d[o.dp].is<bool>()) mine = true;   // right key AND it has our outlets
    if (!mine) continue;
    xSemaphoreTake(lock, portMAX_DELAY);
    cfg.ip = host;
    cfg.ver = v;
    xSemaphoreGive(lock);
    save();
    applyDps(dps);
    st.ok = true; st.fails = 0; st.error = "";
    scan.on = false;
    scan.found = 1;
    scan.finishedAt = millis();
    scan.last = "found " + host;
    logEvent("Power strip found at " + host + " (protocol " + String(v, 1) + ")");
    return;
  }
}

static bool send(const String &dps, String &err) {
  String echo;
  if (!tuyaSend(cfg.ip, cfg.id, cfg.key, cfg.ver, dps, &echo, err)) return false;
  applyDps(echo);
  return true;
}

static void poll() {
  if (!cfg.ip.length()) return;
  std::vector<String> known;
  for (auto &o : cfg.outlets) known.push_back(o.dp);
  tuya::Conn conn;
  String dps;
  if (conn.open(cfg.ip, cfg.id, cfg.key, cfg.ver)) { dps = conn.query(known); conn.close(); }
  if (!dps.length()) {
    if (++st.fails >= 3) { st.ok = false; st.error = conn.lastError; }
    return;
  }
  st.fails = 0;
  st.ok = true;
  st.error = "";
  applyDps(dps);
}

// Called from the worker task. True if it did network work.
static bool step() {
  if (!cfg.configured) return false;
  // A Tuya session needs ~10 KB at once. When the bridge is short, wait instead of tipping it over.
  if (ESP.getMaxAllocHeap() < 24000 || govee::radioOn || acNetBusy) { st.lowMem++; return false; }
  if (scan.on) scanStep();
  if (!cfg.ip.length()) {
    // No address yet (or it was cleared): look for it now and every few minutes after.
    if (!scan.on && (!scan.finishedAt || millis() - scan.finishedAt > 300000UL)) startScan("no address yet");
    xSemaphoreTake(lock, portMAX_DELAY);
    pending.clear();
    xSemaphoreGive(lock);
    return false;
  }
  // It stopped answering for a while: the router may have given it a new address.
  if (st.fails >= 3 && !scan.on && (!scan.finishedAt || millis() - scan.finishedAt > 600000UL)) startScan("stopped answering");
  String next;
  xSemaphoreTake(lock, portMAX_DELAY);
  if (!pending.empty()) { next = pending.front(); pending.erase(pending.begin()); }
  xSemaphoreGive(lock);
  if (next.length()) {
    String err;
    if (send(next, err)) { st.ok = true; st.fails = 0; st.error = ""; }
    else { st.error = err; logEvent("Power strip: " + err); }
    st.lastSent = millis();
    return true;
  }
  if (st.lastPoll && millis() - st.lastPoll < (st.fails >= 3 ? 60000UL : STRIP_POLL_MS)) return false;
  if (millis() - st.lastSent < 4000) return false;
  st.lastPoll = millis();
  poll();
  return true;
}

// ---------------------------------------------------------------------------------------------

static void load() {
  lock = xSemaphoreCreateMutex();
  parseCfg(readFile("/strip.json"), cfg);
}

static void addAccessory(std::vector<uint32_t> &used) {
  if (!cfg.configured) return;
  inHome = true;
  homeSig = signature(cfg);
  // One accessory with an Outlet service per outlet: Home still shows each outlet as its own tile, but the
  // bridge holds one set of accessory info instead of one per outlet (5 separate accessories ran it out of RAM).
  new SpanAccessory(aidFor("strip:" + cfg.id, used));
    new Service::AccessoryInformation();
      new Characteristic::Identify();
      new Characteristic::Name(cfg.name.c_str());
  for (size_t i = 0; i < cfg.outlets.size(); i++) new Tile(i);
}

static void reply(int code, const String &body) { server.send(code, "application/json", body); }

static void handleApi() {
  if (!screen::adminOK()) return reply(401, "{\"error\":\"unauthorized\"}");
  JsonDocument d;
  if (deserializeJson(d, server.arg("plain"))) return reply(400, "{\"error\":\"bad json\"}");
  String action = d["action"] | "";
  if (action == "probe") {
    String id = d["id"] | cfg.id, key = d["key"] | "", ip = d["ip"] | cfg.ip;
    if (!key.length()) key = cfg.key;
    float ver = d["ver"] | cfg.ver;
    if (!ip.length()) return reply(400, "{\"error\":\"no IP yet: let the bridge find the strip first\"}");
    if (key.length() != 16) return reply(400, "{\"error\":\"the local key must be 16 characters\"}");
    tuya::Conn conn;
    String dps;
    if (conn.open(ip, id, key, ver, 2500)) { dps = conn.query({"1", "2", "3", "4", "5", "6", "7"}); conn.close(); }
    if (!dps.length()) return reply(200, "{\"ok\":false,\"error\":\"" + (conn.lastError.length() ? conn.lastError : String("no status")) + "\"}");
    return reply(200, "{\"ok\":true,\"dps\":" + dps + "}");
  }
  if (action == "find") {
    if (!cfg.configured) return reply(400, "{\"error\":\"set the strip up first\"}");
    scan.finishedAt = 0;
    startScan("asked from Keystone");
    return reply(200, "{\"ok\":true}");
  }
  if (action == "remove") {
    if (fsUp) LittleFS.remove("/strip.json");
    bool restart = inHome;
    cfg = Cfg();
    scan = Scan();
    logEvent("Power strip removed");
    reply(200, String("{\"ok\":true,\"restart\":") + (restart ? "true" : "false") + "}");
    if (restart) { delay(800); ESP.restart(); }
    return;
  }
  if (action != "config") return reply(400, "{\"error\":\"unknown action\"}");
  String body;
  serializeJson(d, body);
  Cfg c;
  parseCfg(body, c);
  if (!c.key.length() && c.id == cfg.id) c.key = cfg.key;   // blank key = keep the saved one
  if (!c.ip.length() && c.id == cfg.id) c.ip = cfg.ip;      // blank IP = keep the saved one (use "find" to look again)
  c.configured = c.id.length() && c.key.length() == 16 && !c.outlets.empty();
  if (!c.configured) return reply(400, "{\"error\":\"needs the device ID, the 16-character local key and at least one outlet\"}");
  writeFile("/strip.json", cfgJson(c));
  bool restart = signature(c) != homeSig;
  xSemaphoreTake(lock, portMAX_DELAY);
  cfg = c;
  pending.clear();
  st = State();
  scan = Scan();
  xSemaphoreGive(lock);
  logEvent(restart ? "Power strip set up: restarting for Home" : "Power strip updated");
  reply(200, String("{\"ok\":true,\"restart\":") + (restart ? "true" : "false") + "}");
  if (restart) { delay(800); ESP.restart(); }
}

static void registerRoutes() { server.on("/api/strip", HTTP_POST, handleApi); }

// From /api/control (LAN or relay).
static void control(JsonDocument &d, void (*done)(int, const String &)) {
  if (!cfg.configured) return done(400, "no power strip");
  if (d["on"].isNull() && d["all"].isNull()) return done(400, "nothing to do");
  std::vector<int> idx;
  bool on;
  if (!d["all"].isNull()) {
    on = d["all"];
    for (size_t i = 0; i < cfg.outlets.size(); i++) idx.push_back(i);
  } else {
    int i = d["outlet"] | -1;
    if (i < 0 || i >= (int)cfg.outlets.size()) return done(400, "no such outlet");
    on = d["on"];
    idx.push_back(i);
  }
  setOutlets(idx, on);
  done(200, "");
}

static void info(JsonDocument &d) {
  JsonObject s = d["strip"].to<JsonObject>();
  s["configured"] = cfg.configured;
  if (!cfg.configured) return;
  s["name"] = cfg.name;
  s["id"] = cfg.id;
  s["ip"] = cfg.ip;
  s["ver"] = cfg.ver;
  s["scanning"] = scan.on;
  if (scan.on) { s["scanDone"] = scan.done; s["scanTotal"] = scan.total; }
  if (scan.last.length()) s["scan"] = scan.last;
  s["ok"] = st.ok;
  s["known"] = st.known;
  if (st.error.length()) s["error"] = st.error;
  if (st.lowMem) s["lowMem"] = st.lowMem;
  JsonArray a = s["outlets"].to<JsonArray>();
  for (size_t i = 0; i < cfg.outlets.size(); i++) {
    JsonObject o = a.add<JsonObject>();
    o["name"] = cfg.outlets[i].name;
    o["dp"] = cfg.outlets[i].dp;
    if (st.known) o["on"] = st.on[i];
  }
}

}  // namespace strip
