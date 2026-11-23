// Keystone's isolated local firmware upload server.
// Only entered after a paired Keystone phone on the same LAN requests
// /api/admin {"action":"prepareUpdate"}. The request is explicitly refused
// over the MQTT relay. This boot skips HomeSpan, cameras, lights, Govee BLE,
// AC TLS, and the 24-KB worker stack, leaving maximum contiguous RAM for OTA.
// The one-shot boot flag is cleared before joining Wi-Fi; any error or timeout
// returns to normal operation without erasing Wi-Fi, HomeKit pairing or devices.
#pragma once

namespace localota {

static void earlyBoot() {
  if (!prefs.getBool("loReady", false)) return;
  prefs.remove("loReady");  // guarantee a one-shot maintenance boot

  Serial.println("[keystone] local firmware OTA: isolated upload-only boot");
  struct SavedWifi { char ssid[33]; char pwd[65]; } wifiData = {};
  nvs_handle_t handle = 0;
  size_t len = sizeof(wifiData);
  esp_err_t err = nvs_open("WIFI", NVS_READONLY, &handle);
  if (err == ESP_OK) {
    err = nvs_get_blob(handle, "WIFIDATA", &wifiData, &len);
    nvs_close(handle);
  }
  wifiData.ssid[32] = 0; wifiData.pwd[64] = 0;
  if (err != ESP_OK || len != sizeof(wifiData) || !wifiData.ssid[0]) {
    logEvent("Local OTA: saved Wi-Fi credentials unavailable, returning to normal boot");
    delay(150);
    ESP.restart();
    return;
  }

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.begin(wifiData.ssid, wifiData.pwd);
  memset(&wifiData, 0, sizeof(wifiData));
  uint32_t started = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - started < 60000UL) delay(250);
  if (WiFi.status() != WL_CONNECTED) {
    logEvent("Local OTA: couldn't reconnect to home Wi-Fi");
    delay(150);
    ESP.restart();
    return;
  }

  // Dedicated authenticated endpoints; do NOT expose regular control/pairing
  // routes while HomeKit has not started.
  const char *headers[] = {"X-Device-Token", "X-Afterglow-Token"};
  server.collectHeaders(headers, 2);
  server.on("/api/ota/local", HTTP_GET, []() {
    if (!devTokenOK("keystone", server.header("X-Device-Token"))) {
      server.send(401, "application/json", "{\"error\":\"unauthorized\"}");
      return;
    }
    String out = "{\"ready\":true,\"mode\":\"isolated\",\"freeHeap\":" +
                 String(ESP.getFreeHeap()) + ",\"largestBlock\":" +
                 String(ESP.getMaxAllocHeap()) + "}";
    server.send(200, "application/json", out);
  });
  server.on("/api/update", HTTP_POST, handleUpdateDone, handleUpdateUpload);
  server.onNotFound([]() { server.send(404, "application/json", "{\"error\":\"OTA mode only\"}"); });
  server.begin();

  Serial.printf("[keystone] isolated local upload at %s:%d; free=%lu, block=%lu\n",
                WiFi.localIP().toString().c_str(), API_PORT,
                (unsigned long)ESP.getFreeHeap(), (unsigned long)ESP.getMaxAllocHeap());

  uint32_t readyAt = millis();
  // A stuck or abandoned update must never strand the bridge in upload mode.
  // During an active upload the synchronous WebServer callback owns this task.
  while (millis() - readyAt < 300000UL) {
    server.handleClient();
    if (WiFi.status() != WL_CONNECTED && millis() - readyAt > 120000UL) break;
    delay(2);
  }
  Serial.println("[keystone] isolated local OTA timed out; normal restart");
  server.stop();
  delay(150);
  ESP.restart();
}
}  // namespace localota
