// The OpenWrt router (the ASUS), through the Switchyard plugin on it. The bridge signs in to the router's
// /ubus endpoint with the limited "switchyard" login Keystone set up, and passes Keystone's calls through,
// so the router can be run from anywhere over the relay.
//
// POST /api/control {"device":"router", "call":"status", "args":{...}}   -> the plugin's answer
//                   {"device":"router", "setup":{"host":"192.168.1.1","user":"switchyard","pass":"..."}}
//                   {"device":"router", "forget":true}
#pragma once

namespace router {

static String host, user, pass, sid;
static String lastError;
static bool followOn = false;      // router lights follow the bridge lights
static int8_t lastAny = -1;
static uint32_t nextFollow = 0;
static uint32_t lastOk = 0;

static bool configured() { return host.length() && user.length() && pass.length(); }

static void begin() {
  host = prefs.getString("rt_host", "");
  user = prefs.getString("rt_user", "");
  pass = prefs.getString("rt_pass", "");
  followOn = prefs.getBool("rt_follow", false);
}

// "setup" and "allow" need the root password and stay on the phone.
static bool allowed(const String &m) { return m.length() && m != "setup" && m != "allow"; }

static int post(const String &body, String &out, int timeoutMs) {
  WiFiClient c;
  HTTPClient h;
  h.setConnectTimeout(2500);
  h.setTimeout(timeoutMs);
  h.setReuse(false);
  workerBeat = millis();   // runs on the worker; a slow router isn't a hang
  if (!h.begin(c, "http://" + host + "/ubus")) { lastError = "bad router address"; return -1; }
  h.addHeader("Content-Type", "application/json");
  int code = h.POST(body);
  out = code > 0 ? h.getString() : String();
  h.end();
  workerBeat = millis();
  if (code <= 0) lastError = "router unreachable (" + String(code) + ")";
  else if (code != 200) lastError = "router said HTTP " + String(code);
  return code;
}

// uhttpd answers {"jsonrpc":"2.0","id":1,"result":[status,{...}]} or {"jsonrpc":"2.0","id":1,"error":{"code":..}}.
// Pull the status and the object out as text, so a big reply isn't parsed twice.
static int unwrap(const String &resp, String &obj) {
  obj = "";
  int r = resp.indexOf("\"result\"");
  if (r < 0) {
    int e = resp.indexOf("\"code\"");
    if (e < 0) return -99;
    int colon = resp.indexOf(':', e);
    return colon < 0 ? -99 : resp.substring(colon + 1).toInt();   // e.g. -32002 access denied
  }
  int open = resp.indexOf('[', r);
  if (open < 0) return -99;
  int i = open + 1;
  while (i < (int)resp.length() && resp[i] == ' ') i++;
  int status = resp.substring(i).toInt();
  int comma = resp.indexOf(',', i);
  int close = resp.lastIndexOf(']');
  if (comma > 0 && close > comma) {
    obj = resp.substring(comma + 1, close);
    obj.trim();
  }
  return status;
}

static bool login() {
  // user is "switchyard" and pass is hex from the router, so no JSON escaping is needed.
  String body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"call\",\"params\":[\"00000000000000000000000000000000\",\"session\",\"login\",{\"username\":\"" +
                user + "\",\"password\":\"" + pass + "\",\"timeout\":3600}]}";
  String resp, obj;
  if (post(body, resp, 6000) != 200) return false;
  int st = unwrap(resp, obj);
  if (st != 0) { lastError = st == 6 ? "router refused login: set it up again" : "router login failed (" + String(st) + ")"; return false; }
  int k = obj.indexOf("\"ubus_rpc_session\"");
  int q1 = k < 0 ? -1 : obj.indexOf('"', obj.indexOf(':', k) + 1);
  int q2 = q1 < 0 ? -1 : obj.indexOf('"', q1 + 1);
  sid = q2 > q1 ? obj.substring(q1 + 1, q2) : String();
  if (!sid.length()) lastError = "odd login answer";
  return sid.length() > 0;
}

// Runs switchyard.<method>. Returns the HTTP code to hand back and fills out with the JSON body.
static int call(const String &method, const String &args, String &out, int timeoutMs) {
  if (!configured()) { out = "{\"error\":\"router not set up\"}"; return 400; }
  for (int attempt = 0; attempt < 2; attempt++) {
    if (!sid.length() && !login()) break;
    String body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"call\",\"params\":[\"" + sid + "\",\"switchyard\",\"" + method + "\"," + args + "]}";
    String resp, obj;
    if (post(body, resp, timeoutMs) != 200) break;
    int st = unwrap(resp, obj);
    if (st == 0) {
      lastOk = millis();
      lastError = "";
      out = obj.length() ? obj : String("{}");
      return 200;
    }
    if (st == -32002 || st == 6) { sid = ""; continue; }   // session ran out: log in again once
    lastError = st == 3 || st == 4 || st == -32000 ? "plugin isn't on the router" : "router call failed (" + String(st) + ")";
    break;
  }
  String msg = lastError.length() ? lastError : String("router call failed");
  msg.replace("\\", "/");
  msg.replace("\"", "'");
  out = "{\"error\":\"" + msg + "\"}";
  return 502;
}

static void control(JsonDocument &d) {
  String out;
  if (d["forget"] | false) {
    host = user = pass = sid = "";
    prefs.remove("rt_host"); prefs.remove("rt_user"); prefs.remove("rt_pass");
    return respond(200, "{\"ok\":true}");
  }
  if (!d["follow"].isNull()) {
    followOn = d["follow"];
    prefs.putBool("rt_follow", followOn);
    lastAny = -1;
    return respond(200, "{\"ok\":true}");
  }
  if (d["setup"].is<JsonObject>()) {
    host = d["setup"]["host"] | "";
    user = d["setup"]["user"] | "";
    pass = d["setup"]["pass"] | "";
    host.trim();
    sid = "";
    prefs.putString("rt_host", host); prefs.putString("rt_user", user); prefs.putString("rt_pass", pass);
    int code = call("version", "{}", out, 6000);
    return respond(code, out);
  }
  String m = d["call"] | "";
  if (!allowed(m)) return respond(400, "{\"error\":\"not a router call\"}");
  String args = "{}";
  if (d["args"].is<JsonObject>()) { args = ""; serializeJson(d["args"], args); }
  int timeout = (m == "diag" || m == "scan") ? 15000 : m == "guest" ? 12000 : 8000;
  int code = call(m, args, out, timeout);
  respond(code, out);
}

static void info(JsonDocument &d) {
  JsonObject o = d["router"].to<JsonObject>();
  o["configured"] = configured();
  o["follow"] = followOn;
  if (!configured()) return;
  o["host"] = host;
  o["ok"] = lastOk > 0 && lastError.length() == 0;
  if (lastOk) o["ago"] = (int)((millis() - lastOk) / 1000);
  if (lastError.length()) o["error"] = lastError;
}

// Every bridge light off -> router lights off; any on -> on. Checked every 2 s from the worker.
static void follow() {
  if (!followOn || !configured() || (int32_t)(millis() - nextFollow) < 0) return;
  nextFollow = millis() + 2000;
  int any = 0, known = 0;
  xSemaphoreTake(stateLock, portMAX_DELAY);
  for (auto &L : lights) if (L.known) { known++; if (L.on) any = 1; }
  xSemaphoreGive(stateLock);
  if (!known || any == lastAny) return;
  if (lastAny >= 0) {
    String out;
    if (call("leds", any ? "{\"on\":true}" : "{\"on\":false}", out, 6000) != 200) { nextFollow = millis() + 60000; return; }
  }
  lastAny = any;
}

}  // namespace router
