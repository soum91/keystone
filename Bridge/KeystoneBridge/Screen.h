// What the OLED shows, its settings, and the Keystone app's controls for the bridge itself.
// Two-tone panel: the top 16 px are yellow (status bar), the rest blue (one big reading at a time).
#pragma once

namespace screen {

// ---------------------------------------------------------------------------------------------
// Settings (from Keystone, kept in NVS)

enum Page { P_CLOCK = 1, P_ROOM = 2, P_AIR = 4, P_LIGHTS = 8, P_TV = 16 };

struct Cfg {
  int bright = 160;          // 0..255 (SSD1306 contrast)
  bool flip = false;         // upside down, for mounting with the USB port on the left
  int cycle = 6;             // seconds per page
  int pages = P_CLOCK | P_ROOM | P_AIR | P_LIGHTS | P_TV;
  bool clock24 = true;
  bool tempF = false;
  bool nightOn = false;
  int nightFrom = 23 * 60, nightTo = 7 * 60;
  int nightMode = 1;         // 0 screen off, 1 dim clock only
  bool countdownWakes = true;// show the TV-off countdown even at night
  bool on = true;            // master switch
};
static Cfg cfg;
static uint32_t identifyUntil = 0;
static String bridgeName;

static void apply() {
  if (!oled::present()) return;
  oled::g->setFlipMode(cfg.flip ? 1 : 0);
  oled::g->setContrast(cfg.bright);
}

static void toJson(JsonObject o) {
  o["bright"] = cfg.bright; o["flip"] = cfg.flip; o["cycle"] = cfg.cycle; o["pages"] = cfg.pages;
  o["clock24"] = cfg.clock24; o["tempF"] = cfg.tempF; o["nightOn"] = cfg.nightOn;
  o["nightFrom"] = cfg.nightFrom; o["nightTo"] = cfg.nightTo; o["nightMode"] = cfg.nightMode;
  o["countdownWakes"] = cfg.countdownWakes; o["on"] = cfg.on; o["present"] = oled::present();
}

static void fromJson(JsonObject o) {
  if (!o["bright"].isNull()) cfg.bright = constrain(o["bright"].as<int>(), 0, 255);
  if (!o["flip"].isNull()) cfg.flip = o["flip"];
  if (!o["cycle"].isNull()) cfg.cycle = constrain(o["cycle"].as<int>(), 2, 120);
  if (!o["pages"].isNull()) cfg.pages = o["pages"].as<int>() & 31;
  if (!o["clock24"].isNull()) cfg.clock24 = o["clock24"];
  if (!o["tempF"].isNull()) cfg.tempF = o["tempF"];
  if (!o["nightOn"].isNull()) cfg.nightOn = o["nightOn"];
  if (!o["nightFrom"].isNull()) cfg.nightFrom = constrain(o["nightFrom"].as<int>(), 0, 1439);
  if (!o["nightTo"].isNull()) cfg.nightTo = constrain(o["nightTo"].as<int>(), 0, 1439);
  if (!o["nightMode"].isNull()) cfg.nightMode = constrain(o["nightMode"].as<int>(), 0, 1);
  if (!o["countdownWakes"].isNull()) cfg.countdownWakes = o["countdownWakes"];
  if (!o["on"].isNull()) cfg.on = o["on"];
}

static void load() {
  String s = prefs.getString("disp", "");
  if (s.length()) {
    JsonDocument d;
    if (!deserializeJson(d, s)) fromJson(d.as<JsonObject>());
  }
  apply();
}

static void save() {
  JsonDocument d;
  toJson(d.to<JsonObject>());
  d.remove("present");
  String s;
  serializeJson(d, s);
  prefs.putString("disp", s);
}

// ---------------------------------------------------------------------------------------------
// Drawing helpers

static U8G2 &G() { return *oled::g; }

static void centered(const String &s, int y) {
  int w = G().getStrWidth(s.c_str());
  G().drawStr((128 - w) / 2, y, s.c_str());
}

static void wifiBars(int x, int y) {   // y = baseline
  int rssi = WiFi.RSSI();
  int bars = WiFi.status() != WL_CONNECTED ? 0 : rssi > -55 ? 4 : rssi > -65 ? 3 : rssi > -75 ? 2 : 1;
  for (int i = 0; i < 4; i++) {
    int h = 3 + i * 2;
    if (i < bars) G().drawBox(x + i * 3, y - h, 2, h);
    else G().drawPixel(x + i * 3, y - 1);
  }
}

static void tvIcon(int x, int y) {     // 11x9, y = top
  G().drawFrame(x, y, 11, 7);
  G().drawHLine(x + 3, y + 8, 5);
}

static String timeText(bool seconds = false) {
  time_t now = time(nullptr);
  if (now < 1700000000) return "--:--";
  now += utcOffset;
  struct tm t;
  gmtime_r(&now, &t);
  char b[12];
  int h = t.tm_hour;
  if (!cfg.clock24) { h %= 12; if (!h) h = 12; }
  if (seconds) snprintf(b, sizeof(b), "%d:%02d:%02d", h, t.tm_min, t.tm_sec);
  else snprintf(b, sizeof(b), cfg.clock24 ? "%02d:%02d" : "%d:%02d", h, t.tm_min);
  return String(b);
}

static String dateText() {
  time_t now = time(nullptr);
  if (now < 1700000000) return "";
  now += utcOffset;
  struct tm t;
  gmtime_r(&now, &t);
  static const char *days[] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
  static const char *mons[] = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
  return String(days[t.tm_wday]) + " " + mons[t.tm_mon] + " " + t.tm_mday;
}

static void statusBar(const String &title) {
  G().setFont(u8g2_font_helvB08_tr);
  G().drawStr(0, 10, title.c_str());
  int x = 128 - 13;
  wifiBars(x, 11);
  if (tvState == TV_ON) { x -= 15; tvIcon(x, 2); }
  if (!followTV) { x -= 10; G().drawStr(x, 10, "||"); }   // TV rules paused
}

// Big value with a small unit, centered in the blue area.
static void bigValue(const String &v, const String &unit, int y = 58) {
  G().setFont(u8g2_font_logisoso28_tn);
  int w = G().getStrWidth(v.c_str());
  G().setFont(u8g2_font_helvB10_tr);
  int uw = unit.length() ? G().getStrWidth(unit.c_str()) + 3 : 0;
  int x = (128 - w - uw) / 2;
  G().setFont(u8g2_font_logisoso28_tn);
  G().drawStr(x, y, v.c_str());
  if (unit.length()) {
    G().setFont(u8g2_font_helvB10_tr);
    G().drawStr(x + w + 3, y, unit.c_str());
  }
}

static void bodyLines(const char *a, const char *b, const char *c = nullptr, const char *d = nullptr) {
  G().setFont(u8g2_font_6x10_tr);
  const char *ls[] = {a, b, c, d};
  for (int i = 0; i < 4; i++) if (ls[i]) G().drawStr(0, 27 + i * 11, ls[i]);
}

static const char *aqLabel(float pm) {
  if (pm <= 9) return "Good";
  if (pm <= 35.4) return "Moderate";
  if (pm <= 55.4) return "Sensitive";
  if (pm <= 125.4) return "Unhealthy";
  return "Very bad";
}

// ---------------------------------------------------------------------------------------------
// Pages

static bool hasData(int p) {
  switch (p) {
    case P_CLOCK: return true;
#ifdef HAS_GOVEE
    case P_ROOM: return govee::locked && !govee::stale();
#else
    case P_ROOM: return false;
#endif
    case P_AIR: return pur.configured && ps.pm >= 0;
    case P_LIGHTS: return !lights.empty();
    case P_TV: return tvAddr().length() > 0;
  }
  return false;
}

static void pageClock() {
  statusBar(dateText());
  G().setFont(u8g2_font_logisoso28_tn);
  centered(timeText(), 56);
}

static void pageRoom() {
#ifdef HAS_GOVEE
  float t = govee::temp, h = govee::hum;
  if (cfg.tempF) t = t * 9 / 5 + 32;
  statusBar("Room  " + timeText());
  G().setFont(u8g2_font_logisoso28_tn);
  String tv = String(t, 1);
  G().drawStr(0, 56, tv.c_str());
  int w = G().getStrWidth(tv.c_str());
  G().drawCircle(w + 4, 30, 2);
  G().setFont(u8g2_font_helvB10_tr);
  G().drawStr(w + 8, 40, cfg.tempF ? "F" : "C");
  String hs = String((int)lroundf(h)) + "%";
  G().setFont(u8g2_font_helvB12_tr);
  G().drawStr(128 - G().getStrWidth(hs.c_str()), 42, hs.c_str());
  G().setFont(u8g2_font_6x10_tr);
  G().drawStr(128 - G().getStrWidth("humidity"), 56, "humidity");
#endif
}

static void pageAir() {
  statusBar(String("Air  ") + aqLabel(ps.pm));
  String v = String((int)lroundf(ps.pm));
  G().setFont(u8g2_font_logisoso28_tn);
  G().drawStr(0, 56, v.c_str());
  int w = G().getStrWidth(v.c_str());
  G().setFont(u8g2_font_6x10_tr);
  G().drawStr(w + 4, 44, "PM2.5");
  G().drawStr(w + 4, 56, "ug/m3");
  String s = !ps.on ? "off" : ps.autoMode ? "auto" : ps.fanIdx >= 0 ? "fan " + String(ps.fanIdx + 1) : "on";
  G().setFont(u8g2_font_helvB10_tr);
  G().drawStr(128 - G().getStrWidth(s.c_str()), 56, s.c_str());
}

static void pageLights() {
  int on = 0, ok = 0;
  xSemaphoreTake(stateLock, portMAX_DELAY);
  for (auto &L : lights) { if (L.on) on++; if (L.ok) ok++; }
  xSemaphoreGive(stateLock);
  statusBar("Lights  " + timeText());
  G().setFont(u8g2_font_logisoso28_tn);
  String v = String(on);
  G().drawStr(0, 56, v.c_str());
  int w = G().getStrWidth(v.c_str());
  G().setFont(u8g2_font_helvB10_tr);
  String of = "of " + String(lights.size()) + " on";
  G().drawStr(w + 6, 56, of.c_str());
  if (ok < (int)lights.size()) {
    G().setFont(u8g2_font_6x10_tr);
    String bad = String(lights.size() - ok) + " not answering";
    G().drawStr(w + 6, 30, bad.c_str());
  }
}

static void pageTV() {
  statusBar("TV  " + timeText());
  G().setFont(u8g2_font_helvB18_tr);
  const char *s = tvState == TV_ON ? "On" : tvState == TV_OFF ? "Off" : "...";
  G().drawStr(0, 46, s);
  G().setFont(u8g2_font_6x10_tr);
  String d = "lights off after " + String(tvOff.delay < 0 ? learnedDelay() : tvOff.delay) + "s";
  if (!followTV) d = "TV rules paused";
  G().drawStr(0, 60, d.c_str());
}

static void pageCountdown() {
  int left = max(0, (int)((int32_t)(ruleDueMs - millis()) / 1000));
  statusBar("TV off");
  G().setFont(u8g2_font_6x10_tr);
  G().drawStr(0, 27, "Lights off in");
  char b[8];
  snprintf(b, sizeof(b), "%d:%02d", left / 60, left % 60);
  G().setFont(u8g2_font_logisoso28_tn);
  G().drawStr(128 - G().getStrWidth(b), 60, b);
}

static int nowMinutes() {
  time_t now = time(nullptr);
  if (now < 1700000000) return -1;
  now += utcOffset;
  return (int)((now % 86400) / 60);
}

static bool isNight() {
  if (!cfg.nightOn) return false;
  int m = nowMinutes();
  if (m < 0 || cfg.nightFrom == cfg.nightTo) return false;
  if (cfg.nightFrom < cfg.nightTo) return m >= cfg.nightFrom && m < cfg.nightTo;
  return m >= cfg.nightFrom || m < cfg.nightTo;
}

static int pageIdx = 0;
static uint32_t pageSince = 0;
static bool dimmed = false, blank = false;

// The BOOT button (GPIO0 on ESP32/S3, GPIO9 on C3) wakes the screen for 30 s, even when it's set to off.
#if defined(CONFIG_IDF_TARGET_ESP32C3)
static const int WAKE_PIN = 9;
#else
static const int WAKE_PIN = 0;
#endif
static uint32_t wakeUntil = 0;
static bool wakeInit = false;
static uint32_t heldSince = 0;
static uint32_t clearedAt = 0;

// Holding BOOT for 8 s clears every app pairing (Afterglow, Keystone, Subwave, Exhale, Redshift, Equinox).
// Wi-Fi, Apple Home and all device settings stay. Physical access is the proof of ownership.
static void clearAllPairings() {
  token = ""; prefs.remove("token");
  barToken = ""; prefs.remove("bartoken");
  for (const char *k : {"tok_keystone", "tok_exhale", "tok_redshift", "tok_equinox", "tok_nightjar"}) prefs.remove(k);
  logEvent("All app pairings cleared with the BOOT button");
  clearedAt = millis();
  if (!clearedAt) clearedAt = 1;
}

static void draw() {
  if (!wakeInit) { pinMode(WAKE_PIN, INPUT_PULLUP); wakeInit = true; wakeUntil = 60000; }   // on for the first minute after boot
  if (digitalRead(WAKE_PIN) == LOW) {
    wakeUntil = millis() + 30000;
    if (!heldSince) heldSince = millis();
    if (heldSince != 1 && millis() - heldSince >= 8000) { clearAllPairings(); heldSince = 1; }
  } else {
    heldSince = 0;
  }
  if (!oled::present()) return;   // the button reset above works without a screen too
  bool woke = (int32_t)(wakeUntil - millis()) > 0;
  bool ident = (identifyUntil && (int32_t)(identifyUntil - millis()) > 0) || woke;
  bool countdown = ruleDueMs != 0;
  bool night = isNight() && !ident;
  bool off = (!cfg.on || (night && cfg.nightMode == 0)) && !ident && !(countdown && cfg.countdownWakes);
  if (off) {
    if (!blank) { G().clearBuffer(); G().sendBuffer(); G().setPowerSave(1); blank = true; }
    return;
  }
  if (blank) { G().setPowerSave(0); blank = false; }
  bool dim = night && cfg.nightMode == 1 && !(countdown && cfg.countdownWakes);
  if (dim != dimmed) { G().setContrast(dim ? 1 : cfg.bright); dimmed = dim; }

  G().clearBuffer();
  wifi_mode_t mode = WiFi.getMode();
  if (clearedAt && millis() - clearedAt < 15000) {
    statusBar("Pairings cleared");
    bodyLines("All apps can pair", "again. Wi-Fi and", "Apple Home are kept.", nullptr);
  } else if (heldSince > 1 && millis() - heldSince > 1000) {
    statusBar("Keep holding BOOT");
    int left = max(0, 8 - (int)((millis() - heldSince) / 1000));
    String l = "Clears app pairings in " + String(left) + "s";
    bodyLines(l.c_str(), "Let go to cancel.", nullptr, nullptr);
  } else if (woke && !(identifyUntil && (int32_t)(identifyUntil - millis()) > 0)) {
    // Woken by the button or just booted: who and where it is.
    statusBar(bridgeName);
    String l2 = WiFi.status() == WL_CONNECTED ? WiFi.localIP().toString() : ((mode & WIFI_AP) ? "Setup: Keystone-Setup" : "Connecting to Wi-Fi");
    String l3 = String("Firmware ") + FW_VERSION;
    String l4 = safeMode ? "Safe mode: restart it" : (cfg.on ? "" : "Screen is set to off");
    bodyLines(l2.c_str(), l3.c_str(), l4.length() ? l4.c_str() : nullptr, nullptr);
  } else if (ident) {
    G().setFont(u8g2_font_helvB12_tr);
    centered("Hello!", 12);
    G().setFont(u8g2_font_6x10_tr);
    centered("This is your bridge", 36);
    centered(WiFi.localIP().toString(), 52);
    if ((millis() / 400) % 2) G().drawFrame(0, 0, 128, 64);
  } else if (WiFi.status() != WL_CONNECTED && (mode & WIFI_AP)) {
    statusBar(String("Wi-Fi setup ") + String(ESP.getFreeHeap() / 1024) + "K");
    if (provision::status.length()) {
      String a = provision::status.substring(0, 21), b = provision::status.substring(21, 42), c = provision::status.substring(42, 63);
      bodyLines(a.c_str(), b.c_str(), c.c_str(), nullptr);
    } else {
      bodyLines("Join Keystone-Setup", "(no password), or on", "a computer go to", "soum91.github.io/...");
    }
  } else if (WiFi.status() != WL_CONNECTED) {
    statusBar("Connecting...");
    bodyLines("Looking for Wi-Fi.", "Wrong network? Reset", "Wi-Fi in Keystone or", "type W in console");
  } else if (!token.length() && devToken("keystone").isEmpty()) {
    statusBar(WiFi.localIP().toString());
    bodyLines("Pair in Keystone,", "then Home app: add", "Keystone Bridge,", "code 466-37-726");
  } else if (countdown) {
    pageCountdown();
  } else if (dim) {
    pageClock();
  } else {
    // Rotate through enabled pages that have something to show.
    int order[] = {P_CLOCK, P_ROOM, P_AIR, P_LIGHTS, P_TV};
    if (millis() - pageSince > (uint32_t)cfg.cycle * 1000UL) { pageIdx++; pageSince = millis(); }
    int p = 0;
    for (int tries = 0; tries < 5; tries++) {
      int cand = order[(pageIdx + tries) % 5];
      if ((cfg.pages & cand) && hasData(cand)) { p = cand; pageIdx = (pageIdx + tries) % 5; break; }
    }
    switch (p) {
      case P_ROOM: pageRoom(); break;
      case P_AIR: pageAir(); break;
      case P_LIGHTS: pageLights(); break;
      case P_TV: pageTV(); break;
      default: pageClock(); break;
    }
  }
  G().sendBuffer();
}

// ---------------------------------------------------------------------------------------------
// Keystone API. Keystone pairs like Exhale/Redshift (app=keystone) and can manage the bridge.

static volatile int pendingAction = 0;   // run on HomeSpan's core: 1 restart, 2 forget Wi-Fi

static bool adminOK() {
  String k = devToken("keystone");
  if (k.length() && server.header("X-Device-Token") == k) return true;
  return token.length() && server.header("X-Afterglow-Token") == token;
}

static void deny() { server.send(401, "application/json", "{\"error\":\"unauthorized\"}"); }

static void handleDisplay() {
  if (!adminOK()) return deny();
  if (server.method() == HTTP_POST) {
    JsonDocument d;
    if (deserializeJson(d, server.arg("plain"))) { server.send(400, "application/json", "{\"error\":\"bad json\"}"); return; }
    fromJson(d.as<JsonObject>());
    save();
    apply();
    dimmed = false;
  }
  JsonDocument r;
  toJson(r.to<JsonObject>());
  String out;
  serializeJson(r, out);
  server.send(200, "application/json", out);
}

static void handleIdentify() {
  if (!adminOK()) return deny();
  identifyUntil = millis() + 8000;
  if (!identifyUntil) identifyUntil = 1;
  server.send(200, "application/json", "{\"ok\":true}");
}

// The screen as a switch in Apple Home (on = the screen's normal settings, off = dark).
struct HomeSwitch : Service::Switch {
  SpanCharacteristic *on;
  HomeSwitch() : Service::Switch() {
    on = new Characteristic::On(cfg.on);
    new Characteristic::Name("Bridge Screen");
  }
  boolean update() override { cfg.on = on->getNewVal(); save(); return true; }
  void loop() override { if (on->getVal() != (int)cfg.on && on->timeVal() > 2000) on->setVal(cfg.on); }
};

static void handleAdmin() {
  if (!adminOK()) return deny();
  JsonDocument d;
  deserializeJson(d, server.arg("plain"));
  String a = d["action"] | "";
  if (a == "restart" || a == "normal") {
    prefs.putInt("crashes", 0);   // a deliberate restart always comes back in normal mode
    pendingAction = 1;
  } else if (a == "forgetWifi") {
    pendingAction = 2;
  } else if (a == "forgetGovee") {
    prefs.remove("gv_addr");
    prefs.remove("gv_name");
    pendingAction = 1;
  } else if (a == "resetPairing") {
    String app = d["app"] | "";
    if (app == "afterglow") { token = ""; prefs.remove("token"); }
    else if (app == "subwave") { barToken = ""; prefs.remove("bartoken"); }
    else if (app == "exhale" || app == "redshift" || app == "equinox" || app == "nightjar") prefs.remove(("tok_" + app).c_str());
    else { server.send(400, "application/json", "{\"error\":\"unknown app\"}"); return; }
    logEvent(app + " pairing cleared");
  } else if (a == "follow") {
    if (!d["lights"].isNull()) { followTV = d["lights"]; prefs.putBool("follow", followTV); if (!followTV) ruleDueMs = 0; }
    if (!d["bar"].isNull()) { barFollow = d["bar"]; prefs.putBool("barFollow", barFollow); if (!barFollow) barOffDueMs = 0; }
  } else if (a == "rename") {
    String n = d["name"] | "";
    n.trim();
    if (n.length() < 1 || n.length() > 32) { server.send(400, "application/json", "{\"error\":\"name must be 1 to 32 characters\"}"); return; }
    prefs.putString("bridgeName", n);
    logEvent("Renamed to " + n);
    pendingAction = 1;
  } else {
    server.send(400, "application/json", "{\"error\":\"unknown action\"}");
    return;
  }
  server.send(200, "application/json", String("{\"ok\":true,\"restart\":") + (pendingAction ? "true" : "false") + "}");
}

static void registerRoutes() {
  server.on("/api/display", HTTP_GET, handleDisplay);
  server.on("/api/display", HTTP_POST, handleDisplay);
  server.on("/api/identify", HTTP_POST, handleIdentify);
  server.on("/api/admin", HTTP_POST, handleAdmin);
}

static void info(JsonDocument &d) {
  d["name"] = bridgeName;
  d["ip"] = WiFi.localIP().toString();
  d["rssi"] = WiFi.RSSI();
  d["ssid"] = WiFi.SSID();
  d["heap"] = ESP.getFreeHeap();
  d["heapBlock"] = ESP.getMaxAllocHeap();
  d["keystone"] = devToken("keystone").length() > 0;
  d["barFollow"] = barFollow;
  if (ruleDueMs) d["countdown"] = max(0, (int)((int32_t)(ruleDueMs - millis()) / 1000));
  JsonObject s = d["display"].to<JsonObject>();
  toJson(s);
  d["paired"]["afterglow"] = token.length() > 0;
  d["paired"]["subwave"] = barToken.length() > 0;
  d["paired"]["exhale"] = devToken("exhale").length() > 0;
  d["paired"]["redshift"] = devToken("redshift").length() > 0;
  d["paired"]["equinox"] = devToken("equinox").length() > 0;
  d["paired"]["nightjar"] = devToken("nightjar").length() > 0;
}

// From loop(), on HomeSpan's core.
static void runPending() {
  int a = pendingAction;
  if (!a) return;
  pendingAction = 0;
  delay(600);   // let the HTTP reply go out
  if (a == 2) {
    logEvent("Forgetting Wi-Fi");
    homeSpan.processSerialCommand("X");   // erases Wi-Fi and restarts into setup
  }
  ESP.restart();
}

}  // namespace screen
