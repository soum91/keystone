// Hisense / ConnectLife air conditioner, sent from Equinox. The bridge logs into ConnectLife itself
// (same flow as Equinox: Gigya login -> JWT -> HijuConn OAuth -> RSA-signed gateway calls), so the AC
// works from Apple Home and Smart Auto keeps running with every phone asleep or away.
//
// In Home it's a heater/cooler tile:
//   Cool / Heat  -> the unit's own mode with that target
//   Auto         -> Smart Auto: cool above the cooling threshold, heat below the heating threshold,
//                   using the Govee sensor when it's fresh (the AC's own sensor otherwise), with the same
//                   5 minute confirm and 30 minute minimum dwell as Equinox, and never a repeated command.
// Network calls run on their own task, so a slow cloud never holds up the lights.
#pragma once
#include <WiFiClientSecure.h>
#include <mbedtls/pk.h>
#include <mbedtls/sha256.h>
#include <mbedtls/base64.h>

namespace ac {

// ---------------------------------------------------------------------------------------------
// Config (from Equinox)

struct Cfg {
  bool configured = false;
  String user, pass, puid, name = "Air Conditioner";
  bool heatSupported = true;
  // Smart Auto, in °C
  bool autoOn = false;
  float setpoint = 21, band = 3;
};
static Cfg cfg;
static bool inHome = false;
static String homeSig;

static String signature(const Cfg &c) { return c.configured ? c.puid + "|" + c.name + "|" + (c.heatSupported ? "h" : "") : ""; }

static bool parseCfg(const String &json, Cfg &out) {
  JsonDocument d;
  if (deserializeJson(d, json)) return false;
  Cfg c;
  JsonObject o = d["ac"];
  if (!o.isNull()) {
    c.user = o["user"] | ""; c.pass = o["pass"] | ""; c.puid = o["puid"] | "";
    c.name = o["name"] | "Air Conditioner";
    if (!c.name.length()) c.name = "Air Conditioner";
    c.heatSupported = o["heat"] | true;
    c.autoOn = o["auto"]["enabled"] | false;
    c.setpoint = o["auto"]["setpoint"] | 21.0f;
    c.band = o["auto"]["band"] | 3.0f;
    c.band = constrain(c.band, 0.5f, 8.0f);
    c.configured = c.user.length() && c.pass.length() && c.puid.length();
  }
  out = c;
  return true;
}

static void saveAuto() {
  // Keep the stored config in step when Smart Auto changes from Home.
  String s = readFile("/equinox.json");
  JsonDocument d;
  if (deserializeJson(d, s)) return;
  d["ac"]["auto"]["enabled"] = cfg.autoOn;
  d["ac"]["auto"]["setpoint"] = cfg.setpoint;
  d["ac"]["auto"]["band"] = cfg.band;
  String out;
  serializeJson(d, out);
  writeFile("/equinox.json", out);
}

// ---------------------------------------------------------------------------------------------
// Live state

struct State {
  bool known = false, online = false, on = false, fahrenheit = false;
  int mode = 2;          // 0 fan, 1 heat, 2 cool, 3 dry, 4 auto (unit's own)
  int target = 22;       // in the unit's scale
  float indoorC = NAN;
  int fan = 0;
  uint32_t polledAt = 0;
  String error;
  // Smart Auto bookkeeping
  int pendingMode = -1;
  uint32_t pendingSince = 0, lastSwitch = 0;
  int lastSentMode = -1, lastSentTarget = -1;
};
static State st;
static SemaphoreHandle_t lock;
static volatile bool wantPoll = true;
static volatile uint32_t homeSetAt = 0;

// Commands from Home, run on the AC task.
struct Cmd { String props; bool userAuto; };
static std::vector<Cmd> cmds;

static void enqueueProps(const String &props) {
  xSemaphoreTake(lock, portMAX_DELAY);
  cmds.push_back(Cmd{props, false});
  xSemaphoreGive(lock);
}
static void enqueueAutoNow() {
  xSemaphoreTake(lock, portMAX_DELAY);
  cmds.push_back(Cmd{"", true});
  xSemaphoreGive(lock);
}

// ---------------------------------------------------------------------------------------------
// ConnectLife

static const char *GIGYA_KEY = "4_yhTWQmHFpZkQZDSV1uV-_A";
static const char *CLIENT_ID = "5065059336212";
static const char *CLIENT_SECRET = "07swfKgvJhC3ydOUS9YV_SwVz0i4LKqlOLGNUukYHVMsJRF1b-iWeUGcNlXyYCeK";
static const char *REDIRECT = "https://api.connectlife.io/swagger/oauth2-redirect.html";
static const char *GATEWAY = "https://clife-eu-gateway.hijuconn.com";
static const char *APP_ID = "47110565134383";
static const char *APP_SECRET = "yOzhz6junYno-nmULM3Wr7PU_dpSZN22ZdluvVWZ4uW5ZwwG8fIGCHTbrhcnU-iv";
static const char *SIGN_SUFFIX = "D9519A4B756946F081B7BB5B5E8D1197";
// Gateway RSA public key as SubjectPublicKeyInfo (Equinox has the bare PKCS#1 form).
static const char *PUBKEY_B64 =
    "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyyWrNG6q475HIHu7sMVuvHof6vlgPeixmxa4EL/UsvVvHPz33NnWoQetQqit9TBNzUjMXw0KlY9PXM4iqHUUU+dSyNDq1jZWIiJ2C2FccppswJtIKL3NRMFvT9PFh6NlP/4FUcQKojgKFbF7KaccJPKYHlwaO7qgoIjLxAHlSOXGpucJcOkPzT2EqsSVnW8sn8kenvNmghXDayhgxsh6AyxK4kehJplEnmX/iYCfNoFXknGcLqFWYccgBz3fybvx30C/0IgU1980L8QsUAv5esZmN8ugnbRgLRxKRlkQQLxQAiZMZdKTAx665YflT3YMHJvEFE8c2XFgoxHzSMc4BwIDAQAB";

static String accessToken, refreshToken;
static uint32_t tokenExpiresAt = 0;   // millis

static String urlEncode(const String &s) {
  String o;
  const char *hex = "0123456789ABCDEF";
  for (size_t i = 0; i < s.length(); i++) {
    char c = s[i];
    if (isalnum((unsigned char)c) || c == '-' || c == '_' || c == '.' || c == '~') o += c;
    else { o += '%'; o += hex[(c >> 4) & 15]; o += hex[c & 15]; }
  }
  return o;
}

static String netErr;   // why the last HTTPS call failed, with memory numbers

static int http(const char *method, const String &url, const String &ctype, const String &body, String &out) {
  workerBeat = millis();   // these calls run on the worker; a slow handshake isn't a hang
  if (ESP.getMaxAllocHeap() < 30000) {
    netErr = "low memory, free " + String(ESP.getFreeHeap() / 1024) + "K, block " + String(ESP.getMaxAllocHeap() / 1024) + "K";
    return -1;
  }
  WiFiClientSecure c;
  c.setInsecure();
  c.setHandshakeTimeout(20);   // seconds (setTimeout is milliseconds on this core: 15 there broke every handshake)
  HTTPClient h;
  h.setConnectTimeout(8000);
  h.setTimeout(15000);
  if (!h.begin(c, url)) return -1;
  h.addHeader("User-Agent", "KeystoneBridge/1.0");
  if (ctype.length()) h.addHeader("Content-Type", ctype);
  int code = String(method) == "GET" ? h.GET() : h.POST(body);
  out = code > 0 ? h.getString() : "";
  workerBeat = millis();
  if (code <= 0) {
    char buf[96] = "";
    c.lastError(buf, sizeof(buf));
    netErr = String(buf[0] ? buf : HTTPClient::errorToString(code).c_str()) + ", free " + String(ESP.getFreeHeap() / 1024) +
             "K, block " + String(ESP.getMaxAllocHeap() / 1024) + "K";
  }
  h.end();
  return code;
}

static String form(std::initializer_list<std::pair<const char *, String>> kv) {
  String s;
  for (auto &p : kv) { if (s.length()) s += '&'; s += urlEncode(p.first) + "=" + urlEncode(p.second); }
  return s;
}

static int rng(void *, unsigned char *b, size_t n) { esp_fill_random(b, n); return 0; }

static String signString(const String &plain) {
  uint8_t digest[32];
  mbedtls_sha256((const unsigned char *)plain.c_str(), plain.length(), digest, 0);
  static uint8_t der[300];
  static size_t derLen = 0;
  if (!derLen) mbedtls_base64_decode(der, sizeof(der), &derLen, (const unsigned char *)PUBKEY_B64, strlen(PUBKEY_B64));
  mbedtls_pk_context pk;
  mbedtls_pk_init(&pk);
  String out;
  if (mbedtls_pk_parse_public_key(&pk, der, derLen) == 0) {
    uint8_t enc[256];
    size_t olen = 0;
    if (mbedtls_pk_encrypt(&pk, digest, 32, enc, &olen, sizeof(enc), rng, nullptr) == 0) {
      unsigned char b64[400];
      size_t blen = 0;
      mbedtls_base64_encode(b64, sizeof(b64), &blen, enc, olen);
      out = String((const char *)b64).substring(0, blen);
    }
  }
  mbedtls_pk_free(&pk);
  return out;
}

static bool tokenRequest(const String &extra, String &err) {
  String body = form({{"client_id", CLIENT_ID}, {"client_secret", CLIENT_SECRET}, {"redirect_uri", REDIRECT}}) + "&" + extra;
  String out;
  int code = http("POST", "https://oauth.hijuconn.com/oauth/token", "application/x-www-form-urlencoded", body, out);
  JsonDocument d;
  if (code != 200 || deserializeJson(d, out) || !d["access_token"].is<const char *>()) { err = "token HTTP " + String(code) + (code <= 0 ? " (" + netErr + ")" : ""); return false; }
  accessToken = d["access_token"].as<String>();
  if (d["refresh_token"].is<const char *>()) { refreshToken = d["refresh_token"].as<String>(); prefs.putString("ac_rt", refreshToken); }
  long exp = d["expires_in"] | 3600L;
  tokenExpiresAt = millis() + (uint32_t)max(60L, exp - 90) * 1000UL;
  return true;
}

static bool fullLogin(String &err) {
  String out;
  int code = http("POST", "https://accounts.eu1.gigya.com/accounts.login", "application/x-www-form-urlencoded",
                  form({{"loginID", cfg.user}, {"password", cfg.pass}, {"APIKey", GIGYA_KEY}}), out);
  JsonDocument f;
  f["errorCode"] = true; f["errorDetails"] = true; f["UID"] = true; f["sessionInfo"]["cookieValue"] = true;
  JsonDocument d;
  if (code != 200 || deserializeJson(d, out, DeserializationOption::Filter(f))) { err = "login HTTP " + String(code) + (code <= 0 ? " (" + netErr + ")" : ""); return false; }
  int ec = d["errorCode"] | 0;
  if (ec) { err = ec == 206001 ? "accept ConnectLife's new terms in its app" : String("login: ") + (d["errorDetails"] | "wrong email or password"); return false; }
  String uid = d["UID"] | "", cookie = d["sessionInfo"]["cookieValue"] | "";
  code = http("POST", "https://accounts.eu1.gigya.com/accounts.getJWT", "application/x-www-form-urlencoded",
              form({{"APIKey", GIGYA_KEY}, {"login_token", cookie}}), out);
  JsonDocument j;
  if (code != 200 || deserializeJson(j, out) || !j["id_token"].is<const char *>()) { err = "JWT HTTP " + String(code) + (code <= 0 ? " (" + netErr + ")" : ""); return false; }
  JsonDocument a;
  a["client_id"] = CLIENT_ID; a["redirect_uri"] = REDIRECT; a["idToken"] = j["id_token"].as<String>();
  a["response_type"] = "code"; a["thirdType"] = "CDC"; a["thirdClientId"] = uid;
  String ab;
  serializeJson(a, ab);
  code = http("POST", "https://oauth.hijuconn.com/oauth/authorize", "application/json", ab, out);
  JsonDocument r;
  if (code != 200 || deserializeJson(r, out) || !r["code"].is<const char *>()) { err = "authorize HTTP " + String(code) + (code <= 0 ? " (" + netErr + ")" : ""); return false; }
  return tokenRequest(form({{"grant_type", "authorization_code"}, {"code", r["code"].as<String>()}}), err);
}

static bool ensureToken(String &err) {
  if (accessToken.length() && (int32_t)(tokenExpiresAt - millis()) > 0) return true;
  if (refreshToken.length() && tokenRequest(form({{"grant_type", "refresh_token"}, {"refresh_token", refreshToken}}), err)) return true;
  return fullLogin(err);
}

static String randHex() {
  char b[33];
  for (int i = 0; i < 16; i++) snprintf(b + i * 2, 3, "%02x", (unsigned)(esp_random() & 0xff));
  return String(b);
}

// One gateway call. `props` is the compact, key-sorted JSON for property/set ("" for the device list).
static bool gateway(bool list, const String &props, String &out, String &err, bool retry = true) {
  if (!ensureToken(err)) return false;
  // Every field, sorted by key, exactly as signed.
  std::vector<std::pair<String, String>> f = {
      {"accessToken", accessToken}, {"appId", APP_ID}, {"appSecret", APP_SECRET}, {"languageId", "12"},
      {"randStr", randHex()}, {"timeStamp", String((uint64_t)time(nullptr) * 1000ULL)}, {"timezone", "1.0"}, {"version", "5.0"}};
  if (!list) { f.push_back({"properties", props}); f.push_back({"puid", cfg.puid}); }
  std::sort(f.begin(), f.end(), [](const std::pair<String, String> &a, const std::pair<String, String> &b) { return strcmp(a.first.c_str(), b.first.c_str()) < 0; });
  String plain;
  for (auto &p : f) { if (plain.length()) plain += '&'; plain += p.first + "=" + p.second; }
  String sign = signString(plain + SIGN_SUFFIX);
  if (!sign.length()) { err = "signing failed"; return false; }
  int code;
  if (list) {
    String q;
    for (auto &p : f) q += (q.length() ? "&" : "") + p.first + "=" + urlEncode(p.second);
    q += "&sign=" + urlEncode(sign);
    code = http("GET", String(GATEWAY) + "/clife-svc/pu/get_device_status_list?" + q, "", "", out);
  } else {
    String b = "{";
    for (auto &p : f) {
      if (b.length() > 1) b += ',';
      b += "\"" + p.first + "\":";
      if (p.first == "properties") b += p.second;
      else { String v = p.second; v.replace("\\", "\\\\"); v.replace("\"", "\\\""); b += "\"" + v + "\""; }
    }
    b += ",\"sign\":\"" + sign + "\"}";
    code = http("POST", String(GATEWAY) + "/device/pu/property/set", "application/json", b, out);
  }
  if (code != 200) { err = "gateway HTTP " + String(code) + (code <= 0 ? " (" + netErr + ")" : ""); return false; }
  int rc = out.indexOf("\"resultCode\"");
  bool ok = rc >= 0 && (out.indexOf("\"resultCode\":0", rc) == rc || out.indexOf("\"resultCode\":\"0\"", rc) == rc);
  if (ok) return true;
  if (retry && out.indexOf("100026") >= 0) { accessToken = ""; refreshToken = ""; return gateway(list, props, out, err, false); }
  if (retry && out.indexOf("101005") >= 0) return gateway(list, props, out, err, false);
  int e = out.indexOf("errorDesc");
  err = e >= 0 ? out.substring(e + 12, min((int)out.length(), e + 80)) : "gateway error";
  return false;
}

static float toC(int v, bool f) { return f ? (v - 32) * 5.0f / 9.0f : (float)v; }
static int fromC(float c, bool f) { return f ? (int)lroundf(c * 9 / 5 + 32) : (int)lroundf(c); }

static bool poll() {
  String out, err;
  if (!gateway(true, "", out, err)) { st.error = err; return false; }
  JsonDocument filter;
  JsonObject fd = filter["response"]["deviceList"].add<JsonObject>();
  fd["puid"] = true; fd["offlineState"] = true; fd["statusList"] = true;
  JsonDocument d;
  if (deserializeJson(d, out, DeserializationOption::Filter(filter))) { st.error = "bad device list"; return false; }
  for (JsonObject dev : d["response"]["deviceList"].as<JsonArray>()) {
    if (cfg.puid != (dev["puid"] | "")) continue;
    JsonObject s = dev["statusList"];
    auto num = [&](const char *k, int def) { return s[k].isNull() ? def : (int)String(s[k].as<String>()).toFloat(); };
    xSemaphoreTake(lock, portMAX_DELAY);
    st.online = String(dev["offlineState"] | "1") == "1";
    st.on = num("t_power", 0) == 1;
    st.mode = num("t_work_mode", 2);
    st.fahrenheit = num("t_temp_type", 0) == 1;
    st.target = num("t_temp", st.fahrenheit ? 72 : 22);
    int in = num("f_temp_in", -999);
    st.indoorC = in == -999 ? NAN : toC(in, st.fahrenheit);
    st.fan = num("t_fan_speed", 0);
    st.known = true;
    st.polledAt = millis();
    st.error = "";
    xSemaphoreGive(lock);
    return true;
  }
  st.error = "AC not in this ConnectLife account";
  return false;
}

static bool send(const std::vector<std::pair<String, int>> &kv) {
  if (kv.empty()) return true;
  auto sorted = kv;
  std::sort(sorted.begin(), sorted.end(), [](const std::pair<String, int> &a, const std::pair<String, int> &b) { return strcmp(a.first.c_str(), b.first.c_str()) < 0; });
  String p = "{";
  for (auto &x : sorted) { if (p.length() > 1) p += ','; p += "\"" + x.first + "\":\"" + String(x.second) + "\""; }
  p += "}";
  String out, err;
  bool ok = gateway(false, p, out, err);
  if (!ok) { st.error = err; logEvent("AC: " + err); }
  return ok;
}

// ---------------------------------------------------------------------------------------------
// Smart Auto (port of Equinox's SmartAuto.decide)

static float roomC() {
#ifdef HAS_GOVEE
  if (govee::locked && !govee::stale()) return govee::temp;
#endif
  return st.indoorC;
}

static void runAuto(bool userAction) {
  if (!cfg.autoOn || !st.known || !st.online || !st.on) return;
  bool f = st.fahrenheit;
  int set = fromC(cfg.setpoint, f);
  float band = f ? cfg.band * 9 / 5 : cfg.band;
  int idleMode = cfg.heatSupported ? 1 : 0;
  bool inSmart = st.mode == 2 || st.mode == idleMode;
  float room = roomC();
  float roomU = isnan(room) ? NAN : (f ? room * 9 / 5 + 32 : room);
  int wanted = inSmart ? st.mode : 2;
  if (!isnan(roomU)) {
    if (roomU >= set + band) wanted = 2;
    else if (roomU <= set - band) wanted = idleMode;
    else if (!inSmart) wanted = roomU >= set ? 2 : idleMode;
  }
  std::vector<std::pair<String, int>> props;
  int newMode = -1;
  uint32_t now = millis();
  if (wanted != st.mode) {
    if (userAction || !inSmart) newMode = wanted;
    else {
      if (st.pendingMode != wanted) { st.pendingMode = wanted; st.pendingSince = now; }
      bool held = now - st.pendingSince >= 5UL * 60UL * 1000UL;
      bool dwell = !st.lastSwitch || now - st.lastSwitch >= 30UL * 60UL * 1000UL;
      if (held && dwell) newMode = wanted;
    }
  } else {
    st.pendingMode = -1;
  }
  if (newMode >= 0) props.push_back({"t_work_mode", newMode});
  int finalMode = newMode >= 0 ? newMode : st.mode;
  if ((finalMode == 1 || finalMode == 2) && st.target != set) {
    if (newMode >= 0 || userAction || st.lastSentTarget != set) props.push_back({"t_temp", set});
  }
  if (!userAction && newMode < 0 && st.lastSentTarget == set) {
    props.erase(std::remove_if(props.begin(), props.end(), [](const std::pair<String, int> &p) { return p.first == "t_temp"; }), props.end());
  }
  if (props.empty()) return;
  if (send(props)) {
    if (newMode >= 0) {
      st.lastSwitch = now; st.lastSentMode = newMode; st.pendingMode = -1;
      st.mode = newMode;
      logEvent(String("Smart Auto: ") + (newMode == 2 ? "cooling" : newMode == 1 ? "heating" : "fan") + " (room " + String(room, 1) + "C)");
    }
    for (auto &p : props) if (p.first == "t_temp") { st.lastSentTarget = p.second; st.target = p.second; }
  }
}

// ---------------------------------------------------------------------------------------------
// The AC task

static uint32_t lastPoll = 0;
static bool started = false;

// One pass, called from the worker task (no task of its own: saves 24 KB). Never runs while the
// Bluetooth radio is on, so the TLS handshake gets the memory.
static void netWork(const Cmd &c, bool have);

static void step() {
  if (!started) { refreshToken = prefs.getString("ac_rt", ""); started = true; }
  if (!acEnabled || millis() < 30000UL || otaActive || safeMode || setupOnly || !cfg.configured || govee::radioOn ||
      WiFi.status() != WL_CONNECTED || time(nullptr) < 1700000000) return;
  Cmd c{"", false};
  bool have = false;
  xSemaphoreTake(lock, portMAX_DELAY);
  if (!cmds.empty()) { c = cmds.front(); cmds.erase(cmds.begin()); have = true; }
  xSemaphoreGive(lock);
  if (!have && !(wantPoll || millis() - lastPoll > 60000UL)) return;
  // Clear the decks: ask the relay to let go of its memory, wait (briefly) until it has.
  acNetBusy = true;
  if (relayLetGo) relayLetGo();   // same task as the relay: hand its memory over directly
  netWork(c, have);
  acNetBusy = false;
}

static void netWork(const Cmd &c, bool have) {
  if (have) {
    if (c.props.length()) {
      // "k=v,k=v"
      std::vector<std::pair<String, int>> kv;
      int start = 0;
      while (start < (int)c.props.length()) {
        int comma = c.props.indexOf(',', start);
        if (comma < 0) comma = c.props.length();
        String part = c.props.substring(start, comma);
        int eq = part.indexOf('=');
        if (eq > 0) kv.push_back({part.substring(0, eq), part.substring(eq + 1).toInt()});
        start = comma + 1;
      }
      send(kv);
      lastPoll = millis() - 50000UL;   // read back shortly
    }
    if (c.userAuto) runAuto(true);
    return;
  }
  wantPoll = false;
  lastPoll = millis();
  if (poll()) runAuto(false);
}

// ---------------------------------------------------------------------------------------------
// Apple Home: heater/cooler

struct Tile : Service::HeaterCooler {
  SpanCharacteristic *active, *current, *target, *temp, *cool, *heat = nullptr, *speed, *units;
  Tile() : Service::HeaterCooler() {
    active = new Characteristic::Active(0);
    current = new Characteristic::CurrentHeaterCoolerState(0);
    target = new Characteristic::TargetHeaterCoolerState(2);
    if (!cfg.heatSupported) target->setValidValues(2, 0, 2);
    temp = new Characteristic::CurrentTemperature(21);
    cool = new Characteristic::CoolingThresholdTemperature(24);
    cool->setRange(16, 32, 0.5);
    if (cfg.heatSupported) {
      heat = new Characteristic::HeatingThresholdTemperature(18);
      heat->setRange(16, 32, 0.5);
    }
    speed = new Characteristic::RotationSpeed(0);
    speed->setRange(0, 100, 25);
    units = new Characteristic::TemperatureDisplayUnits(0);
    new Characteristic::Name(cfg.name.c_str());
  }

  boolean update() override {
    homeSetAt = millis();
    String p;
    auto add = [&](const char *k, int v) { if (p.length()) p += ','; p += String(k) + "=" + String(v); };
    bool f = st.fahrenheit;
    if (active->updated()) { add("t_power", active->getNewVal() ? 1 : 0); st.on = active->getNewVal(); }
    int t = target->updated() ? target->getNewVal() : target->getVal();
    float c = cool->updated() ? cool->getNewVal<float>() : cool->getVal<float>();
    float h = heat ? (heat->updated() ? heat->getNewVal<float>() : heat->getVal<float>()) : c - 2 * cfg.band;
    bool modeOrTemp = target->updated() || cool->updated() || (heat && heat->updated());
    if (modeOrTemp) {
      if (t == 0) {
        // Auto = Smart Auto between the two thresholds.
        if (c - h < 1) c = h + 1;
        cfg.setpoint = (c + h) / 2;
        cfg.band = max(0.5f, (c - h) / 2);
        cfg.autoOn = true;
        saveAuto();
        if (!active->updated() && !st.on) add("t_power", 1);
      } else {
        cfg.autoOn = false;
        saveAuto();
        if (t == 2) { add("t_work_mode", 2); add("t_temp", fromC(c, f)); st.mode = 2; }
        else if (t == 1 && cfg.heatSupported) { add("t_work_mode", 1); add("t_temp", fromC(h, f)); st.mode = 1; }
      }
    }
    if (speed->updated() && speed->getNewVal() > 0) {
      int s = speed->getNewVal();
      add("t_fan_speed", s <= 25 ? 2 : s <= 50 ? 3 : s <= 75 ? 4 : 0);   // low, med, high, then auto at 100
    }
    if (p.length()) enqueueProps(p);
    if (cfg.autoOn && (modeOrTemp || active->updated())) enqueueAutoNow();
    return true;
  }

  void loop() override {
    if (!st.known || millis() - homeSetAt < 8000) return;
    if (active->getVal() != (int)st.on) active->setVal(st.on);
    int cur = !st.on ? 0 : st.mode == 1 ? 2 : st.mode == 2 ? 3 : 1;
    if (current->getVal() != cur) current->setVal(cur);
    int tgt = cfg.autoOn ? 0 : st.mode == 1 ? 1 : 2;
    if (target->getVal() != tgt) target->setVal(tgt);
    float room = roomC();
    if (!isnan(room) && fabs(temp->getVal<float>() - room) >= 0.2f) temp->setVal(room);
    float tc = toC(st.target, st.fahrenheit);
    float cv = cfg.autoOn ? cfg.setpoint + cfg.band : tc;
    float hv = cfg.autoOn ? cfg.setpoint - cfg.band : tc;
    cv = constrain(cv, 16, 32); hv = constrain(hv, 16, 32);
    if (fabs(cool->getVal<float>() - cv) >= 0.25f) cool->setVal(cv);
    if (heat && fabs(heat->getVal<float>() - hv) >= 0.25f) heat->setVal(hv);
    int sp = st.fan == 2 ? 25 : st.fan == 3 ? 50 : st.fan == 4 ? 75 : 100;
    if (speed->getVal() != sp) speed->setVal(sp);
    int u = st.fahrenheit ? 1 : 0;
    if (units->getVal() != u) units->setVal(u);
  }
};

// ---------------------------------------------------------------------------------------------
// Setup, API, info

static void load() {
  lock = xSemaphoreCreateMutex();
  parseCfg(readFile("/equinox.json"), cfg);

}

static void addAccessory(std::vector<uint32_t> &used) {
  if (!cfg.configured) return;
  inHome = true;
  homeSig = signature(cfg);
  new SpanAccessory(aidFor("ac:" + cfg.puid, used));
    new Service::AccessoryInformation();
      new Characteristic::Identify();
      new Characteristic::Name(cfg.name.c_str());
      new Characteristic::Manufacturer("Hisense");
      new Characteristic::Model("ConnectLife AC");
    new Tile();
}

// From handleDevConfig for app=equinox. Returns true if Home needs a restart.
static bool applyConfig(const String &body) {
  Cfg c;
  if (!parseCfg(body, c)) return false;
  bool credsChanged = c.user != cfg.user || c.pass != cfg.pass;
  writeFile("/equinox.json", body);
  bool restart = signature(c) != homeSig;
  cfg = c;
  if (credsChanged) { accessToken = ""; refreshToken = ""; prefs.remove("ac_rt"); }
  wantPoll = true;
  if (cfg.autoOn) enqueueAutoNow();
  return restart;
}

static void info(JsonDocument &d) {
  JsonObject a = d["ac"].to<JsonObject>();
  a["configured"] = cfg.configured;
  if (!cfg.configured) return;
  a["name"] = cfg.name;
  a["ok"] = st.error.isEmpty() && st.known;
  if (st.error.length()) a["error"] = st.error;
  if (st.known) {
    a["on"] = st.on; a["mode"] = st.mode; a["target"] = st.target; a["fahrenheit"] = st.fahrenheit;
    if (!isnan(st.indoorC)) a["indoor"] = st.indoorC;
  }
  float r = roomC();
  if (!isnan(r)) a["room"] = r;
  JsonObject s = a["auto"].to<JsonObject>();
  s["enabled"] = cfg.autoOn; s["setpoint"] = cfg.setpoint; s["band"] = cfg.band;
  if (st.lastSwitch) s["lastSwitchAgo"] = (int)((millis() - st.lastSwitch) / 1000);
}

}  // namespace ac
