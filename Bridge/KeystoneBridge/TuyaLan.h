// Tuya LAN protocol 3.3 / 3.4 / 3.5 for ESP32, ported from the app's Swift version (itself from tinytuya).
// One short connection per operation: bulbs often allow a single client, so we never hold one open.
#pragma once
#include <Arduino.h>
#include <WiFi.h>
#include <vector>
#include <mbedtls/aes.h>
#include <mbedtls/md.h>
#include <mbedtls/gcm.h>
#include <esp_random.h>

namespace tuya {

typedef std::vector<uint8_t> Bytes;

static const uint32_t CMD_SESS_START = 0x03, CMD_SESS_RESP = 0x04, CMD_SESS_FINISH = 0x05;
static const uint32_t CMD_CONTROL = 0x07, CMD_STATUS = 0x08, CMD_HEARTBEAT = 0x09;
static const uint32_t CMD_DP_QUERY = 0x0a, CMD_CONTROL_NEW = 0x0d, CMD_DP_QUERY_NEW = 0x10;

static bool noHeader(uint32_t cmd) {
  return cmd == 0x0a || cmd == 0x10 || cmd == 0x12 || cmd == 0x09 || cmd == 0x03 || cmd == 0x04 || cmd == 0x05 || cmd == 0x40;
}

static void be32(Bytes &b, uint32_t v) {
  b.push_back((v >> 24) & 0xff); b.push_back((v >> 16) & 0xff); b.push_back((v >> 8) & 0xff); b.push_back(v & 0xff);
}
static uint32_t rd32(const Bytes &b, size_t i) {
  return ((uint32_t)b[i] << 24) | ((uint32_t)b[i + 1] << 16) | ((uint32_t)b[i + 2] << 8) | (uint32_t)b[i + 3];
}

static uint32_t crc32(const uint8_t *d, size_t n) {
  uint32_t c = 0xffffffff;
  for (size_t i = 0; i < n; i++) {
    c ^= d[i];
    for (int k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
  }
  return c ^ 0xffffffff;
}

static Bytes hmac256(const uint8_t *data, size_t n, const uint8_t *key, size_t klen) {
  Bytes out(32);
  mbedtls_md_hmac(mbedtls_md_info_from_type(MBEDTLS_MD_SHA256), key, klen, data, n, out.data());
  return out;
}

static Bytes ecb(bool enc, const Bytes &in, const uint8_t *key, bool pad) {
  Bytes data = in;
  if (enc && pad) {
    uint8_t p = 16 - (data.size() % 16);
    data.insert(data.end(), p, p);
  }
  if (data.empty() || data.size() % 16 != 0) return Bytes();
  Bytes out(data.size());
  mbedtls_aes_context ctx;
  mbedtls_aes_init(&ctx);
  if (enc) mbedtls_aes_setkey_enc(&ctx, key, 128); else mbedtls_aes_setkey_dec(&ctx, key, 128);
  for (size_t i = 0; i < data.size(); i += 16)
    mbedtls_aes_crypt_ecb(&ctx, enc ? MBEDTLS_AES_ENCRYPT : MBEDTLS_AES_DECRYPT, data.data() + i, out.data() + i);
  mbedtls_aes_free(&ctx);
  if (!enc && !out.empty()) {
    uint8_t last = out.back();
    if (last >= 1 && last <= 16 && last <= out.size()) out.resize(out.size() - last);
  }
  return out;
}

static bool gcmSeal(const Bytes &plain, const uint8_t *key, const uint8_t *iv, const uint8_t *aad, size_t aadLen, Bytes &ct, Bytes &tag) {
  ct.assign(plain.size(), 0);
  tag.assign(16, 0);
  mbedtls_gcm_context g;
  mbedtls_gcm_init(&g);
  int r = mbedtls_gcm_setkey(&g, MBEDTLS_CIPHER_ID_AES, key, 128);
  if (r == 0) r = mbedtls_gcm_crypt_and_tag(&g, MBEDTLS_GCM_ENCRYPT, plain.size(), iv, 12, aad, aadLen, plain.data(), ct.data(), 16, tag.data());
  mbedtls_gcm_free(&g);
  return r == 0;
}

static bool gcmOpen(const Bytes &ct, const uint8_t *tag, const uint8_t *key, const uint8_t *iv, const uint8_t *aad, size_t aadLen, Bytes &plain) {
  plain.assign(ct.size(), 0);
  mbedtls_gcm_context g;
  mbedtls_gcm_init(&g);
  int r = mbedtls_gcm_setkey(&g, MBEDTLS_CIPHER_ID_AES, key, 128);
  if (r == 0) r = mbedtls_gcm_auth_decrypt(&g, ct.size(), iv, 12, aad, aadLen, tag, 16, ct.data(), plain.data());
  mbedtls_gcm_free(&g);
  return r == 0;
}

struct Frame {
  uint32_t cmd = 0;
  Bytes payload;
  String text() const { return String((const char *)payload.data(), payload.size()); }
};

class Conn {
 public:
  String devId;
  float ver = 3.3;
  String lastError;

  bool open(const String &host, const String &id, const String &localKey, float version, uint32_t timeoutMs = 1500) {
    devId = id;
    ver = version;
    seq = 1;
    buf.clear();
    if (localKey.length() != 16) { lastError = "bad key length"; return false; }
    memcpy(realKey, localKey.c_str(), 16);
    memcpy(key, realKey, 16);
    if (!client.connect(host.c_str(), 6668, timeoutMs)) { lastError = "no answer on 6668"; return false; }
    client.setNoDelay(true);
    if (ver >= 3.4f && !negotiate()) { close(); return false; }
    return true;
  }

  void close() { client.stop(); }

  // Returns the dps JSON object text, e.g. {"20":true,"22":500}, or "" on failure.
  String query(const std::vector<String> &knownDPs) {
    String t = String((uint32_t)time(nullptr));
    if (ver >= 3.4f) {
      if (!send(CMD_DP_QUERY_NEW, "{}")) return "";
      return waitDps(1500);
    }
    String j = "{\"gwId\":\"" + devId + "\",\"devId\":\"" + devId + "\",\"uid\":\"" + devId + "\",\"t\":\"" + t + "\"}";
    if (!send(CMD_DP_QUERY, j)) return "";
    Frame f;
    if (!waitFrame(f, 1500, CMD_DP_QUERY)) return "";
    String txt = f.text();
    if (txt.indexOf("data unvalid") >= 0) {
      // "device22" firmware: ask through CONTROL_NEW with null values.
      String dps = "{";
      for (size_t i = 0; i < knownDPs.size(); i++) dps += (i ? ",\"" : "\"") + knownDPs[i] + "\":null";
      dps += "}";
      String q = "{\"devId\":\"" + devId + "\",\"uid\":\"" + devId + "\",\"t\":\"" + t + "\",\"dps\":" + dps + "}";
      if (!send(CMD_CONTROL_NEW, q)) return "";
      return waitDps(1500);
    }
    return extractDps(txt);
  }

  // dps: JSON object text. Returns the echoed dps if the device answered within the window ("" otherwise).
  bool set(const String &dps, String *echo = nullptr) {
    String t = String((uint32_t)time(nullptr));
    bool ok;
    if (ver >= 3.4f) ok = send(CMD_CONTROL_NEW, "{\"protocol\":5,\"t\":" + t + ",\"data\":{\"dps\":" + dps + "}}");
    else ok = send(CMD_CONTROL, "{\"devId\":\"" + devId + "\",\"uid\":\"" + devId + "\",\"t\":\"" + t + "\",\"dps\":" + dps + "}");
    if (!ok) return false;
    String e = waitDps(700);
    if (echo) *echo = e;
    return true;
  }

 private:
  WiFiClient client;
  uint8_t realKey[16];
  uint8_t key[16];
  uint32_t seq = 1;
  Bytes buf;

  Bytes versionTag() const {
    char v[4];
    snprintf(v, sizeof(v), "%.1f", ver);
    return Bytes(v, v + 3);
  }

  Bytes encode(uint32_t cmd, const Bytes &raw) {
    Bytes h3;
    if (!noHeader(cmd)) { h3 = versionTag(); h3.insert(h3.end(), 12, 0); }
    Bytes out;
    uint32_t s = seq++;
    if (ver >= 3.5f) {
      Bytes p = h3; p.insert(p.end(), raw.begin(), raw.end());
      Bytes header;
      be32(header, 0x00006699); header.push_back(0); header.push_back(0);
      be32(header, s); be32(header, cmd); be32(header, p.size() + 12 + 16);
      uint8_t iv[12];
      for (int i = 0; i < 12; i++) iv[i] = esp_random() & 0xff;
      Bytes ct, tag;
      gcmSeal(p, key, iv, header.data() + 4, header.size() - 4, ct, tag);
      out = header;
      out.insert(out.end(), iv, iv + 12);
      out.insert(out.end(), ct.begin(), ct.end());
      out.insert(out.end(), tag.begin(), tag.end());
      be32(out, 0x00009966);
      return out;
    }
    if (ver >= 3.4f) {
      Bytes p = h3; p.insert(p.end(), raw.begin(), raw.end());
      Bytes enc = ecb(true, p, key, true);
      be32(out, 0x000055AA); be32(out, s); be32(out, cmd); be32(out, enc.size() + 36);
      out.insert(out.end(), enc.begin(), enc.end());
      Bytes mac = hmac256(out.data(), out.size(), key, 16);
      out.insert(out.end(), mac.begin(), mac.end());
      be32(out, 0x0000AA55);
      return out;
    }
    Bytes body = h3;
    Bytes enc = ecb(true, raw, key, true);
    body.insert(body.end(), enc.begin(), enc.end());
    be32(out, 0x000055AA); be32(out, s); be32(out, cmd); be32(out, body.size() + 8);
    out.insert(out.end(), body.begin(), body.end());
    be32(out, crc32(out.data(), out.size()));
    be32(out, 0x0000AA55);
    return out;
  }

  bool sendRaw(const Bytes &b) {
    if (!client.connected()) { lastError = "connection closed"; return false; }
    size_t n = client.write(b.data(), b.size());
    if (n != b.size()) { lastError = "write failed"; return false; }
    return true;
  }

  bool send(uint32_t cmd, const String &json) {
    Bytes raw((const uint8_t *)json.c_str(), (const uint8_t *)json.c_str() + json.length());
    return sendRaw(encode(cmd, raw));
  }

  bool hasPrefix(const Bytes &b, const Bytes &p) const {
    return b.size() >= p.size() && memcmp(b.data(), p.data(), p.size()) == 0;
  }

  // Takes one complete frame off the front of buf. False if there isn't one yet.
  bool decodeOne(Frame &f) {
    while (buf.size() >= 4 && rd32(buf, 0) != 0x000055AA && rd32(buf, 0) != 0x00006699) buf.erase(buf.begin());
    if (buf.size() < 4) return false;
    Bytes tag = versionTag();
    if (rd32(buf, 0) == 0x000055AA) {
      if (buf.size() < 16) return false;
      uint32_t len = rd32(buf, 12);
      if (len > 8192) { buf.erase(buf.begin(), buf.begin() + 4); return false; }
      size_t total = 16 + len;
      if (buf.size() < total) return false;
      Bytes frame(buf.begin(), buf.begin() + total);
      buf.erase(buf.begin(), buf.begin() + total);
      size_t endLen = ver >= 3.4f ? 36 : 8;
      if (total < 16 + endLen) return false;
      Bytes body(frame.begin() + 16, frame.begin() + (total - endLen));
      if (body.size() >= 4 && body[0] == 0 && body[1] == 0 && body[2] == 0 && (ver < 3.4f || body.size() % 16 == 4))
        body.erase(body.begin(), body.begin() + 4);
      f.cmd = rd32(frame, 8);
      if (ver >= 3.4f) {
        Bytes plain = ecb(false, body, key, false);
        if (plain.empty() && !body.empty()) plain = body;
        if (hasPrefix(plain, tag)) plain.erase(plain.begin(), plain.begin() + min((size_t)15, plain.size()));
        f.payload = plain;
      } else {
        if (hasPrefix(body, tag)) body.erase(body.begin(), body.begin() + min((size_t)15, body.size()));
        if (!body.empty() && body[0] == '{') f.payload = body;
        else {
          Bytes plain = ecb(false, body, key, false);
          f.payload = plain.empty() ? body : plain;
        }
      }
      return true;
    }
    if (buf.size() < 18) return false;
    uint32_t len = rd32(buf, 14);
    if (len > 8192) { buf.erase(buf.begin(), buf.begin() + 4); return false; }
    size_t total = 18 + len + 4;
    if (buf.size() < total) return false;
    Bytes frame(buf.begin(), buf.begin() + total);
    buf.erase(buf.begin(), buf.begin() + total);
    if (total < 18 + 12 + 16 + 4) return false;
    Bytes ct(frame.begin() + 30, frame.begin() + (total - 20));
    Bytes plain;
    if (!gcmOpen(ct, frame.data() + (total - 20), key, frame.data() + 18, frame.data() + 4, 14, plain)) return false;
    if (plain.size() >= 4) plain.erase(plain.begin(), plain.begin() + 4);
    if (hasPrefix(plain, tag)) plain.erase(plain.begin(), plain.begin() + min((size_t)15, plain.size()));
    f.cmd = rd32(frame, 10);
    f.payload = plain;
    return true;
  }

  bool waitFrame(Frame &out, uint32_t timeoutMs, int wantCmd = -1) {
    uint32_t start = millis();
    while (millis() - start < timeoutMs) {
      while (client.available()) {
        uint8_t tmp[256];
        int n = client.read(tmp, sizeof(tmp));
        if (n > 0) buf.insert(buf.end(), tmp, tmp + n);
      }
      Frame f;
      while (decodeOne(f)) {
        if (wantCmd < 0 || (int)f.cmd == wantCmd) { out = f; return true; }
      }
      if (!client.connected() && !client.available()) { lastError = "closed by device"; return false; }
      delay(10);
    }
    lastError = "no reply";
    return false;
  }

  static String extractDps(const String &txt) {
    int k = txt.indexOf("\"dps\"");
    if (k < 0) return "";
    int s = txt.indexOf('{', k);
    if (s < 0) return "";
    int depth = 0;
    for (int i = s; i < (int)txt.length(); i++) {
      if (txt[i] == '{') depth++;
      else if (txt[i] == '}') { if (--depth == 0) return txt.substring(s, i + 1); }
    }
    return "";
  }

  String waitDps(uint32_t timeoutMs) {
    uint32_t start = millis();
    while (millis() - start < timeoutMs) {
      uint32_t used = millis() - start;
      if (used >= timeoutMs) break;
      Frame f;
      if (!waitFrame(f, timeoutMs - used)) return "";
      String d = extractDps(f.text());
      if (d.length()) return d;
      if (f.text().indexOf('{') >= 0 && (f.cmd == CMD_DP_QUERY_NEW || f.cmd == CMD_DP_QUERY)) return "{}";
    }
    return "";
  }

  bool negotiate() {
    uint8_t local[16];
    for (int i = 0; i < 16; i++) local[i] = esp_random() & 0xff;
    memcpy(key, realKey, 16);
    if (!sendRaw(encode(CMD_SESS_START, Bytes(local, local + 16)))) return false;
    Frame f;
    if (!waitFrame(f, 1500, CMD_SESS_RESP)) { lastError = "no handshake reply"; return false; }
    if (f.payload.size() < 48) { lastError = "short handshake"; return false; }
    Bytes remote(f.payload.begin(), f.payload.begin() + 16);
    Bytes expect = hmac256(local, 16, realKey, 16);
    if (memcmp(expect.data(), f.payload.data() + 16, 32) != 0) { lastError = "wrong key or version"; return false; }
    Bytes fin = hmac256(remote.data(), 16, realKey, 16);
    if (!sendRaw(encode(CMD_SESS_FINISH, fin))) return false;
    Bytes mixed(16);
    for (int i = 0; i < 16; i++) mixed[i] = local[i] ^ remote[i];
    if (ver >= 3.5f) {
      Bytes ct, tag;
      if (!gcmSeal(mixed, realKey, local, nullptr, 0, ct, tag)) { lastError = "gcm failed"; return false; }
      memcpy(key, ct.data(), 16);
    } else {
      Bytes k = ecb(true, mixed, realKey, false);
      if (k.size() < 16) { lastError = "ecb failed"; return false; }
      memcpy(key, k.data(), 16);
    }
    return true;
  }
};

}  // namespace tuya
