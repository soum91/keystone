// Time, solar, weather and temperature rules for Equinox and Afterglow.
// Rules are stored in each app's existing bridge configuration and run on the ESP32.
#pragma once
#include <math.h>

namespace sceneauto {

struct RuleEntry {
  String id, name, event, condition, acAction;
  Rule lightAction;
  bool isAC = false, window = false, onlyCloudy = false;
  int at = 1140, offset = 0, cloud = 75, from = 1080, to = 1380, fade = 0;
  float threshold = 25, conditionTemp = 25;
  int lastDay = -1;
  int lastState = -1; // unknown until first environmental sample
  uint32_t lastRunMs = 0;
};
static std::vector<RuleEntry> lightRules, acRules;
static double lat = NAN, lon = NAN;
static double afterglowLat = NAN, afterglowLon = NAN, equinoxLat = NAN, equinoxLon = NAN;
static float outdoorC = NAN;
static int cloudCover = -1;
static uint32_t weatherFetchedMs = 0;
static time_t weatherObservedAt = 0;

static void parseRules(const String &json, std::vector<RuleEntry> &out, bool ac) {
  JsonDocument doc;
  if (deserializeJson(doc, json)) return;
  if (!doc["utcOffset"].isNull()) utcOffset = doc["utcOffset"].as<long>();
  std::vector<RuleEntry> fresh;
  JsonObject weather = doc["weather"].as<JsonObject>();
  double newLat = NAN, newLon = NAN;
  if (!weather.isNull() && weather["lat"].is<double>() && weather["lon"].is<double>()) {
    double a = weather["lat"].as<double>(), b = weather["lon"].as<double>();
    if (a >= -90 && a <= 90 && b >= -180 && b <= 180) { newLat = a; newLon = b; }
  }
  if (ac) { equinoxLat = newLat; equinoxLon = newLon; }
  else { afterglowLat = newLat; afterglowLon = newLon; }
  double effectiveLat = isfinite(afterglowLat) ? afterglowLat : equinoxLat;
  double effectiveLon = isfinite(afterglowLon) ? afterglowLon : equinoxLon;
  if (effectiveLat != lat || effectiveLon != lon || isfinite(lat) != isfinite(effectiveLat)) {
    lat = effectiveLat; lon = effectiveLon;
    weatherFetchedMs = 0;
    weatherObservedAt = 0; // no readings from the previously configured place
    outdoorC = NAN;
    cloudCover = -1;
  }
  for (JsonObject item : doc["sceneRules"].as<JsonArray>()) {
    RuleEntry r;
    r.id = item["id"] | "";
    r.name = item["name"] | "Scene";
    r.event = item["event"] | "";
    if (!r.id.length() || !r.event.length() || r.event == "none") continue;
    r.isAC = ac;
    r.at = constrain(item["at"] | 1140, 0, 1439);
    r.offset = constrain(item["offset"] | 0, -120, 120);
    r.threshold = item["threshold"] | 25.0f;
    r.cloud = constrain(item["cloud"] | 75, 0, 100);
    r.window = item["window"] | false;
    r.from = constrain(item["from"] | 1080, 0, 1439);
    r.to = constrain(item["to"] | 1380, 0, 1439);
    r.onlyCloudy = item["onlyCloudy"] | false;
    r.condition = item["condition"] | "";
    r.conditionTemp = item["conditionTemp"] | 25.0f;
    r.fade = constrain(item["fade"] | 0, 0, 1800);
    if (ac) {
      serializeJson(item["ac"], r.acAction);
    } else {
      parseRule(item, r.lightAction);
      if (r.lightAction.actions.empty()) continue;
    }
    // Preserve trigger state when the app pushes an unchanged rule.
    for (const auto &old : out) if (old.id == r.id && old.event == r.event) {
      r.lastDay = old.lastDay; r.lastState = old.lastState; r.lastRunMs = old.lastRunMs;
      break;
    }
    if (fresh.size() < 20) fresh.push_back(r);
  }
  out.swap(fresh);
}

static void loadAfterglow(const String &json) { parseRules(json, lightRules, false); }
static void loadEquinox(const String &json) { parseRules(json, acRules, true); }

// NOAA solar geometry. A zenith of 90.833° means apparent sunset; 96° civil dusk.
static int sunMinute(bool dusk) {
  if (!isfinite(lat) || !isfinite(lon) || time(nullptr) < 1700000000) return -1;
  time_t local = time(nullptr) + utcOffset;
  struct tm t;
  gmtime_r(&local, &t);
  const double pi = 3.141592653589793;
  double gamma = 2 * pi / (t.tm_year % 4 == 0 ? 366.0 : 365.0) * (t.tm_yday + 0.5);
  double eq = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
                        - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma));
  double dec = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
               - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma)
               - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma);
  double phi = lat * pi / 180.0;
  double zenith = (dusk ? 96.0 : 90.833) * pi / 180.0;
  double cosH = (cos(zenith) - sin(phi) * sin(dec)) / (cos(phi) * cos(dec));
  if (cosH < -1 || cosH > 1) return -1; // no sunset at this latitude/date
  double sunsetUTC = 720 - 4 * lon - eq + 4 * acos(cosH) * 180 / pi;
  int result = (int)lround(sunsetUTC + utcOffset / 60.0);
  return ((result % 1440) + 1440) % 1440;
}

static bool needsWeather() {
  auto uses = [](const RuleEntry &r) {
    return r.event == "cloudy" || r.event == "outsideAbove" || r.event == "outsideBelow" ||
           r.onlyCloudy || r.condition == "outsideAbove" || r.condition == "outsideBelow";
  };
  for (const auto &r : lightRules) if (uses(r)) return true;
  for (const auto &r : acRules) if (uses(r)) return true;
  return false;
}

static bool weatherFresh() {
  return weatherObservedAt > 0 && time(nullptr) - weatherObservedAt < 2 * 3600;
}

static void updateWeather() {
  if (!needsWeather() || !isfinite(lat) || !isfinite(lon) || WiFi.status() != WL_CONNECTED ||
      otaActive || safeMode || govee::radioOn || acNetBusy || ESP.getMaxAllocHeap() < 32000) return;
  if (weatherFetchedMs && millis() - weatherFetchedMs < 15UL * 60UL * 1000UL) return;
  weatherFetchedMs = millis();
  String url = "https://api.open-meteo.com/v1/forecast?latitude=" + String(lat, 5) +
               "&longitude=" + String(lon, 5) + "&current=temperature_2m,cloud_cover&timezone=UTC";
  acNetBusy = true;
  if (relayLetGo) relayLetGo();
  WiFiClientSecure client;
  client.setInsecure();
  client.setHandshakeTimeout(10);
  HTTPClient http;
  http.setConnectTimeout(5000);
  http.setTimeout(6000);
  if (http.begin(client, url)) {
    int code = http.GET();
    if (code == 200) {
      JsonDocument doc;
      if (!deserializeJson(doc, http.getStream())) {
        JsonObject current = doc["current"];
        if (!current.isNull() && current["temperature_2m"].is<float>() && current["cloud_cover"].is<int>()) {
          outdoorC = current["temperature_2m"].as<float>();
          cloudCover = constrain(current["cloud_cover"].as<int>(), 0, 100);
          weatherObservedAt = time(nullptr);
        }
      }
    }
    http.end();
  }
  acNetBusy = false;
}

static float reading(const String &type) {
  if (type.startsWith("room")) return ac::roomC();
  if (!weatherFresh()) return NAN;
  return outdoorC;
}

static bool tempTest(const String &kind, float value, float threshold, bool releasing = false) {
  if (!isfinite(value)) return false;
  if (kind.endsWith("Above")) return value >= threshold - (releasing ? 0.5f : 0.0f);
  if (kind.endsWith("Below")) return value <= threshold + (releasing ? 0.5f : 0.0f);
  return true;
}

static bool conditions(const RuleEntry &r) {
  if (!inWindow(r.window, r.from, r.to)) return false;
  if (r.onlyCloudy && (!weatherFresh() || cloudCover < r.cloud)) return false;
  if (r.condition == "roomAbove" || r.condition == "roomBelow" ||
      r.condition == "outsideAbove" || r.condition == "outsideBelow") {
    if (!tempTest(r.condition, reading(r.condition), r.conditionTemp)) return false;
  }
  return true;
}

static String acProps(const RuleEntry &r) {
  JsonDocument doc;
  if (deserializeJson(doc, r.acAction)) return "";
  JsonObject a = doc.as<JsonObject>();
  if (a.isNull()) return "";
  if (!(a["power"] | true)) return "t_power=0";
  String p = "t_power=1";
  if (a["mode"].is<int>()) {
    int mode = a["mode"].as<int>();
    if (mode != 4) { ac::cfg.autoOn = false; p += ",t_work_mode=" + String(mode); }
    else ac::cfg.autoOn = true;
  }
  if (a["tempC"].is<float>()) {
    float t = a["tempC"].as<float>();
    if (ac::cfg.autoOn) ac::cfg.setpoint = t;
    else p += ",t_temp=" + String(ac::fromC(t, ac::st.fahrenheit));
  }
  if (a["fan"].is<int>()) p += ",t_fan_speed=" + String(a["fan"].as<int>());
  for (const char *key : {"sleep", "eco", "dimmer"}) {
    if (!a[key].is<bool>()) continue;
    String k = String("t_") + key;
    p += "," + k + "=" + String(a[key].as<bool>() ? 1 : 0);
  }
  return p;
}

struct FadeJob {
  int idx = -1, start = 0, target = 0, previous = -1;
  uint32_t began = 0, duration = 0;
  String finalDps;
  bool powerOff = false;
};
static std::vector<FadeJob> fades;

static void cancelFade(int idx) {
  for (auto it = fades.begin(); it != fades.end();) {
    if (it->idx == idx) it = fades.erase(it); else ++it;
  }
}

static void runLights(RuleEntry &r) {
  int n = 0;
  for (const auto &action : r.lightAction.actions) {
    int idx = findLight(action.id);
    if (idx < 0) continue;
    Light &L = lights[idx];
    cancelFade(idx);
    if (r.fade < 10 || !L.bri.length() || (!L.known && action.turnsOff)) {
      enqueue(Cmd{idx, action.dps, false, action.turnsOff, !action.turnsOff});
      n++;
      continue;
    }
    JsonDocument doc;
    if (deserializeJson(doc, action.dps)) continue;
    bool on = doc[L.sw].is<bool>() ? doc[L.sw].as<bool>() : !action.turnsOff;
    if (!doc[L.bri].is<int>() && on) {
      enqueue(Cmd{idx, action.dps, false, false, true});
      n++;
      continue;
    }
    int target = on ? (doc[L.bri].is<int>() ? doc[L.bri].as<int>() : L.briMin) : L.briMin;
    int initial = L.on ? L.briMin + (L.pct - 1) * (L.briMax - L.briMin) / 99 : L.briMin;
    if (!L.on && on) {
      doc[L.sw] = true;
      doc[L.bri] = initial;
      String startDps;
      serializeJson(doc, startDps);
      enqueue(Cmd{idx, startDps, false, false, true});
    }
    fades.push_back(FadeJob{idx, initial, target, -1, millis(), (uint32_t)r.fade * 1000UL, action.dps, !on});
    n++;
  }
  logEvent("Automation " + r.name + ": " + String(n) + " light(s)" + (r.fade > 0 ? " (fade)" : ""));
}

static void fadeTick() {
  uint32_t now = millis();
  for (auto it = fades.begin(); it != fades.end();) {
    FadeJob &f = *it;
    if (f.idx < 0 || f.idx >= (int)lights.size()) { it = fades.erase(it); continue; }
    Light &L = lights[f.idx];
    uint32_t elapsed = now - f.began;
    bool done = elapsed >= f.duration;
    int step = done ? 20 : (int)((uint64_t)elapsed * 20 / f.duration);
    if (step == f.previous) { ++it; continue; }
    f.previous = step;
    if (done) {
      enqueue(Cmd{f.idx, f.finalDps, false, f.powerOff, !f.powerOff});
      it = fades.erase(it);
      continue;
    }
    int value = f.start + (f.target - f.start) * step / 20;
    JsonDocument d;
    d[L.bri] = constrain(value, L.briMin, L.briMax);
    String raw;
    serializeJson(d, raw);
    enqueue(Cmd{f.idx, raw, false, false, false});
    ++it;
  }
}

static void run(RuleEntry &r) {
  if (r.isAC) {
    String p = acProps(r);
    if (p.length() && ac::cfg.configured) {
      ac::enqueueProps(p);
      if (ac::cfg.autoOn) ac::enqueueAutoNow();
      logEvent("AC automation: " + r.name);
    }
  } else runLights(r);
  r.lastRunMs = millis();
}

static void tick() {
  static uint32_t lastTick = 0;
  if (millis() - lastTick < 1000) return;
  lastTick = millis();
  fadeTick();
  updateWeather();
  if (time(nullptr) < 1700000000) return;
  int minute = minutesNow();
  time_t local = time(nullptr) + utcOffset;
  int day = (int)(local / 86400);
  auto eval = [&](std::vector<RuleEntry> &rules) {
    for (auto &r : rules) {
      bool env = r.event == "cloudy" || r.event == "roomAbove" || r.event == "roomBelow" ||
                 r.event == "outsideAbove" || r.event == "outsideBelow";
      if (env) {
        bool ready = r.event == "cloudy"
            ? (weatherFresh() && cloudCover >= r.cloud)
            : tempTest(r.event, reading(r.event), r.threshold, r.lastState == 1);
        if (r.lastState == -1) { r.lastState = ready ? 1 : 0; continue; }
        if (!ready) { r.lastState = 0; continue; }
        if (r.lastState == 1) continue;
        r.lastState = 1;
        if (r.lastRunMs && millis() - r.lastRunMs < 30UL * 60UL * 1000UL) continue;
        if (conditions(r)) run(r);
        continue;
      }
      if (r.lastDay == day) continue;
      int eventMinute = r.event == "clock" ? r.at :
                        r.event == "sunset" ? sunMinute(false) :
                        r.event == "lastLight" ? sunMinute(true) : -1;
      if (eventMinute < 0) continue;
      eventMinute = (eventMinute + r.offset + 1440) % 1440;
      int lag = (minute - eventMinute + 1440) % 1440;
      if (lag > 2) continue;
      if (!conditions(r)) continue;
      String key = "rule" + String(tuya::crc32((const uint8_t *)r.id.c_str(), r.id.length()), HEX);
      key = key.substring(0, 15);
      if (prefs.getInt(key.c_str(), -1) == day) { r.lastDay = day; continue; }
      run(r);
      r.lastDay = day;
      prefs.putInt(key.c_str(), day);
    }
  };
  eval(lightRules);
  eval(acRules);
}

} // namespace sceneauto
