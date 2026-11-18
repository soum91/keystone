// Tuya devices announce themselves on the Wi-Fi every few seconds (UDP 6666 plain, 6667 AES-ECB,
// 7000 AES-GCM for protocol 3.5), with their device id in "gwId". Listening gives every device's
// address by id, no scanning and no key needed. Layout and key follow tinytuya (udp_helper.py,
// message_helper.py): key = md5("yGAdlopoPVldABfn").
#pragma once
#include <WiFiUdp.h>

namespace tuyadisc {

struct Seen { String id, ip, ver; uint32_t at = 0; };
static std::vector<Seen> seen;
static WiFiUDP u6666, u6667, u7000;
static bool started = false;
static uint32_t packets = 0, decoded = 0;
static void (*onSeen)(const Seen &) = nullptr;

static const uint8_t KEY[16] = {0x6c, 0x1e, 0xc8, 0xe2, 0xbb, 0x9b, 0xb5, 0x9a, 0xb5, 0x0b, 0x0d, 0xaf, 0x64, 0x9b, 0x41, 0x0a};

static uint32_t be32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3]; }

static void note(const String &text, const String &ip) {
  int a = text.indexOf('{'), b = text.lastIndexOf('}');
  if (a < 0 || b <= a) return;
  JsonDocument d;
  if (deserializeJson(d, text.substring(a, b + 1))) return;
  if (String(d["from"] | "") == "app") return;   // another app asking, not a device
  String id = d["gwId"] | "";
  if (!id.length()) return;
  decoded++;
  String ver;
  if (d["version"].is<const char *>()) ver = d["version"].as<const char *>();
  else if (d["version"].is<float>()) ver = String(d["version"].as<float>(), 1);
  for (auto &s : seen) {
    if (s.id == id) {
      bool moved = s.ip != ip;
      s.ip = ip; s.at = millis(); if (ver.length()) s.ver = ver;
      if (moved && onSeen) onSeen(s);
      return;
    }
  }
  if (seen.size() >= 40) {   // forget the one heard longest ago
    size_t old = 0;
    for (size_t i = 1; i < seen.size(); i++) if (seen[i].at < seen[old].at) old = i;
    seen.erase(seen.begin() + old);
  }
  Seen s; s.id = id; s.ip = ip; s.ver = ver; s.at = millis();
  seen.push_back(s);
  if (onSeen) onSeen(s);
}

static void handle(const uint8_t *p, int n, const String &ip) {
  if (n < 24) return;
  uint32_t prefix = be32(p);
  if (prefix == 0x000055AA) {
    // prefix, seq, cmd, length | retcode | payload | crc, suffix
    uint32_t len = be32(p + 12);
    int end = min(n, (int)(16 + len));
    if (end - 8 <= 20) return;
    tuya::Bytes payload(p + 20, p + end - 8);
    if (!payload.empty() && payload[0] == '{') { note(String((const char *)payload.data(), payload.size()), ip); return; }
    tuya::Bytes plain = tuya::ecb(false, payload, KEY, true);
    if (!plain.empty()) note(String((const char *)plain.data(), plain.size()), ip);
  } else if (prefix == 0x00006699) {
    // prefix, unknown(2), seq, cmd, length (18 bytes) | iv(12) | ciphertext | tag(16) | suffix(4)
    if (n < 18 + 12 + 20) return;
    uint32_t len = be32(p + 14);
    int end = min(n, (int)(18 + len + 4));
    if (end - 18 < 12 + 20) return;
    const uint8_t *iv = p + 18;
    const uint8_t *tag = p + end - 20;
    tuya::Bytes ct(p + 30, p + end - 20);
    tuya::Bytes plain;
    if (tuya::gcmOpen(ct, tag, KEY, iv, p + 4, 14, plain)) note(String((const char *)plain.data(), plain.size()), ip);
  } else if (p[0] == '{') {
    note(String((const char *)p, n), ip);
  }
}

static void begin() {
  if (started) return;
  u6666.begin(6666); u6667.begin(6667); u7000.begin(7000);
  started = true;
}

static void poll() {
  if (!started) return;
  static uint8_t buf[700];
  WiFiUDP *socks[] = {&u6666, &u6667, &u7000};
  for (WiFiUDP *u : socks) {
    for (int guard = 0; guard < 4; guard++) {
      int n = u->parsePacket();
      if (n <= 0) break;
      packets++;
      if (n > (int)sizeof(buf)) { u->flush(); continue; }
      int r = u->read(buf, sizeof(buf));
      if (r > 0) handle(buf, r, u->remoteIP().toString());
    }
  }
}

static const Seen *find(const String &id) {
  for (auto &s : seen) if (s.id == id) return &s;
  return nullptr;
}

static void info(JsonObject o) {
  o["packets"] = packets; o["decoded"] = decoded;
  JsonArray a = o["devices"].to<JsonArray>();
  for (auto &s : seen) {
    JsonObject d = a.add<JsonObject>();
    d["id"] = s.id; d["ip"] = s.ip; if (s.ver.length()) d["ver"] = s.ver;
    d["ago"] = (int)((millis() - s.at) / 1000);
  }
}

}  // namespace tuyadisc
