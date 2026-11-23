import UIKit

/// Opens the official Tuya Smart app for QR approval. This does not change
/// the signed Tuya Home Assistant cloud client or migrate any account.
enum TuyaSmartApp {
    static func open() {
        guard let app = URL(string: "tuyaSmart://") else { return }
        UIApplication.shared.open(app, options: [:]) { opened in
            if !opened, let store = URL(string: "https://apps.apple.com/ca/app/id1034649547") {
                UIApplication.shared.open(store)
            }
        }
    }
}
