// Vicohome camera, sent from Nightjar. The bridge polls Vicohome's cloud for the camera's events and puts
// it in Apple Home as a motion sensor, a person (occupancy) sensor and a battery. With no home hub, Home
// automations can't run, so the bridge runs the one that matters itself: a person turns chosen lights on,
// and they go off again after a quiet spell.
//
// Same API as Nightjar (soum91/nightjar): POST {base}/library/newselectlibrary for events and
// /device/listuserdevices for battery/online, token in Authorization. It starts with the token Nightjar
// sends and only signs in itself when that stops working, so the two don't keep knocking each other off.
#pragma once

#define CAM_POLL_MS 20000UL
#define CAM_SLOW_MS 60000UL
#define CAM_DEVICE_MS 300000UL
#define CAM_MOTION_MS 30000UL
#define CAM_PERSON_MS 120000UL

namespace cam {

struct Cfg {
  bool configured = false;
  String email, pass, token, base = "https://api-us.vicohome.io", country = "US", serial, name = "Camera";
  bool ruleOn = false, window = false;
  int from = 0, to = 0, offAfter = 10;   // minutes; offAfter 0 leaves the lights on
  std::vector<String> lights;
  // Alerts: ntfy push (the ntfy iOS app shows the snapshot), optionally checked by Claude first
  bool alertOn = false, alertAll = false, aiOnly = false;
  String topic, server = "https://ntfy.sh", aiKey, aiModel = "claude-haiku-5-5";
  int cooldown = 60;   // seconds between unflagged alerts
};
static Cfg cfg;
static String homeSig, token;

static String signature(const Cfg &c) { return c.configured ? c.serial + "|" + c.name : ""; }

static bool parseCfg(const String &json, Cfg &out) {
  JsonDocument d;
  if (deserializeJson(d, json)) return false;
  Cfg c;
  JsonObject o = d["camera"];
  if (!o.isNull()) {
    c.email = o["email"] | ""; c.pass = o["pass"] | ""; c.token = o["token"] | "";
    c.base = o["base"] | "https://api-us.vicohome.io"; c.country = o["country"] | "US";
    c.serial = o["serial"] | ""; c.name = o["name"] | "Camera";
    if (!c.name.length()) c.name = "Camera";
    JsonObject r = o["person"];
    c.ruleOn = r["enabled"] | false; c.window = r["window"] | false;
    c.from = r["from"] | 0; c.to = r["to"] | 0; c.offAfter = r["offAfter"] | 10;
    for (JsonVariant v : r["lights"].as<JsonArray>()) c.lights.push_back(v.as<String>());
    JsonObject a = o["alerts"];
    c.topic = a["topic"] | ""; c.server = a["server"] | "https://ntfy.sh";
    c.alertOn = (a["enabled"] | false) && c.topic.length();
    c.alertAll = a["all"] | false; c.cooldown = a["cooldown"] | 60;
    c.aiKey = a["aiKey"] | ""; c.aiModel = a["aiModel"] | "claude-haiku-5-5"; c.aiOnly = (a["aiOnly"] | false) && c.aiKey.length();
    c.configured = c.serial.length() && (c.token.length() || (c.email.length() && c.pass.length()));
  }
  out = c;
  return true;
}

// ---------------------------------------------------------------------------------------------
// State (written by the worker, read by the Home tiles)

struct State {
  bool ok = false, known = false, online = false, charging = false, seeded = false;
  int battery = -1;
  uint32_t motionAt = 0, personAt = 0, eventMs = 0;
  long newestTs = 0;
  String error, lastType;
};
static State st;
static std::vector<String> seen;   // recent traceIds, events get re-reported as their clips finish
static uint32_t lastEvents = 0, lastDevice = 0, ruleOffDue = 0;
static std::vector<int> ruleLit;

// ---------------------------------------------------------------------------------------------
// Vicohome

// HTTPS POST, parsed straight off the socket through `filter` (HTTP/1.0, so no chunked framing) to
// keep the raw reply out of RAM. If memory is short it borrows the AC's handshake: the remote relay
// lets go of its buffer for the duration, and reconnects right after.
static int post(const String &url, const String &body, JsonDocument &filter, JsonDocument &d,
                const char *h1 = nullptr, const String &v1 = "", const char *h2 = nullptr, const char *v2 = nullptr) {
  workerBeat = millis();
  bool borrowed = false;
  if (ESP.getMaxAllocHeap() < 34000 && relayHolding) {   // only when it really can't fit otherwise
    borrowed = acNetBusy = true;
    if (relayLetGo) relayLetGo();
  }
  int code = -1;
  if (ESP.getMaxAllocHeap() < 30000) {
    st.error = "low memory, block " + String(ESP.getMaxAllocHeap() / 1024) + "K";
  } else {
    WiFiClientSecure c;
    c.setInsecure();
    c.setHandshakeTimeout(20);
    HTTPClient h;
    h.useHTTP10(true);
    h.setConnectTimeout(8000);
    h.setTimeout(15000);
    if (h.begin(c, url)) {
      h.addHeader("Content-Type", "application/json");
      if (h1 && v1.length()) h.addHeader(h1, v1);
      if (h2 && v2) h.addHeader(h2, v2);
      code = h.POST(body);
      d.clear();
      if (code > 0 && deserializeJson(d, h.getStream(), DeserializationOption::Filter(filter))) d.clear();
      h.end();
    }
  }
  if (borrowed) acNetBusy = false;
  workerBeat = millis();
  return code;
}

static bool login() {
  if (!cfg.email.length() || !cfg.pass.length()) { st.error = "token expired, open Nightjar to send a new one"; return false; }
  JsonDocument b, f, d;
  b["email"] = cfg.email; b["password"] = cfg.pass; b["loginType"] = 0;
  String body;
  serializeJson(b, body);
  token = "";
  f["msg"] = true;
  f["data"]["token"]["token"] = true;
  if (post(cfg.base + "/account/login", body, f, d) <= 0) { if (!st.error.startsWith("low")) st.error = "sign in: no reply"; return false; }
  token = d["data"]["token"]["token"] | "";
  if (!token.length()) { st.error = String("sign in failed: ") + (d["msg"] | "?"); return false; }
  prefs.putString("cam_tok", token);
  logEvent("Camera: signed in to Vicohome");
  return true;
}

// One call with a single re-login on a session error.
static bool call(const char *path, JsonDocument &body, JsonDocument &filter, JsonDocument &d) {
  body["language"] = "en";
  body["countryNo"] = cfg.country;
  filter["result"] = true; filter["code"] = true; filter["msg"] = true;
  String b;
  serializeJson(body, b);
  for (int attempt = 0; attempt < 2; attempt++) {
    if (!token.length() && !login()) return false;
    int code = post(cfg.base + path, b, filter, d, "Authorization", token);
    if (code <= 0) { if (!st.error.startsWith("low")) st.error = "no reply (" + String(code) + ")"; return false; }
    if (code == 401 || code == 403) { token = ""; continue; }
    if (d.isNull()) { st.error = "HTTP " + String(code); return false; }
    int r = d["result"] | (d["code"] | 0);
    if (r == 0) { st.error = ""; return true; }
    String msg = d["msg"] | "";
    if ((r <= -1024 && r >= -1027) || msg.indexOf("token") >= 0) { token = ""; continue; }
    st.error = msg.length() ? msg : "error " + String(r);
    return false;
  }
  return false;
}

static bool isPerson(JsonObject e) {
  auto is = [](JsonVariant v) { const char *s = v.as<const char *>(); return s && strcasecmp(s, "person") == 0; };
  for (JsonObject i : e["subcategoryInfoList"].as<JsonArray>()) if (is(i["objectType"]) || is(i["objectName"])) return true;
  for (JsonObject k : e["keyshots"].as<JsonArray>()) if (is(k["objectCategory"])) return true;
  return false;
}

static void runRule() {
  if (!cfg.ruleOn || !inWindow(cfg.window, cfg.from, cfg.to)) return;
  int n = 0;
  for (auto &id : cfg.lights) {
    int i = findLight(id);
    if (i < 0 || !lights[i].sw.length() || lights[i].on) continue;
    enqueue(Cmd{i, "{\"" + lights[i].sw + "\":true}", false, false, true});
    if (std::find(ruleLit.begin(), ruleLit.end(), i) == ruleLit.end()) ruleLit.push_back(i);
    n++;
  }
  if (!ruleLit.empty() && cfg.offAfter > 0) ruleOffDue = millis() + cfg.offAfter * 60000UL;
  if (n) logEvent("Camera saw a person: " + String(n) + " light" + (n == 1 ? "" : "s") + " on");
}

static void runRuleTimer() {
  if (!ruleOffDue || (int32_t)(millis() - ruleOffDue) < 0) return;
  ruleOffDue = 0;
  int n = 0;
  for (int i : ruleLit) {
    if (i >= (int)lights.size() || !lights[i].on) continue;
    enqueue(Cmd{i, "{\"" + lights[i].sw + "\":false}", false, true, false});
    n++;
  }
  ruleLit.clear();
  if (n) logEvent("Nobody on camera for " + String(cfg.offAfter) + " min: " + String(n) + " off");
}

// ---------------------------------------------------------------------------------------------
// Alerts

struct Alert { String trace, img; uint32_t at; bool person; };
static std::vector<Alert> alerts;
static uint32_t lastAlertMs = 0;
static int alertsSent = 0;
static String alertErr, lastAi;

// Claude looks at the snapshot (by URL, so the image never touches the bridge's RAM).
static String askAI(const String &img) {
  JsonDocument b, f, d;
  b["model"] = cfg.aiModel;
  b["max_tokens"] = 80;
  JsonArray content = b["messages"][0]["content"].to<JsonArray>();
  b["messages"][0]["role"] = "user";
  JsonObject im = content.add<JsonObject>();
  im["type"] = "image";
  im["source"]["type"] = "url";
  im["source"]["url"] = img;
  JsonObject t = content.add<JsonObject>();
  t["type"] = "text";
  t["text"] = "Frame from a home security camera. Reply with exactly one line: FLAGS: <close,tamper,food or none> | "
              "<at most 15 words on who is there and what they are doing>. close = a person is very near the lens, "
              "face or body filling much of the frame. tamper = touching, covering, turning or blocking the camera. "
              "food = handling or taking food, or opening the fridge or cupboards.";
  String body;
  serializeJson(b, body);
  f["content"][0]["text"] = true;
  f["error"]["message"] = true;
  int code = post("https://api.anthropic.com/v1/messages", body, f, d, "x-api-key", cfg.aiKey, "anthropic-version", "2023-06-01");
  String out = d["content"][0]["text"] | "";
  if (code != 200 || !out.length()) { alertErr = "AI: " + String(d["error"]["message"] | ("HTTP " + String(code)).c_str()); return ""; }
  out.trim();
  return out;
}

// ntfy JSON publish: title, text, the snapshot as an attachment (previewed in the iOS banner), and a
// tap action that opens Nightjar on the event.
static bool ntfy(const String &title, const String &text, const String &img, const String &trace, bool urgent) {
  JsonDocument b, f, d;
  b["topic"] = cfg.topic;
  b["title"] = title;
  b["message"] = text.length() ? text : cfg.name;
  if (img.length()) b["attach"] = img;
  b["click"] = "nightjar://event/" + trace;
  b["priority"] = urgent ? 5 : 4;
  b["tags"][0] = urgent ? "rotating_light" : "bust_in_silhouette";
  String body;
  serializeJson(b, body);
  f["id"] = true;
  f["error"] = true;
  int code = post(cfg.server, body, f, d);
  if (code == 200 && d["id"].is<const char *>()) return true;
  alertErr = "ntfy: " + String(d["error"] | ("HTTP " + String(code)).c_str());
  return false;
}

// One alert per pass. Waits up to 45 s for the event's snapshot to show up in Vicohome's list.
static void runAlerts() {
  if (alerts.empty()) return;
  Alert a = alerts.front();
  if (!a.img.length() && millis() - a.at < 45000UL) return;
  alerts.erase(alerts.begin());
  String flags, what;
  bool checked = false;
  if (cfg.aiKey.length() && a.img.length()) {
    String r = askAI(a.img);
    checked = r.length() > 0;
    lastAi = r;
    int bar = r.indexOf('|');
    flags = r.substring(0, bar < 0 ? r.length() : bar);
    flags.toLowerCase();
    if (bar >= 0) { what = r.substring(bar + 1); what.trim(); }
  }
  bool tamper = flags.indexOf("tamper") >= 0, close = flags.indexOf("close") >= 0, food = flags.indexOf("food") >= 0;
  bool flagged = tamper || close || food;
  if (cfg.aiOnly && checked && !flagged) return;   // unchecked (no snapshot, AI down) still alerts
  if (!flagged && lastAlertMs && millis() - lastAlertMs < (uint32_t)cfg.cooldown * 1000UL) return;
  String head = tamper ? "Someone's messing with the camera" : close ? "Person right at the camera"
              : food ? "Person at the food" : a.person ? "Person" : "Motion";
  String title = head + " \u00b7 " + cfg.name + " \u00b7 " + clockText();
  if (ntfy(title, what, a.img, a.trace, flagged)) {
    lastAlertMs = millis();
    alertsSent++;
    alertErr = "";
  }
}

static void pollEvents() {
  long now = time(nullptr);
  long from = st.newestTs ? st.newestTs - 30 : now - 180;
  JsonDocument b, f, d;
  b["startTimestamp"] = String(from);
  b["endTimestamp"] = String(now + 60);
  JsonObject e = f["data"]["list"][0].to<JsonObject>();
  e["traceId"] = true; e["timestamp"] = true; e["serialNumber"] = true;
  e["subcategoryInfoList"][0]["objectType"] = true;
  e["subcategoryInfoList"][0]["objectName"] = true;
  e["keyshots"][0]["objectCategory"] = true;
  e["keyshots"][0]["imageUrl"] = true;
  e["imageUrl"] = true;
  if (!call("/library/newselectlibrary", b, f, d)) { st.ok = false; return; }
  st.ok = true;
  bool motion = false, person = false;
  for (JsonObject x : d["data"]["list"].as<JsonArray>()) {
    String sn = x["serialNumber"] | "";
    if (sn.length() && sn != cfg.serial) continue;
    String trace = x["traceId"] | "";
    JsonVariant tv = x["timestamp"];
    long ts = tv.is<const char *>() ? atol(tv.as<const char *>()) : tv.as<long>();
    if (ts > 1e12) ts /= 1000;
    if (ts > st.newestTs) st.newestTs = ts;
    String img = x["imageUrl"] | "";
    if (!img.length()) img = x["keyshots"][0]["imageUrl"] | "";
    for (auto &al : alerts) if (al.trace == trace && !al.img.length()) al.img = img;   // snapshot arrived later
    if (!trace.length() || std::find(seen.begin(), seen.end(), trace) != seen.end()) continue;
    seen.push_back(trace);
    if (seen.size() > 12) seen.erase(seen.begin());
    if (!st.seeded) continue;   // first pass after boot: remember, don't fire
    motion = true;
    bool p = isPerson(x);
    if (p) person = true;
    if (cfg.alertOn && (p || cfg.alertAll) && alerts.size() < 4) alerts.push_back(Alert{trace, img, millis(), p});
  }
  if (!st.newestTs) st.newestTs = now - 60;
  st.seeded = true;
  if (!motion) return;
  st.motionAt = st.eventMs = millis();
  st.lastType = person ? "person" : "motion";
  if (person) { st.personAt = millis(); runRule(); }
}

static void pollDevice() {
  JsonDocument b, f, d;
  JsonObject e = f["data"]["list"][0].to<JsonObject>();
  e["serialNumber"] = true; e["batteryLevel"] = true; e["isCharging"] = true; e["ip"] = true; e["online"] = true;
  if (!call("/device/listuserdevices", b, f, d)) return;
  for (JsonObject x : d["data"]["list"].as<JsonArray>()) {
    String sn = x["serialNumber"] | "";
    if (sn != cfg.serial) continue;
    int bat = x["batteryLevel"] | -1;
    st.battery = bat >= 0 && bat <= 100 ? bat : -1;
    st.charging = (x["isCharging"] | 0) > 0;
    const char *ip = x["ip"] | "";
    st.online = x["online"].isNull() ? (ip[0] && strcmp(ip, "0.0.0.0") != 0) : x["online"].as<bool>();
    st.known = true;
  }
}

// From the worker, like ac::step(). Never while Bluetooth has the memory.
static void step() {
  runRuleTimer();
  if (!camEnabled || !cfg.configured || millis() < 30000UL || otaActive || safeMode || setupOnly || govee::radioOn ||
      WiFi.status() != WL_CONNECTED || time(nullptr) < 1700000000) return;
  if (!lastDevice || millis() - lastDevice > CAM_DEVICE_MS) { lastDevice = millis(); pollDevice(); return; }
  if (millis() - lastEvents > (st.ok ? CAM_POLL_MS : CAM_SLOW_MS)) { lastEvents = millis(); pollEvents(); return; }
  runAlerts();
}

// ---------------------------------------------------------------------------------------------
// Apple Home

static bool live() { return st.ok && (!st.known || st.online); }

struct Motion : Service::MotionSensor {
  SpanCharacteristic *m, *active;
  Motion() : Service::MotionSensor() {
    new Characteristic::Name("Motion");
    m = new Characteristic::MotionDetected(0);
    active = new Characteristic::StatusActive(0);
  }
  void loop() override {
    int on = st.motionAt && millis() - st.motionAt < CAM_MOTION_MS;
    if (m->getVal() != on) m->setVal(on);
    if (active->getVal() != (int)live()) active->setVal(live());
  }
};

struct Person : Service::OccupancySensor {
  SpanCharacteristic *o, *active;
  Person() : Service::OccupancySensor() {
    new Characteristic::Name("Person");
    o = new Characteristic::OccupancyDetected(0);
    active = new Characteristic::StatusActive(0);
  }
  void loop() override {
    int on = st.personAt && millis() - st.personAt < CAM_PERSON_MS;
    if (o->getVal() != on) o->setVal(on);
    if (active->getVal() != (int)live()) active->setVal(live());
  }
};

struct Battery : Service::BatteryService {
  SpanCharacteristic *level, *chg, *low;
  Battery() : Service::BatteryService() {
    level = new Characteristic::BatteryLevel(100);
    chg = new Characteristic::ChargingState(0);
    low = new Characteristic::StatusLowBattery(0);
  }
  void loop() override {
    if (!st.known || level->timeVal() < 30000) return;
    int b = st.battery < 0 ? 100 : st.battery;
    if (level->getVal() != b) level->setVal(b);
    int c = st.charging ? 1 : st.battery < 0 ? 2 : 0;   // 2 = not chargeable (mains powered)
    if (chg->getVal() != c) chg->setVal(c);
    int l = st.battery >= 0 && st.battery <= 15 && !st.charging;
    if (low->getVal() != l) low->setVal(l);
  }
};

static void load() {
  parseCfg(readFile("/nightjar.json"), cfg);
  token = prefs.getString("cam_tok", "");
  if (!token.length()) token = cfg.token;
}

static void addAccessory(std::vector<uint32_t> &used) {
  if (!cfg.configured) return;
  homeSig = signature(cfg);
  new SpanAccessory(aidFor("cam:" + cfg.serial, used));
    new Service::AccessoryInformation();
      new Characteristic::Identify();
      new Characteristic::Name(cfg.name.c_str());
      new Characteristic::Manufacturer("Vicohome");
      new Characteristic::Model("Camera");
      new Characteristic::SerialNumber(cfg.serial.c_str());
    new Motion();
    new Person();
    new Battery();
}

// From handleDevConfig for app=nightjar. Returns true if Home needs a restart.
static bool applyConfig(const String &body) {
  Cfg c;
  if (!parseCfg(body, c)) return false;
  writeFile("/nightjar.json", body);
  bool restart = signature(c) != homeSig;
  if (c.token.length() && c.token != cfg.token) { token = c.token; prefs.putString("cam_tok", token); }
  if (c.serial != cfg.serial || c.base != cfg.base) { st = State(); seen.clear(); }
  if (!c.configured) { token = ""; prefs.remove("cam_tok"); }
  cfg = c;
  lastEvents = 0;
  lastDevice = 0;
  return restart;
}

static void info(JsonDocument &d) {
  JsonObject c = d["camera"].to<JsonObject>();
  c["paired"] = devToken("nightjar").length() > 0;
  c["configured"] = cfg.configured;
  if (!cfg.configured) return;
  c["name"] = cfg.name;
  c["ok"] = st.ok;
  if (st.error.length()) c["error"] = st.error;
  if (st.known) {
    c["online"] = st.online;
    c["charging"] = st.charging;
    if (st.battery >= 0) c["battery"] = st.battery;
  }
  c["motion"] = st.motionAt && millis() - st.motionAt < CAM_MOTION_MS;
  c["person"] = st.personAt && millis() - st.personAt < CAM_PERSON_MS;
  if (st.eventMs) { c["lastEventAgo"] = (int)((millis() - st.eventMs) / 1000); c["lastType"] = st.lastType; }
  JsonObject r = c["rule"].to<JsonObject>();
  r["enabled"] = cfg.ruleOn;
  r["window"] = cfg.window; r["from"] = cfg.from; r["to"] = cfg.to;
  r["offAfter"] = cfg.offAfter;
  JsonArray ls = r["lights"].to<JsonArray>();
  for (auto &id : cfg.lights) ls.add(id);
  if (ruleOffDue) r["offIn"] = (int)((int32_t)(ruleOffDue - millis()) / 1000);
  JsonObject a = c["alerts"].to<JsonObject>();
  a["enabled"] = cfg.alertOn;
  a["ai"] = cfg.aiKey.length() > 0;
  a["sent"] = alertsSent;
  if (alertErr.length()) a["error"] = alertErr;
  if (lastAi.length()) a["lastAi"] = lastAi;
}

}  // namespace cam
