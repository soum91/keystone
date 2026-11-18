// Uses what TuyaDiscover.h hears (in a header so the Arduino builder's generated prototypes don't
// reference tuyadisc before it exists).
#pragma once

// A Tuya device announced itself at a new address: point whatever uses it there. Fixes lights, the
// purifier, the IR blaster and the strip after the router hands out new addresses, with no scanning.
static void applySeen(const tuyadisc::Seen &s) {
  float v = s.ver.length() ? s.ver.toFloat() : 0;
  bool used = false;
  xSemaphoreTake(stateLock, portMAX_DELAY);
  for (auto &L : lights) if (L.id == s.id && L.ip != s.ip) { L.ip = s.ip; if (v >= 3.1f) L.ver = v; L.fails = 0; used = true; }
  xSemaphoreGive(stateLock);
  if (pur.id == s.id && pur.ip != s.ip) { pur.ip = s.ip; if (v >= 3.1f) pur.ver = v; used = true; }
  if (ir.id == s.id && ir.ip != s.ip) { ir.ip = s.ip; if (v >= 3.1f) ir.ver = v; used = true; }
  if (strip::lock && strip::cfg.id == s.id && strip::cfg.ip != s.ip) {
    xSemaphoreTake(strip::lock, portMAX_DELAY);
    strip::cfg.ip = s.ip;
    if (v >= 3.1f) strip::cfg.ver = v;
    xSemaphoreGive(strip::lock);
    strip::save();
    strip::scan.on = false;
    used = true;
  }
  if (used) logEvent("Found " + s.id.substring(0, 6) + "… at " + s.ip + " (it announced itself)");
}

static void handleTuyaSeen() {
  if (!screen::adminOK()) { respond(401, "{\"error\":\"unauthorized\"}"); return; }
  JsonDocument d;
  tuyadisc::info(d.to<JsonObject>());
  String out;
  serializeJson(d, out);
  respond(200, out);
}

