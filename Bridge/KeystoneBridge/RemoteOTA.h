// Keystone internet OTA: encrypted relay command; verified HTTPS firmware fetch.
// No arbitrary download URLs, direct MQTT firmware payloads, or NVS erase.
#pragma once
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <HTTPUpdate.h>

namespace remoteota {
static const char *IMAGE_URL = "https://soum91.github.io/keystone/fw/KeystoneBridge-esp32-app.bin";
static const char *SHA_URL = "https://soum91.github.io/keystone/fw/KeystoneBridge-esp32-app.bin.sha256";
static const char *BUILD_URL = "https://soum91.github.io/keystone/fw/build.txt";

static uint32_t target = 0, requestedAt = 0;
static uint8_t tries = 0;
static bool restartAfterAck = false, maintenanceBoot = false;
static String state = "idle", lastError = "";

static void begin() {
  target = prefs.getUInt("roTarget", 0);
  tries = prefs.getUChar("roTries", 0);
  state = prefs.getString("roState", "idle");
  lastError = prefs.getString("roError", "");
  // A local firmware upload can skip the remote updater altogether.
  // Don't display an old HTTPS failure forever after a NEW build is installed.
  uint32_t lastBootBuild = prefs.getUInt("roSeenBuild", 0);
  prefs.putUInt("roSeenBuild", FW_BUILD);
  if (!target && lastBootBuild && lastBootBuild != FW_BUILD) {
    state = "idle"; lastError = ""; tries = 0;
    prefs.putString("roState", state);
    prefs.remove("roError"); prefs.remove("roTries");
  }
  if (target && target <= FW_BUILD) {
    prefs.remove("roTarget"); prefs.remove("roTries");
    target = 0; tries = 0; state = "installed"; lastError = "";
    prefs.putString("roState", state); prefs.remove("roError");
  }
  maintenanceBoot = target > FW_BUILD;
}
static void fail(const String &why) {
  lastError = why; state = "failed"; target = 0;
  restartAfterAck = false; maintenanceBoot = false;
  prefs.remove("roTarget"); prefs.remove("roTries");
  prefs.putString("roState", state); prefs.putString("roError", why);
  otaActive = false;
  logEvent("Internet OTA: " + why);
}
static void info(JsonDocument &d) {
  JsonObject o = d["remoteOta"].to<JsonObject>();
  o["supported"] = true; o["state"] = state; o["targetBuild"] = target;
  o["installedBuild"] = FW_BUILD; o["attempt"] = tries;
  if (lastError.length()) o["error"] = lastError;
}

// Only the already-authenticated AES-GCM relay dispatcher can call this.
static void handle() {
  if (!viaRelay || !devTokenOK("keystone", reqHeader("X-Device-Token"))) {
    respond(401, "{\"error\":\"Only a paired Keystone phone can request internet OTA\"}");
    return;
  }
  if (!reqPost()) {
    JsonDocument d; info(d);
    String out; serializeJson(d, out); respond(200, out);
    return;
  }
  if (maintenanceBoot || restartAfterAck || otaActive) {
    respond(409, "{\"error\":\"An internet OTA update is already queued\"}"); return;
  }
  JsonDocument body;
  if (deserializeJson(body, reqBody())) {
    respond(400, "{\"error\":\"Invalid update request\"}"); return;
  }
  int n = body["build"] | 0;
  if (n <= FW_BUILD || n > 999999) {
    respond(400, "{\"error\":\"Build must be newer than installed version\"}"); return;
  }
  // The actual URL, build metadata and checksum are all fixed on the ESP32.
  target = (uint32_t)n;
  tries = 0;
  prefs.putUInt("roTarget", target); prefs.putUChar("roTries", tries);
  prefs.putString("roState", "queued"); prefs.remove("roError");
  lastError = ""; state = "queued";
  requestedAt = millis(); restartAfterAck = true;
  respond(200, "{\"ok\":true,\"queued\":true}");
}

static void download() {
  if (WiFi.status() != WL_CONNECTED) return;
  maintenanceBoot = false;
  otaActive = true;
  stopBluetoothForOta();
  if (relayLetGo) relayLetGo();
  if (otaStarting) otaStarting();
  prefs.putUChar("roTries", ++tries);
  if (tries > 2) {
    fail("Too many failed update attempts"); return;
  }
  if (ESP.getFreeHeap() < 65000 || ESP.getMaxAllocHeap() < 33000) {
    fail("Not enough internal memory to start verified HTTPS"); return;
  }
  for (int i = 0; i < 80 && time(nullptr) < 1700000000; ++i) delay(250);
  if (time(nullptr) < 1700000000) {
    fail("Clock not ready for HTTPS certificate validation"); return;
  }

  // Always verify the server's build matches the phone-approved build.
  int onlineBuild = 0;
  {
    WiFiClientSecure client;
    client.useBuiltinCACertBundle();
    HTTPClient http;
    http.setTimeout(12000);
    if (!http.begin(client, BUILD_URL)) {
      fail("Couldn't start HTTPS build lookup"); return;
    }
    int code = http.GET();
    if (code == HTTP_CODE_OK) {
      String b = http.getString(); b.trim();
      if (b.length() && b.length() < 12) onlineBuild = b.toInt();
    }
    http.end();
  }
  if (onlineBuild != (int)target || onlineBuild <= FW_BUILD) {
    fail("Online build differs from approved build, or HTTPS is unavailable");
    return;
  }

  state = "downloading"; prefs.putString("roState", state);
  logEvent("Internet OTA: fetching verified build " + String(target));
  WiFiClientSecure client;
  client.useBuiltinCACertBundle();
  HTTPUpdate updater;
  updater.rebootOnUpdate(false);
  updater.setSHA256sumUrl(SHA_URL);  // reject absent/bad SHA-256
  updater.setFollowRedirects(HTTPC_DISABLE_FOLLOW_REDIRECTS);
  HTTPUpdateResult result = updater.update(client, IMAGE_URL);
  if (result != HTTP_UPDATE_OK) {
    // HTTPUpdate can return FAILED without populating an error string. Keep the
    // numeric code and heap diagnostics so a low-memory/TLS problem is visible
    // through Keystone after the bridge returns to normal operation.
    String detail = updater.getLastErrorString();
    const int code = updater.getLastError();
    if (!detail.length()) detail = "no detail from HTTPUpdate";
    fail(result == HTTP_UPDATE_NO_UPDATES ? "No new firmware available" :
         "Verified HTTPS update failed (" + String(code) + "): " + detail +
         "; heap " + String(ESP.getFreeHeap()) +
         ", largest " + String(ESP.getMaxAllocHeap()));
    return;
  }
  prefs.putString("roState", "installed");
  prefs.remove("roError"); prefs.remove("roTarget"); prefs.remove("roTries");
  logEvent("Internet OTA verified; starting new firmware");
  delay(200);
  ESP.restart();
}

// Dedicated reduced-memory boot for queued OTA. Called from setup() immediately
// after Preferences and the log mutex initialize, BEFORE parsing device configs,
// constructing the HomeSpan accessory tree, or starting the large network worker.
// HomeSpan 2.1.8 persists WIFI/WIFIDATA as char ssid[33], pwd[65]. Read only;
// never update/erase NVS, HomeKit pairing, saved accessories, or relay credentials.
static void earlyBoot() {
  if (!maintenanceBoot) return;
  Serial.println("[keystone] Internet OTA: isolated Wi-Fi-only maintenance boot");
  state = "connecting"; prefs.putString("roState", state);

  struct SavedWifi { char ssid[33]; char pwd[65]; } credentials = {};
  nvs_handle_t wifi = 0;
  size_t size = sizeof(credentials);
  esp_err_t err = nvs_open("WIFI", NVS_READONLY, &wifi);
  if (err == ESP_OK) {
    err = nvs_get_blob(wifi, "WIFIDATA", &credentials, &size);
    nvs_close(wifi);
  }
  credentials.ssid[32] = 0;
  credentials.pwd[64] = 0;
  if (err != ESP_OK || size != sizeof(credentials) || !credentials.ssid[0]) {
    fail("Isolated OTA: saved HomeSpan Wi-Fi credentials unavailable");
    delay(150); ESP.restart();
    return;
  }

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.begin(credentials.ssid, credentials.pwd);
  // Do not retain a second copy of the password after Wi-Fi is configured.
  memset(&credentials, 0, sizeof(credentials));

  uint32_t started = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - started < 60000UL) {
    delay(250);
  }
  if (WiFi.status() != WL_CONNECTED) {
    fail("Isolated OTA: couldn't reconnect to saved Wi-Fi within 60 seconds");
    delay(150); ESP.restart();
    return;
  }
  configTime(0, 0, "pool.ntp.org", "time.google.com");
  Serial.printf("[keystone] Isolated OTA: heap=%lu, largest=%lu\n",
                (unsigned long)ESP.getFreeHeap(),
                (unsigned long)ESP.getMaxAllocHeap());

  // Validated build URL and SHA-256 verification are unchanged. Successful
  // update restarts into normal HomeSpan; failed update records the real error
  // and restarts normally instead of getting stuck in maintenance mode.
  download();
  delay(200);
  ESP.restart();
}

// Reply to the phone BEFORE rebooting into a low-memory-pressure update boot.
static bool poll() {
  if (restartAfterAck) {
    if (millis() - requestedAt > 3000) {
      Serial.println("[keystone] restarting into internet OTA mode");
      delay(100); ESP.restart();
    }
    return false;
  }
  if (!maintenanceBoot) return false;
  if (WiFi.status() == WL_CONNECTED) download();
  return true;  // cloud, BLE, relay operations are paused in maintenance mode
}
} // namespace remoteota
