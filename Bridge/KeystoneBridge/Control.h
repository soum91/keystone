// Direct control of everything on the bridge for Keystone (works over the LAN and the remote relay).
// Each command goes through the same queues the Apple Home tiles use, so the bridge, Home and the
// devices stay in step; Home catches up from the next poll.
//
// POST /api/control  {"device": ..., ...}
//   light     {"idx":0, "on":true, "bri":1-100}
//   tv        {"on":true} | {"input":0} | {"vol":"up"|"down"}
//   bar       {"on":true}
//   purifier  {"on":true, "auto":true, "speed":1-n}
//   ir        {"remote":0, "button":-1 (power) | 0-7}
//   router    {"call":"status","args":{}} (see Router.h)
//   ac        {"on":true, "mode":"cool"|"heat"|"fan"|"dry"|"smart", "target":23.5 (°C), "fan":"low"|"med"|"high"|"auto"}
#pragma once

namespace control {

static bool anyAppOK() {
  if (screen::adminOK()) return true;
  String t = reqHeader("X-Device-Token");
  for (const char *app : {"exhale", "redshift", "equinox"}) if (t.length() && devToken(app) == t) return true;
  return barToken.length() && reqHeader("X-Subwave-Token") == barToken;
}

static void reply(int code, const String &err = "") {
  respond(code, err.length() ? "{\"error\":\"" + err + "\"}" : String("{\"ok\":true}"));
}

static void light(JsonDocument &d) {
  int i = d["idx"] | -1;
  if (i < 0 || i >= (int)lights.size()) return reply(400, "no such light");
  Light &L = lights[i];
  JsonDocument dps;
  bool hasOn = !d["on"].isNull(), on = d["on"] | false;
  int pct = d["bri"] | -1;
  xSemaphoreTake(stateLock, portMAX_DELAY);
  bool wasOn = L.on, colour = L.colourMode;
  float h = L.hue, s = L.sat;
  xSemaphoreGive(stateLock);
  if (hasOn && L.sw.length()) dps[L.sw] = on;
  if (pct > 0) {
    pct = constrain(pct, 1, 100);
    float v = pct / 100.0f;
    if (colour && L.col.length()) dps[L.col] = colourHex(L, h, s / 100.0f, v);
    else if (L.bri.length()) dps[L.bri] = L.briMin + (int)((L.briMax - L.briMin) * v);
    if (!hasOn && !wasOn && L.sw.length()) { dps[L.sw] = true; hasOn = true; on = true; }
  }
  if (dps.size() == 0) return reply(400, "nothing to do");
  xSemaphoreTake(stateLock, portMAX_DELAY);
  if (hasOn) L.on = on;
  if (pct > 0) L.pct = pct;
  L.lastSent = millis();
  xSemaphoreGive(stateLock);
  String body;
  serializeJson(dps, body);
  bool changed = hasOn && on != wasOn;
  enqueue(Cmd{i, body, true, changed && !on, changed && on});
  reply(200);
}

static void tv(JsonDocument &d) {
  if (!d["on"].isNull()) xenqueue(XCmd{2, "", (d["on"] | false) ? 1 : 0}, true);
  else if (!d["input"].isNull()) {
    int i = d["input"] | -1;
    if (i < 0 || i >= (int)tvInputs.size()) return reply(400, "no such input");
    xenqueue(XCmd{4, tvInputs[i].uri}, true);
    tvActiveInput = i;
  } else if (!d["vol"].isNull()) {
    String v = d["vol"] | "";
    xenqueue(XCmd{3, v == "down" ? ircc(1, 19, false) : ircc(1, 18, false)});
  } else return reply(400, "nothing to do");
  reply(200);
}

static void purifier(JsonDocument &d) {
  if (!pur.configured) return reply(400, "no purifier");
  String s = "{";
  auto add = [&](const String &k, const String &v) { if (k.length()) s += (s.length() > 1 ? ",\"" : "\"") + k + "\":" + v; };
  if (!d["on"].isNull()) { bool on = d["on"]; add(pur.sw, on ? "true" : "false"); ps.on = on; }
  if (!d["auto"].isNull() && pur.mode.length()) {
    bool a = d["auto"];
    add(pur.mode, "\"" + (a ? pur.modeAuto : pur.modeManual) + "\"");
    ps.autoMode = a;
  }
  int sp = d["speed"] | 0;
  if (sp > 0 && pur.fan.length() && !pur.fanVals.empty()) {
    int idx = constrain(sp - 1, 0, (int)pur.fanVals.size() - 1);
    if (d["on"].isNull() && !ps.on) { add(pur.sw, "true"); ps.on = true; }
    if (d["auto"].isNull() && ps.autoMode && pur.modeManual.length()) { add(pur.mode, "\"" + pur.modeManual + "\""); ps.autoMode = false; }
    add(pur.fan, pur.fanVals[idx]);
    ps.fanIdx = idx;
  }
  s += "}";
  if (s.length() <= 2) return reply(400, "nothing to do");
  ps.lastSent = millis();
  xenqueue(XCmd{0, s});
  reply(200);
}

static void irPress(JsonDocument &d) {
  int r = d["remote"] | -1, b = d["button"] | -1;
  if (r < 0 || r >= (int)ir.remotes.size()) return reply(400, "no such remote");
  if (b < 0) {
    if (!ir.remotes[r].power.length()) return reply(400, "no power button");
    xenqueue(XCmd{1, ir.remotes[r].power});
  } else {
    if (b >= (int)ir.remotes[r].buttons.size()) return reply(400, "no such button");
    xenqueue(XCmd{1, ir.remotes[r].buttons[b].dps});
  }
  reply(200);
}

static void airco(JsonDocument &d) {
  using namespace ac;
  if (!cfg.configured) return reply(400, "no AC");
  String p;
  auto add = [&](const char *k, int v) { if (p.length()) p += ','; p += String(k) + "=" + String(v); };
  bool f = st.fahrenheit;
  bool smart = cfg.autoOn;
  if (!d["on"].isNull()) { bool on = d["on"]; add("t_power", on ? 1 : 0); st.on = on; if (!on) { cfg.autoOn = false; saveAuto(); smart = false; } }
  String mode = d["mode"] | "";
  float target = d["target"] | NAN;
  if (mode == "smart") {
    cfg.autoOn = true;
    smart = true;
    if (!isnan(target)) cfg.setpoint = target;
    saveAuto();
    if (!st.on) { add("t_power", 1); st.on = true; }
  } else if (mode.length()) {
    int m = mode == "fan" ? 0 : mode == "heat" ? 1 : mode == "dry" ? 3 : mode == "auto" ? 4 : 2;   // auto = the unit's own
    if (m == 1 && !cfg.heatSupported) return reply(400, "this AC can't heat");
    cfg.autoOn = false;
    smart = false;
    saveAuto();
    add("t_work_mode", m);
    st.mode = m;
    if (!st.on && d["on"].isNull()) { add("t_power", 1); st.on = true; }
  }
  if (!isnan(target) && mode != "smart") {
    if (smart) { cfg.setpoint = target; saveAuto(); }
    else { int t = fromC(target, f); add("t_temp", t); st.target = t; }
  }
  float band = d["band"] | NAN;   // Auto: how far past the target before it switches between cooling and heating
  if (!isnan(band)) { cfg.band = constrain(band, 0.5f, 6.0f); saveAuto(); }
  String fan = d["fan"] | "";
  if (fan.length()) add("t_fan_speed", fan == "low" ? 2 : fan == "med" ? 3 : fan == "high" ? 4 : 0);
  homeSetAt = 0;   // let the tile pick the new state up from the next poll
  if (p.length()) enqueueProps(p);
  if (smart) enqueueAutoNow();
  if (!p.length() && !smart && isnan(band)) return reply(400, "nothing to do");
  reply(200);
}

static void handle() {
  if (!anyAppOK()) return reply(401, "unauthorized");
  JsonDocument d;
  if (deserializeJson(d, reqBody())) return reply(400, "bad json");
  String dev = d["device"] | "";
  if (dev == "light") return light(d);
  if (dev == "tv") return tv(d);
  if (dev == "bar") {
    bool on = d["on"] | false;
    String via = barPower(on, false);
    barEvent(String("Keystone ") + (on ? "on" : "off") + ": " + via);
    return reply(200);
  }
  if (dev == "purifier") return purifier(d);
  if (dev == "ir") return irPress(d);
  if (dev == "ac") return airco(d);
  if (dev == "router") {
    if (!screen::adminOK()) return reply(401, "unauthorized");   // Keystone only
    return router::control(d);
  }
  reply(400, "unknown device");
}

}  // namespace control
