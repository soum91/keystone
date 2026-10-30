// Remote access without port forwarding: the bridge keeps an MQTT connection to a public broker and
// answers requests that apps publish there. Every message is AES-256-GCM encrypted with a key that only
// the bridge and paired apps have (handed out over the LAN), so the broker sees only noise, and a stale
// or replayed request is refused. A request is replayed against the bridge's own web API, so all the
// usual tokens and checks apply unchanged.
#pragma once
#include <PubSubClient.h>
#include <mbedtls/gcm.h>
#include <mbedtls/base64.h>

namespace relay {

static const char *BROKER = "broker.emqx.io";
static const int BROKER_PORT = 1883;
static const char *BROKER_WSS = "wss://broker.emqx.io:8084/mqtt";

static WiFiClient net;
static PubSubClient mq(net);
static bool on = true;
static String id;            // 16 hex, random per bridge
static uint8_t key[32];
static String keyHex;
static String tReq, tRes;
static SemaphoreHandle_t qlock;
static std::vector<String> inbox;
static std::vector<String> seen;   // recent request ids, against replays
static volatile bool connected = false;
static uint32_t lastTry = 0;
static String lastError;
static uint32_t served = 0;
static uint32_t heard = 0, badKey = 0, stale = 0, tooBig = 0;   // diagnostics for Keystone

static String hex(const uint8_t *b, size_t n) {
  String s;
  char t[3];
  for (size_t i = 0; i < n; i++) { snprintf(t, 3, "%02x", b[i]); s += t; }
  return s;
}

static void unhex(const String &h, uint8_t *out, size_t n) {
  for (size_t i = 0; i < n && 2 * i + 1 < h.length(); i++) out[i] = strtol(h.substring(2 * i, 2 * i + 2).c_str(), nullptr, 16);
}

static void makeIdentity() {
  uint8_t r[8];
  esp_fill_random(r, 8);
  id = hex(r, 8);
  esp_fill_random(key, 32);
  keyHex = hex(key, 32);
  prefs.putString("rl_id", id);
  prefs.putString("rl_key", keyHex);
}

static void topics() {
  tReq = "keystone/" + id + "/req";
  tRes = "keystone/" + id + "/res";
}

// base64(iv12 | ciphertext | tag16)
static String seal(const String &plain) {
  uint8_t iv[12];
  esp_fill_random(iv, 12);
  std::vector<uint8_t> buf(12 + plain.length() + 16);
  memcpy(buf.data(), iv, 12);
  mbedtls_gcm_context g;
  mbedtls_gcm_init(&g);
  mbedtls_gcm_setkey(&g, MBEDTLS_CIPHER_ID_AES, key, 256);
  mbedtls_gcm_crypt_and_tag(&g, MBEDTLS_GCM_ENCRYPT, plain.length(), iv, 12, nullptr, 0,
                            (const uint8_t *)plain.c_str(), buf.data() + 12, 16, buf.data() + 12 + plain.length());
  mbedtls_gcm_free(&g);
  size_t olen = 0;
  mbedtls_base64_encode(nullptr, 0, &olen, buf.data(), buf.size());
  std::vector<uint8_t> b64(olen + 1);
  mbedtls_base64_encode(b64.data(), b64.size(), &olen, buf.data(), buf.size());
  return String((const char *)b64.data()).substring(0, olen);
}

static bool open(const String &b64, String &plain) {
  size_t n = 0;
  mbedtls_base64_decode(nullptr, 0, &n, (const uint8_t *)b64.c_str(), b64.length());
  if (n < 29 || n > 12000) return false;
  std::vector<uint8_t> raw(n);
  if (mbedtls_base64_decode(raw.data(), n, &n, (const uint8_t *)b64.c_str(), b64.length())) return false;
  size_t clen = n - 28;
  std::vector<uint8_t> out(clen + 1, 0);
  mbedtls_gcm_context g;
  mbedtls_gcm_init(&g);
  mbedtls_gcm_setkey(&g, MBEDTLS_CIPHER_ID_AES, key, 256);
  int r = mbedtls_gcm_auth_decrypt(&g, clen, raw.data(), 12, nullptr, 0, raw.data() + 12 + clen, 16, raw.data() + 12, out.data());
  mbedtls_gcm_free(&g);
  if (r) return false;
  plain = String((const char *)out.data());
  return true;
}

static void onMessage(char *, byte *payload, unsigned int len) {
  if (len > 4000) return;
  String s;
  s.reserve(len);
  for (unsigned int i = 0; i < len; i++) s += (char)payload[i];
  xSemaphoreTake(qlock, portMAX_DELAY);
  if (inbox.size() < 6) inbox.push_back(s);
  xSemaphoreGive(qlock);
}

// Replays one request against the local web API.
static void handle(const String &sealed) {
  String plain;
  heard++;
  if (!open(sealed, plain)) { badKey++; lastError = "a request with the wrong key (phone has an old key?)"; return; }
  JsonDocument d;
  if (deserializeJson(d, plain)) return;
  String rid = d["i"] | "";
  long ts = d["t"] | 0L;
  long now = (long)time(nullptr);
  if (!rid.length() || (now > 1700000000 && labs(now - ts) > 300)) { stale++; lastError = "a request with the wrong time"; return; }
  for (auto &x : seen) if (x == rid) return;                                 // replay
  seen.push_back(rid);
  if (seen.size() > 40) seen.erase(seen.begin());

  String method = d["m"] | "GET", path = d["p"] | "/api/info", body = d["b"] | "";
  JsonDocument r;
  r["i"] = rid;
  if (!path.startsWith("/api/") || path.startsWith("/api/update")) {
    r["c"] = 403; r["b"] = "{\"error\":\"not over the relay\"}";
  } else if (path.startsWith("/api/info") || path.startsWith("/api/control")) {
    // Answered in place (no loopback through the web server, which could fail or be busy).
    relayTask = xTaskGetCurrentTaskHandle(); relayFlag = true; relayCode = 500; relayOut = "{\"error\":\"no answer\"}";
    relayTok = d["h"]["X-Device-Token"] | ""; relayBody = body;
    if (path.startsWith("/api/info")) handleInfo(); else control::handle();
    relayFlag = false;
    r["c"] = relayCode; r["b"] = relayOut;
    relayOut = ""; relayBody = "";
  } else {
    WiFiClient c;
    HTTPClient h;
    h.setConnectTimeout(3000);
    h.setTimeout(9000);
    int code = -1;
    if (path.startsWith("/api/info")) path += path.indexOf('?') < 0 ? "?lite=1" : "&lite=1";   // no logs over the relay
    if (h.begin(c, "http://" + WiFi.localIP().toString() + ":" + String(API_PORT) + path)) {
      for (JsonPair kv : d["h"].as<JsonObject>()) h.addHeader(kv.key().c_str(), kv.value().as<String>());
      if (method == "POST") { h.addHeader("Content-Type", "application/json"); code = h.POST(body); }
      else code = h.GET();
      r["c"] = code;
      r["b"] = code > 0 ? h.getString() : String("{\"error\":\"bridge busy\"}");
      h.end();
    } else {
      r["c"] = -1; r["b"] = "{\"error\":\"local call failed\"}";
    }
  }
  String out;
  serializeJson(r, out);
  String sealedOut = seal(out);
  size_t need = sealedOut.length() + tRes.length() + 16;
  bool grew = need > mq.getBufferSize() && mq.setBufferSize(need + 64);   // a big status: grow just for this reply
  if (mq.publish(tRes.c_str(), sealedOut.c_str())) { served++; if (lastError.startsWith("a reply")) lastError = ""; }
  else { tooBig++; lastError = "a reply too big to send (" + String(sealedOut.length()) + " bytes)"; }
  if (grew) mq.setBufferSize(5120);
}

// One pass, called from the worker (no task of its own: saves 10 KB of stack). The AC and camera calls run
// on the same task and drop the relay through relayLetGo when they need its memory. The broker keeps a
// persistent session (fixed client id, clean session off, QoS 1), so a request sent while the relay is
// reconnecting waits at the broker and arrives a moment later instead of being lost.
static void letGo() {
  if (mq.connected()) mq.disconnect();
  net.stop();
  if (relayHolding) { mq.setBufferSize(16); relayHolding = false; }   // hand the 5 KB buffer back
  connected = false;
}

static void poll() {
  if (!on || otaActive || safeMode || setupOnly || acNetBusy || WiFi.status() != WL_CONNECTED || millis() < 20000UL) {
    letGo();
    if (acNetBusy) lastTry = 0;   // reconnect as soon as the AC call is done
    return;
  }
  if (!mq.connected()) {
    connected = false;
    if (lastTry && millis() - lastTry < 10000UL) return;
    lastTry = millis();
    if (ESP.getMaxAllocHeap() < 12000) { lastError = "low memory"; return; }
    String cid = "ks-" + id;   // fixed, so the broker keeps this bridge's session and queued requests
    if (!relayHolding) { if (!mq.setBufferSize(5120)) { lastError = "low memory"; return; } relayHolding = true; }
    if (mq.connect(cid.c_str(), nullptr, nullptr, nullptr, 0, false, nullptr, false)) {
      connected = true;
      lastError = mq.subscribe(tReq.c_str(), 1) ? "" : "couldn't subscribe to its channel";
    } else {
      lastError = "broker state " + String(mq.state());
    }
    return;
  }
  mq.loop();
  String job;
  xSemaphoreTake(qlock, portMAX_DELAY);
  if (!inbox.empty()) { job = inbox.front(); inbox.erase(inbox.begin()); }
  xSemaphoreGive(qlock);
  if (job.length()) handle(job);
}

static void begin() {
  qlock = xSemaphoreCreateMutex();
  on = prefs.getBool("rl_on", true);
  id = prefs.getString("rl_id", "");
  keyHex = prefs.getString("rl_key", "");
  if (id.length() != 16 || keyHex.length() != 64) makeIdentity();
  else unhex(keyHex, key, 32);
  topics();
  mq.setServer(BROKER, BROKER_PORT);
  mq.setCallback(onMessage);
  mq.setBufferSize(16);   // the real buffer is taken when connecting
  relayLetGo = [] { letGo(); lastTry = 0; };
  mq.setKeepAlive(45);
  mq.setSocketTimeout(4);
}

// GET: the relay details for a paired app (only over the LAN, it's the key). POST {"on":bool} / {"rotate":true}.
static void handleApi() {
  bool ok = screen::adminOK() || (barToken.length() && server.header("X-Subwave-Token") == barToken);
  String t = server.header("X-Device-Token");
  for (const char *app : {"exhale", "redshift", "equinox"}) if (!ok && t.length() && devToken(app) == t) ok = true;
  if (!ok) {
    server.send(401, "application/json", "{\"error\":\"unauthorized\"}");
    return;
  }
  // Never hand the key out through the relay itself.
  if (server.client().remoteIP() == WiFi.localIP()) { server.send(403, "application/json", "{\"error\":\"LAN only\"}"); return; }
  if (server.method() == HTTP_POST) {
    JsonDocument d;
    deserializeJson(d, server.arg("plain"));
    if (!d["on"].isNull()) { on = d["on"]; prefs.putBool("rl_on", on); }
    if (d["rotate"] | false) { makeIdentity(); topics(); if (mq.connected()) mq.disconnect(); lastTry = 0; }
  }
  JsonDocument r;
  r["on"] = on; r["connected"] = (bool)connected;
  r["broker"] = BROKER_WSS; r["id"] = id; r["key"] = keyHex;
  String out;
  serializeJson(r, out);
  server.send(200, "application/json", out);
}

static void info(JsonDocument &d) {
  JsonObject o = d["remote"].to<JsonObject>();
  o["on"] = on;
  o["connected"] = (bool)connected;
  o["served"] = served;
  o["heard"] = heard; o["badKey"] = badKey; o["stale"] = stale; o["tooBig"] = tooBig;
  o["id"] = id;   // not secret (the key is): lets a phone notice the bridge was reset and fetch the new key
  if (lastError.length()) o["error"] = lastError;
}

}  // namespace relay
