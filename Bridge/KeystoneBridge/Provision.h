// First-time Wi-Fi setup, replacing HomeSpan's built-in access point (which iPhones often refused to
// get an address from, or kept dropping). Two ways in, both active at once:
//   1. Phone: join the open "Keystone-Setup" network; the setup page pops up (captive portal).
//   2. Computer: the web installer's "Connect to Wi-Fi" (Improv Serial over USB).
// Bluetooth scanning is stopped so the radio belongs to the access point. The bridge checks the
// password by actually joining before it saves anything, then restarts onto your network.
#pragma once
#include <DNSServer.h>

namespace provision {

static const char *AP_NAME = "Keystone-Setup";
static volatile bool active = false;

struct Net { String ssid; int rssi; bool open; };
static std::vector<Net> nets;

static void scan() {
  nets.clear();
  int n = WiFi.scanNetworks(false, false, false, 300);
  for (int i = 0; i < n; i++) {
    String s = WiFi.SSID(i);
    if (!s.length()) continue;
    bool dup = false;
    for (auto &x : nets) if (x.ssid == s) { dup = true; x.rssi = max(x.rssi, (int)WiFi.RSSI(i)); }
    if (!dup) nets.push_back({s, WiFi.RSSI(i), WiFi.encryptionType(i) == WIFI_AUTH_OPEN});
  }
  std::sort(nets.begin(), nets.end(), [](const Net &a, const Net &b) { return a.rssi > b.rssi; });
  WiFi.scanDelete();
}

// Joins to prove the password works. Keeps the access point up meanwhile.
static bool tryJoin(const String &ssid, const String &pass) {
  status = "Joining " + ssid + "...";
  WiFi.begin(ssid.c_str(), pass.c_str());
  uint32_t t = millis();
  while (millis() - t < 20000) {
    if (WiFi.status() == WL_CONNECTED) return true;
    if (millis() - t > 4000 && (WiFi.status() == WL_CONNECT_FAILED || WiFi.status() == WL_NO_SSID_AVAIL)) break;
    delay(200);
  }
  WiFi.disconnect(false, false);
  status = "Couldn't join " + ssid + ". Wrong password?";
  return false;
}

static void save(const String &ssid, const String &pass, const String &code) {
  homeSpan.setWifiCredentials(ssid.c_str(), pass.c_str());
  String c;
  for (char ch : code) if (isdigit(ch)) c += ch;
  if (c.length() == 8) homeSpan.setPairingCode(c.c_str(), false);
  status = "Connected! Restarting...";
}

static String esc(const String &s) {
  String o;
  for (char c : s) {
    if (c == '<') o += "&lt;"; else if (c == '>') o += "&gt;"; else if (c == '&') o += "&amp;"; else if (c == '"') o += "&quot;"; else o += c;
  }
  return o;
}

static String page() {
  String h = F("<!doctype html><html><head><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'>"
               "<title>Keystone Bridge setup</title><style>body{font:17px -apple-system,system-ui,sans-serif;background:#111;color:#eee;"
               "margin:0;padding:20px;max-width:480px}h1{font-size:24px}label{display:block;margin:16px 0 6px;color:#aaa;font-size:14px}"
               "select,input{width:100%;box-sizing:border-box;font-size:17px;padding:12px;border-radius:10px;border:1px solid #333;"
               "background:#1c1c1e;color:#eee}button{margin-top:22px;width:100%;padding:14px;font-size:17px;font-weight:600;border:0;"
               "border-radius:12px;background:#f5c542;color:#111}.s{margin-top:16px;color:#f5c542}.m{color:#888;font-size:13px}a{color:#f5c542}"
               "</style></head><body><h1>Keystone Bridge</h1><p class=m>Pick your 2.4 GHz Wi-Fi. 5 GHz networks won't work.</p>"
               "<form method=post action=/save><label>Wi-Fi network</label><select name=s>");
  for (auto &n : nets) h += "<option value=\"" + esc(n.ssid) + "\">" + esc(n.ssid) + (n.open ? " (open)" : "") + "</option>";
  h += F("<option value=''>Other (type below)…</option></select><label>…or type the name</label><input name=o autocapitalize=off autocorrect=off>"
         "<label>Password</label><input name=p type=password autocapitalize=off autocorrect=off>"
         "<label>Apple Home setup code (8 digits, optional)</label><input name=c inputmode=numeric placeholder='466-37-726'>"
         "<button>Connect</button></form><p class=m>After you tap Connect, watch the bridge's screen. It says Connected and restarts, "
         "or shows what went wrong: then rejoin Keystone-Setup and try again.</p><p><a href=/rescan>Scan again</a></p>");
  if (status.length()) h += "<p class=s>" + esc(status) + "</p>";
  h += F("</body></html>");
  return h;
}

static String pendSsid, pendPass, pendCode;
static bool pend = false, pendFromWeb = false;

// Improv Serial (Wi-Fi over USB from the web installer). Off: the firmware is out of flash room.
#ifdef KS_IMPROV
// ---- Improv Serial (https://www.improv-wifi.com/serial/) -----------------------------------------

static void improvSend(uint8_t type, const std::vector<uint8_t> &data) {
  std::vector<uint8_t> p = {'I', 'M', 'P', 'R', 'O', 'V', 1, type, (uint8_t)data.size()};
  p.insert(p.end(), data.begin(), data.end());
  uint8_t sum = 0;
  for (auto b : p) sum += b;
  p.push_back(sum);
  p.push_back('\n');
  Serial.write(p.data(), p.size());
  Serial.flush();
}

static void improvState(uint8_t s) { improvSend(0x01, {s}); }
static void improvError(uint8_t e) { improvSend(0x02, {e}); }

static void improvResult(uint8_t cmd, const std::vector<String> &strs) {
  std::vector<uint8_t> d = {cmd, 0};
  for (auto &s : strs) { d.push_back(s.length()); for (char c : s) d.push_back(c); }
  d[1] = d.size() - 2;
  improvSend(0x04, d);
}

static uint8_t ibuf[256];
static size_t ilen = 0;

static void improvHandle(uint8_t type, const uint8_t *d, uint8_t len) {
  if (type != 0x03 || len < 2) return;
  uint8_t cmd = d[0];
  if (cmd == 0x01) {   // send Wi-Fi settings
    uint8_t sl = d[2];
    String s((const char *)d + 3, sl);
    uint8_t pl = d[3 + sl];
    String p((const char *)d + 4 + sl, pl);
    pendSsid = s; pendPass = p; pendCode = ""; pendFromWeb = false; pend = true;
    improvState(0x03);   // provisioning
  } else if (cmd == 0x02) {
    improvState(0x02);   // authorized, ready
  } else if (cmd == 0x03) {
    improvResult(0x03, {"Keystone Bridge", FW_VERSION, ESP.getChipModel(), screen::bridgeName});
  } else if (cmd == 0x04) {
    scan();
    for (auto &n : nets) improvResult(0x04, {n.ssid, String(n.rssi), n.open ? "NO" : "YES"});
    improvResult(0x04, {});
  } else {
    improvError(0x02);   // unknown command
  }
}

static void improvPoll() {
  while (Serial.available()) {
    uint8_t b = Serial.read();
    if (ilen < 6) {   // hunt for "IMPROV"
      if (b == (uint8_t)"IMPROV"[ilen]) ibuf[ilen++] = b; else ilen = (b == 'I') ? (ibuf[0] = b, 1) : 0;
      continue;
    }
    ibuf[ilen++] = b;
    if (ilen >= 9) {
      size_t want = 9 + ibuf[8] + 1;
      if (ilen >= want || ilen >= sizeof(ibuf)) {
        uint8_t sum = 0;
        for (size_t i = 0; i < want - 1; i++) sum += ibuf[i];
        if (ilen >= want && sum == ibuf[want - 1]) improvHandle(ibuf[7], ibuf + 9, ibuf[8]);
        ilen = 0;
      }
    }
  }
}

#endif

// ---- The setup loop (runs instead of HomeSpan's access point; never returns) ----------------------

static void run() {
  active = true;
  if (!setupOnly) stopBluetoothForOta();
  WiFi.disconnect(false, false);
  WiFi.mode(WIFI_AP_STA);
  delay(100);
  scan();
  WiFi.softAP(AP_NAME, nullptr, 6, 0, 4);
  delay(200);
  WiFi.softAPConfig(IPAddress(192, 168, 4, 1), IPAddress(192, 168, 4, 1), IPAddress(255, 255, 255, 0));
  delay(300);
  DNSServer dns;
  dns.start(53, "*", IPAddress(192, 168, 4, 1));
  WebServer web(80);
  String doneSsid;
  uint32_t pendAt = 0;
  web.on("/save", HTTP_POST, [&]() {
    String s = web.arg("o").length() ? web.arg("o") : web.arg("s");
    s.trim();
    if (!s.length()) { status = "Pick or type a network."; web.sendHeader("Location", "/"); web.send(302); return; }
    // Answer first: joining moves the radio to your router's channel, which can drop this page.
    pendSsid = s; pendPass = web.arg("p"); pendCode = web.arg("c"); pendFromWeb = true; pend = true;
    status = "Joining " + s + "...";
    web.send(200, "text/html", page());
    pendAt = millis();
  });
  web.on("/rescan", [&]() { scan(); web.sendHeader("Location", "/"); web.send(302); });
  web.onNotFound([&]() { web.send(200, "text/html", page()); });   // every URL is the setup page (captive portal)
  web.begin();
  status = "";
#ifdef KS_IMPROV
  improvState(0x02);
#endif
  Serial.println("\n[keystone] Wi-Fi setup: join Keystone-Setup, or use the web installer's Connect to Wi-Fi.");

  for (;;) {
    dns.processNextRequest();
    web.handleClient();
#ifdef KS_IMPROV
    improvPoll();
#endif
    if (pend && (!pendFromWeb || millis() - pendAt > 1500)) {
      pend = false;
      if (tryJoin(pendSsid, pendPass)) {
        save(pendSsid, pendPass, pendCode);
#ifdef KS_IMPROV
        if (!pendFromWeb) {
          improvState(0x04);
          improvResult(0x01, {"http://" + WiFi.localIP().toString() + ":8080/api/info"});
        }
#endif
        doneSsid = pendSsid;
      }
    }
    if (doneSsid.length()) {
      uint32_t t = millis();
      while (millis() - t < 3000) { web.handleClient(); dns.processNextRequest(); delay(10); }
      ESP.restart();
    }
    delay(5);
  }
}

}  // namespace provision
