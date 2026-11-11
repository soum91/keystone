import Foundation
import CryptoKit

/// Smart Life "device sharing" cloud (the same one Home Assistant's Tuya integration uses), only to read the
/// power strip's ID, local key and outlet names so nobody has to type them. No Tuya developer account:
/// sign in once by scanning a QR in Smart Life. The token stays on this phone; the local key goes to the bridge
/// over the home Wi-Fi and nowhere else.
enum TuyaConst {
    static let clientID = "HA_3y9q4ak7g4ephrvke"
    static let schema = "haauthorize"
    static let loginHost = "https://apigw.iotbing.com"
    static let qrPrefix = "tuyaSmart--qrLogin?token="
}

struct TuyaError: LocalizedError {
    let message: String
    var code: String? = nil
    var isAuth: Bool = false
    var errorDescription: String? { message }
}

struct TuyaToken: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var uid: String
    var expiresAt: Date
    var endpoint: String
    var userCode: String
    var terminalId: String

    static var stored: TuyaToken? {
        get { AppGroup.read(TuyaToken.self, "tuya-token.json") }
        set { if let v = newValue { AppGroup.write(v, "tuya-token.json") } else { AppGroup.remove("tuya-token.json") } }
    }
}

/// A device in the Smart Life account, with what the bridge needs to talk to it on the LAN.
struct TuyaDevice: Identifiable, Equatable {
    var id: String
    var name: String
    var category: String
    var productName: String
    var online: Bool
    var localKey: String?

    /// Tuya categories for sockets and power strips: "cz" socket, "pc" power strip.
    var looksLikeStrip: Bool { category == "pc" || category == "cz" }

    static func parse(_ d: [String: Any]) -> TuyaDevice? {
        guard let id = d["id"] as? String else { return nil }
        return TuyaDevice(id: id,
                          name: (d["name"] as? String) ?? "Device",
                          category: (d["category"] as? String) ?? "",
                          productName: (d["product_name"] as? String) ?? (d["productName"] as? String) ?? "",
                          online: (d["online"] as? Bool) ?? ((d["online"] as? NSNumber)?.boolValue ?? true),
                          localKey: (d["local_key"] as? String) ?? (d["localKey"] as? String))
    }
}

/// One outlet found from the cloud's data point names (switch_1, switch_usb1, ...).
struct StripOutletGuess: Equatable {
    var name: String
    var dp: String
}

// MARK: - Crypto (port of tuya_sharing.customerapi)

enum TuyaCrypto {
    private static let nonceChars = Array("ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678")

    static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func md5Hex(_ s: String) -> String { hex(Insecure.MD5.hash(data: Data(s.utf8))) }

    static func hmacHex(key: String, message: String) -> String {
        hex(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: Data(key.utf8))))
    }

    static func secret(rid: String, hashKey: String) -> String { String(hmacHex(key: rid, message: hashKey).prefix(16)) }

    static func encrypt(_ plain: String, secret: String) throws -> String {
        let nonceString = String((0..<12).map { _ in nonceChars.randomElement()! })
        let nonceData = Data(nonceString.utf8)
        let box = try AES.GCM.seal(Data(plain.utf8), using: SymmetricKey(data: Data(secret.utf8)),
                                   nonce: AES.GCM.Nonce(data: nonceData))
        var sealed = Data(box.ciphertext)
        sealed.append(Data(box.tag))
        return nonceData.base64EncodedString() + sealed.base64EncodedString()
    }

    static func decrypt(_ b64: String, secret: String) throws -> Data {
        guard let raw = Data(base64Encoded: b64, options: .ignoreUnknownCharacters), raw.count > 28 else {
            throw TuyaError(message: "Couldn't decode the server response.")
        }
        let bytes = [UInt8](raw)
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: Data(bytes[0..<12])),
                                        ciphertext: Data(bytes[12..<(bytes.count - 16)]),
                                        tag: Data(bytes[(bytes.count - 16)...]))
        return try AES.GCM.open(box, using: SymmetricKey(data: Data(secret.utf8)))
    }

    static func compactJSON(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

// MARK: - QR login

enum TuyaLogin {
    private static func json(_ request: URLRequest) async throws -> [String: Any] {
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TuyaError(message: "Unexpected response from Tuya.")
        }
        return obj
    }

    /// The QR token to show; the user scans "tuyaSmart--qrLogin?token=<token>" in Smart Life.
    static func requestQR(userCode: String) async throws -> String {
        let uc = TuyaCrypto.formEncode(userCode)
        let url = URL(string: "\(TuyaConst.loginHost)/v1.0/m/life/home-assistant/qrcode/tokens?clientid=\(TuyaConst.clientID)&usercode=\(uc)&schema=\(TuyaConst.schema)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        let obj = try await json(req)
        if obj["success"] as? Bool == true, let result = obj["result"] as? [String: Any], let qr = result["qrcode"] as? String { return qr }
        throw TuyaError(message: (obj["msg"] as? String) ?? "Tuya rejected that user code.", code: obj["code"].map { "\($0)" })
    }

    /// Nil until the QR has been confirmed in Smart Life.
    static func poll(qr: String, userCode: String) async throws -> TuyaToken? {
        let uc = TuyaCrypto.formEncode(userCode)
        let url = URL(string: "\(TuyaConst.loginHost)/v1.0/m/life/home-assistant/qrcode/tokens/\(qr)?clientid=\(TuyaConst.clientID)&usercode=\(uc)")!
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let obj = try await json(req)
        guard obj["success"] as? Bool == true, let r = obj["result"] as? [String: Any] else { return nil }
        let t = (obj["t"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970 * 1000
        let expire = (r["expire_time"] as? NSNumber)?.doubleValue ?? 7200
        guard let access = r["access_token"] as? String, let refresh = r["refresh_token"] as? String,
              let endpoint = r["endpoint"] as? String else { throw TuyaError(message: "Login response was missing fields.") }
        return TuyaToken(accessToken: access, refreshToken: refresh, uid: "\(r["uid"] ?? "")",
                         expiresAt: Date(timeIntervalSince1970: t / 1000 + expire),
                         endpoint: endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint,
                         userCode: userCode, terminalId: "\(r["terminal_id"] ?? "")")
    }
}

// MARK: - Signed client (read only: homes, devices, data point names)

actor TuyaClient {
    private(set) var token: TuyaToken

    init(token: TuyaToken) { self.token = token }

    func allDevices() async throws -> [TuyaDevice] {
        var out: [TuyaDevice] = []
        let homes = (try await request("GET", "/v1.0/m/life/users/homes") as? [[String: Any]] ?? []).compactMap { h in h["ownerId"].map { "\($0)" } }
        for home in homes {
            let list = try await request("GET", "/v1.0/m/life/ha/home/devices", query: ["homeId": home]) as? [[String: Any]] ?? []
            for d in list.compactMap(TuyaDevice.parse) where !out.contains(where: { $0.id == d.id }) { out.append(d) }
        }
        return out
    }

    /// Latest copy of one device, for a fresh local key after the strip was re-paired.
    func device(id: String) async throws -> TuyaDevice? {
        let result = try await request("GET", "/v1.0/m/life/ha/devices/detail", query: ["devIds": id])
        return (result as? [[String: Any]] ?? []).compactMap(TuyaDevice.parse).first { $0.id == id }
    }

    /// Outlets from the cloud's data point names: switch_1/2/3 and switch_usb*, in data point order.
    func outlets(id: String) async throws -> [StripOutletGuess] {
        let result = try await request("GET", "/v1.0/m/life/devices/\(id)/status")
        var pairs: [(dp: Int, code: String)] = []
        for r in (result as? [String: Any])?["dpStatusRelationDTOS"] as? [[String: Any]] ?? [] {
            if let dp = r["dpId"], let n = Int("\(dp)"), let code = r["statusCode"] as? String { pairs.append((n, code)) }
        }
        pairs.sort { $0.dp < $1.dp }
        var outlets: [StripOutletGuess] = []
        let usb = pairs.filter { $0.code.hasPrefix("switch_usb") }
        for p in pairs {
            if p.code == "switch" || (p.code.hasPrefix("switch_") && Int(p.code.dropFirst(7)) != nil) {
                outlets.append(StripOutletGuess(name: "Outlet \(outlets.count + 1)", dp: "\(p.dp)"))
            }
        }
        for (i, p) in usb.enumerated() {
            outlets.append(StripOutletGuess(name: usb.count > 1 ? "USB \(i + 1)" : "USB", dp: "\(p.dp)"))
        }
        return outlets
    }

    private func request(_ method: String, _ path: String, query: [String: Any]? = nil, body: [String: Any]? = nil) async throws -> Any? {
        try await refreshIfNeeded()
        return try await raw(method, path, query: query, body: body).result
    }

    private func refreshIfNeeded() async throws {
        guard token.expiresAt.timeIntervalSinceNow < 60 else { return }
        let response: (result: Any?, t: Double?)
        do {
            response = try await raw("GET", "/v1.0/m/token/\(token.refreshToken)")
        } catch let e as TuyaError {
            throw TuyaError(message: "Your Smart Life session expired. Sign in again. (\(e.message))", code: e.code, isAuth: true)
        }
        guard let r = response.result as? [String: Any], let access = r["accessToken"] as? String,
              let refresh = r["refreshToken"] as? String else {
            throw TuyaError(message: "Your Smart Life session expired. Sign in again.", isAuth: true)
        }
        let t = response.t ?? Date().timeIntervalSince1970 * 1000
        token.accessToken = access
        token.refreshToken = refresh
        if let uid = r["uid"] { token.uid = "\(uid)" }
        token.expiresAt = Date(timeIntervalSince1970: t / 1000 + ((r["expireTime"] as? NSNumber)?.doubleValue ?? 7200))
        TuyaToken.stored = token
    }

    private func raw(_ method: String, _ path: String, query: [String: Any]? = nil, body: [String: Any]? = nil) async throws -> (result: Any?, t: Double?) {
        let rid = UUID().uuidString.lowercased()
        let hashKey = TuyaCrypto.md5Hex(rid + token.refreshToken)
        let secret = TuyaCrypto.secret(rid: rid, hashKey: hashKey)
        var queryEnc = "", bodyEnc = ""
        if let query, !query.isEmpty { queryEnc = try TuyaCrypto.encrypt(TuyaCrypto.compactJSON(query), secret: secret) }
        if let body, !body.isEmpty { bodyEnc = try TuyaCrypto.encrypt(TuyaCrypto.compactJSON(body), secret: secret) }

        let headers: [(String, String)] = [
            ("X-appKey", TuyaConst.clientID), ("X-requestId", rid), ("X-sid", ""),
            ("X-time", String(Int64(Date().timeIntervalSince1970 * 1000))), ("X-token", token.accessToken),
        ]
        let signBase = headers.filter { !$0.1.isEmpty }.map { "\($0.0)=\($0.1)" }.joined(separator: "||") + queryEnc + bodyEnc
        let sign = TuyaCrypto.hmacHex(key: hashKey, message: signBase)

        var urlString = token.endpoint + path
        if !queryEnc.isEmpty { urlString += "?encdata=" + TuyaCrypto.formEncode(queryEnc) }
        guard let url = URL(string: urlString) else { throw TuyaError(message: "Bad URL.") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        for (k, v) in headers where !v.isEmpty { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue(sign, forHTTPHeaderField: "X-sign")
        if !bodyEnc.isEmpty {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["encdata": bodyEnc])
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TuyaError(message: "Tuya returned HTTP \(http.statusCode).", isAuth: http.statusCode == 401)
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TuyaError(message: "Unexpected response from Tuya.")
        }
        let t = (obj["t"] as? NSNumber)?.doubleValue
        guard obj["success"] as? Bool == true else {
            let code = obj["code"].map { "\($0)" }
            throw TuyaError(message: "\((obj["msg"] as? String) ?? "Request failed") (\(code ?? "?"))", code: code,
                            isAuth: ["1010", "1011", "1012"].contains(code ?? ""))
        }
        guard let enc = obj["result"] as? String else { return (obj["result"], t) }
        let plain = try TuyaCrypto.decrypt(enc, secret: secret)
        if let parsed = try? JSONSerialization.jsonObject(with: plain, options: [.fragmentsAllowed]) { return (parsed, t) }
        return (String(data: plain, encoding: .utf8), t)
    }
}
