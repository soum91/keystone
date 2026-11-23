# Surge — Keystone power-strip iPhone app

Surge is a separate SwiftUI app using the existing Keystone ESP32 bridge. It keeps the existing `com.soum91.socket` bundle identifier to upgrade installed Socket builds without duplicate installations. The existing Keystone iPhone app still handles ESP32 firmware, OTA and strip setup. No other bridge firmware.

## Setup
1. In Keystone → Bridge → Power strip, connect the actual strip using Smart Life if compatible; otherwise probe and configure its true Tuya data points. The JO-WFPS-3A2U-US manual alone does not prove that the device uses Tuya LAN.
2. Update firmware from Keystone if Socket pairing is not supported yet. This adds a scoped socket app token, not another bridge firmware.
3. Open Socket on your home Wi-Fi, enter the Keystone bridge's local IP, and pair. The token is stored only in Keychain.
4. After confirming socket state, open Apple Home: Keystone's power strip accessory is already exposed through HomeSpan. Your HomePod mini 2 can act as the automation/home hub.
5. In Apple Shortcuts add an action from Socket: Control Socket (choose a channel and On/Off/Toggle) or Set All Sockets (On/Off).

Socket's All Off skips a channel with Keystone in its name. Individual controls and Home can still power it off: if Keystone is powered by that channel, avoid switching it off.

Shortcuts need LAN connectivity; Apple Home can use your existing HomePod mini 2 for remote operation. Do not claim Tuya compatibility or distinct USB switching until tested. Physical-device validation and compiled IPA remain unverified until GitHub CI succeeds and the strip is paired.

Build: cd SocketApp && brew install xcodegen && xcodegen generate && xcodebuild -project Socket.xcodeproj -scheme Socket -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

App publisher: soum91. This source is within Keystone because the available GitHub connector cannot create a separate repository.
