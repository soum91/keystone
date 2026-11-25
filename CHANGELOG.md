# Changelog

## [firmware-build-188] - 2026-11-25

## Verified changes since firmware-build-186

- Rebind Keystone HTTP API on Wi-Fi recovery or DHCP changes without disturbing HomeKit ([`f4c0b63b`](https://github.com/soum91/keystone/commit/f4c0b63bf83658d2264b55f0f7f8a629e2fb52e9); `Bridge/KeystoneBridge/KeystoneBridge.ino`)
- Show one-tap authenticated Wi-Fi recovery when HomeKit works but Keystone times out ([`c321b73f`](https://github.com/soum91/keystone/commit/c321b73fb46a2a4fdbd3e9c0e1dea0a3c0d06787); `Keystone/Views/DashboardView.swift`)
- Offer manual authenticated Wi-Fi bridge rediscovery without re-pairing ([`52a395b9`](https://github.com/soum91/keystone/commit/52a395b9c911461651893025ac2545e7f6228225); `Keystone/App/Store.swift`)
- Automatically find changed Keystone DHCP IP by Bonjour and verify existing paired token ([`8e4f9958`](https://github.com/soum91/keystone/commit/8e4f995803f15e8f0ca798533723f1fb23215f09); `Keystone/App/Store.swift`)
- Ignore empty MQTT responses and discard stale WebSocket data on reconnect ([`9b764edd`](https://github.com/soum91/keystone/commit/9b764edd83c0cbb74f048fc258116951dc2a58c4); `Shared/Relay.swift`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-186...firmware-build-188)

## [build-98] - 2026-11-25

## Verified changes since build-93

- Show one-tap authenticated Wi-Fi recovery when HomeKit works but Keystone times out ([`c321b73f`](https://github.com/soum91/keystone/commit/c321b73fb46a2a4fdbd3e9c0e1dea0a3c0d06787); `Keystone/Views/DashboardView.swift`)
- Offer manual authenticated Wi-Fi bridge rediscovery without re-pairing ([`52a395b9`](https://github.com/soum91/keystone/commit/52a395b9c911461651893025ac2545e7f6228225); `Keystone/App/Store.swift`)
- Automatically find changed Keystone DHCP IP by Bonjour and verify existing paired token ([`8e4f9958`](https://github.com/soum91/keystone/commit/8e4f995803f15e8f0ca798533723f1fb23215f09); `Keystone/App/Store.swift`)
- Ignore empty MQTT responses and discard stale WebSocket data on reconnect ([`9b764edd`](https://github.com/soum91/keystone/commit/9b764edd83c0cbb74f048fc258116951dc2a58c4); `Shared/Relay.swift`)
- Honor Afterglow lighting type when merging duplicate Keystone smart switch ([`b25f9fb0`](https://github.com/soum91/keystone/commit/b25f9fb0220ec78f0615ba4e6f14680231b478d0); `Bridge/KeystoneBridge/KeystoneBridge.ino`)
- Register surge:// app link for Afterglow native Home integration panel ([`67b6b961`](https://github.com/soum91/keystone/commit/67b6b96165ac80bb42df2542ee78d3f756b0ca76); `SocketApp/project.yml`)
- Prevent stale Surge releases overwriting FlareStore and verify published source ([`dbea04af`](https://github.com/soum91/keystone/commit/dbea04af05f201bc7b30e0ee37ff76566031f0bd); `.github/scripts/update-socket-source.py`, `.github/workflows/socket-app.yml`)
- Preserve unknown Tuya outlet statuses and show bridge-side LAN diagnostics in Surge ([`15ce3a6e`](https://github.com/soum91/keystone/commit/15ce3a6eed7223f1b1c7a6ed297ad83a2237ff92); `SocketApp/Sources/SocketApp.swift`, `SocketApp/Sources/SurgeCloudStore.swift`)
- Add Surge Tuya Smart cloud fallback, real outlet codes and Keystone DHCP rediscovery ([`3c05588e`](https://github.com/soum91/keystone/commit/3c05588e188e5ba01fcf803d1dc2421d22d5ddf1); `SocketApp/CHANGELOG.md`, `SocketApp/README.md`, `SocketApp/Sources/SocketApp.swift`, and 3 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-93...build-98)

## [firmware-build-186] - 2026-11-25

## Verified changes since firmware-build-185

- Honor Afterglow lighting type when merging duplicate Keystone smart switch ([`b25f9fb0`](https://github.com/soum91/keystone/commit/b25f9fb0220ec78f0615ba4e6f14680231b478d0); `Bridge/KeystoneBridge/KeystoneBridge.ino`)
- Register surge:// app link for Afterglow native Home integration panel ([`67b6b961`](https://github.com/soum91/keystone/commit/67b6b96165ac80bb42df2542ee78d3f756b0ca76); `SocketApp/project.yml`)
- Prevent stale Surge releases overwriting FlareStore and verify published source ([`dbea04af`](https://github.com/soum91/keystone/commit/dbea04af05f201bc7b30e0ee37ff76566031f0bd); `.github/scripts/update-socket-source.py`, `.github/workflows/socket-app.yml`)
- Preserve unknown Tuya outlet statuses and show bridge-side LAN diagnostics in Surge ([`15ce3a6e`](https://github.com/soum91/keystone/commit/15ce3a6eed7223f1b1c7a6ed297ad83a2237ff92); `SocketApp/Sources/SocketApp.swift`, `SocketApp/Sources/SurgeCloudStore.swift`)
- Add Surge Tuya Smart cloud fallback, real outlet codes and Keystone DHCP rediscovery ([`3c05588e`](https://github.com/soum91/keystone/commit/3c05588e188e5ba01fcf803d1dc2421d22d5ddf1); `SocketApp/CHANGELOG.md`, `SocketApp/README.md`, `SocketApp/Sources/SocketApp.swift`, and 3 more)
- Treat relay OTA ACK timeout as uncertain; verify fresh bridge status before reporting failure ([`90703e60`](https://github.com/soum91/keystone/commit/90703e6005ebe24f98659cd7deb44cf4983837fa); `Keystone/App/Store.swift`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-185...firmware-build-186)

## [socket-build-13] - 2026-11-23

## Verified changes since socket-build-10

- Register surge:// app link for Afterglow native Home integration panel ([`67b6b961`](https://github.com/soum91/keystone/commit/67b6b96165ac80bb42df2542ee78d3f756b0ca76); `SocketApp/project.yml`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/socket-build-10...socket-build-13)

## [socket-build-11] - 2026-11-23

## Verified changes since socket-build-9

- Prevent stale Surge releases overwriting FlareStore and verify published source ([`dbea04af`](https://github.com/soum91/keystone/commit/dbea04af05f201bc7b30e0ee37ff76566031f0bd); `.github/scripts/update-socket-source.py`, `.github/workflows/socket-app.yml`)
- Preserve unknown Tuya outlet statuses and show bridge-side LAN diagnostics in Surge ([`15ce3a6e`](https://github.com/soum91/keystone/commit/15ce3a6eed7223f1b1c7a6ed297ad83a2237ff92); `SocketApp/Sources/SocketApp.swift`, `SocketApp/Sources/SurgeCloudStore.swift`)
- Add Surge Tuya Smart cloud fallback, real outlet codes and Keystone DHCP rediscovery ([`3c05588e`](https://github.com/soum91/keystone/commit/3c05588e188e5ba01fcf803d1dc2421d22d5ddf1); `SocketApp/CHANGELOG.md`, `SocketApp/README.md`, `SocketApp/Sources/SocketApp.swift`, and 3 more)
- Treat relay OTA ACK timeout as uncertain; verify fresh bridge status before reporting failure ([`90703e60`](https://github.com/soum91/keystone/commit/90703e6005ebe24f98659cd7deb44cf4983837fa); `Keystone/App/Store.swift`)
- Clear legacy persisted OTA error on first boot into new firmware too ([`e43d6ebd`](https://github.com/soum91/keystone/commit/e43d6ebdd03ac2100d5de14521c17f75d915203b); `Bridge/KeystoneBridge/RemoteOTA.h`)
- Clear stale HTTPS OTA error when firmware was updated through another path ([`0ed6b5b8`](https://github.com/soum91/keystone/commit/0ed6b5b8079b811885e01f392a9552e66f783fb6); `Bridge/KeystoneBridge/RemoteOTA.h`)
- Prefer isolated local OTA preparation and verify upload server readiness before sending firmware ([`458705d7`](https://github.com/soum91/keystone/commit/458705d7403bd47a4d2b39112ec69b6f5c121321); `Keystone/App/Store.swift`)
- Wire isolated local OTA server into early boot; bump firmware 1.11.12 ([`38e90f18`](https://github.com/soum91/keystone/commit/38e90f18b07f32189c51d9851bcf760c665b6e6c); `Bridge/KeystoneBridge/KeystoneBridge.ino`)
- Add minimal Wi-Fi-only authenticated local OTA upload boot with automatic recovery ([`3fbe3982`](https://github.com/soum91/keystone/commit/3fbe398267887ee0bec13a2778b8b8e344d1a1c7); `Bridge/KeystoneBridge/LocalOTA.h`)
- Add authenticated local-only request to reboot into isolated firmware-upload mode ([`90a4998f`](https://github.com/soum91/keystone/commit/90a4998ff617cacbf3fa0d556c21ed084fedcb0b); `Bridge/KeystoneBridge/Screen.h`)
- Add direct Tuya-cloud on/off controls for cloud-only outlets and switches in Keystone ([`9fc81a90`](https://github.com/soum91/keystone/commit/9fc81a90632a845074e884ed42d444e65167bbc3); `Keystone/Views/HomeDevicesView.swift`)
- Track Tuya cloud switch states and confirm cloud commands using existing QR session ([`0b9aa900`](https://github.com/soum91/keystone/commit/0b9aa900b3b466ba400e7481faf42f47465fe7a0); `Keystone/Tuya/HomeDevices.swift`)
- Expose actual Tuya cloud switch channels, including cloud-only power strips ([`735948fb`](https://github.com/soum91/keystone/commit/735948fb45f5eb0da442eb02d435e4d39e38ef9d); `Keystone/Tuya/HomeDevices.swift`)
- Support QR-authorized Tuya cloud power commands without a local device connection ([`6a1d0185`](https://github.com/soum91/keystone/commit/6a1d0185860910d5fb948211c59f30618fe347ff); `Keystone/Strip/TuyaCloud.swift`)
- Preserve Tuya Smart QR sessions and allow reauthorization without clearing home device setup ([`c01210cc`](https://github.com/soum91/keystone/commit/c01210ccb2560113d9552b751c1f750fd11f8946); `Keystone/Strip/TuyaCloud.swift`, `Keystone/Views/HomeDevicesView.swift`, `Keystone/Views/StripSetupView.swift`)
- Use valid three-part Keystone app versions and verify FlareStore feed after publishing ([`97f6886c`](https://github.com/soum91/keystone/commit/97f6886c8f1db1cf18e55361251cd10d67365072); `.github/workflows/build.yml`)
- Auto-test Tuya LAN protocol in strip detector, refresh key, and require local bridge for setup ([`a8d672e1`](https://github.com/soum91/keystone/commit/a8d672e1cd87f20894c8aa524373389490d43c7d); `Keystone/Views/StripManualView.swift`, `Keystone/Views/StripSetupView.swift`)
- Add Tuya Smart launch and safe guided outlet DP verification for Surge ([`160b038d`](https://github.com/soum91/keystone/commit/160b038daa903b332253beb296c0113ae56dc93d); `Bridge/KeystoneBridge/Strip.h`, `Keystone/Tuya/TuyaSmartApp.swift`, `Keystone/Views/HomeDevicesView.swift`, and 2 more)
- Diagnose true Tuya strip LAN connectivity and show per-outlet setup failures inline ([`97c8b5f0`](https://github.com/soum91/keystone/commit/97c8b5f0e6802b9641ad0e71fbde29c8636c06c6); `Keystone/Views/HomeDevicesView.swift`)
- Parse Tuya strip data point mappings robustly and reuse known device DP codes ([`2f558a02`](https://github.com/soum91/keystone/commit/2f558a029203b7944aa659c14c3faf3c84783449); `Keystone/Strip/TuyaCloud.swift`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/socket-build-9...socket-build-11)

## [build-93] - 2026-11-23

## Verified changes since build-87

- Treat relay OTA ACK timeout as uncertain; verify fresh bridge status before reporting failure ([`90703e60`](https://github.com/soum91/keystone/commit/90703e6005ebe24f98659cd7deb44cf4983837fa); `Keystone/App/Store.swift`)
- Clear legacy persisted OTA error on first boot into new firmware too ([`e43d6ebd`](https://github.com/soum91/keystone/commit/e43d6ebdd03ac2100d5de14521c17f75d915203b); `Bridge/KeystoneBridge/RemoteOTA.h`)
- Clear stale HTTPS OTA error when firmware was updated through another path ([`0ed6b5b8`](https://github.com/soum91/keystone/commit/0ed6b5b8079b811885e01f392a9552e66f783fb6); `Bridge/KeystoneBridge/RemoteOTA.h`)
- Prefer isolated local OTA preparation and verify upload server readiness before sending firmware ([`458705d7`](https://github.com/soum91/keystone/commit/458705d7403bd47a4d2b39112ec69b6f5c121321); `Keystone/App/Store.swift`)
- Wire isolated local OTA server into early boot; bump firmware 1.11.12 ([`38e90f18`](https://github.com/soum91/keystone/commit/38e90f18b07f32189c51d9851bcf760c665b6e6c); `Bridge/KeystoneBridge/KeystoneBridge.ino`)
- Add minimal Wi-Fi-only authenticated local OTA upload boot with automatic recovery ([`3fbe3982`](https://github.com/soum91/keystone/commit/3fbe398267887ee0bec13a2778b8b8e344d1a1c7); `Bridge/KeystoneBridge/LocalOTA.h`)
- Add authenticated local-only request to reboot into isolated firmware-upload mode ([`90a4998f`](https://github.com/soum91/keystone/commit/90a4998ff617cacbf3fa0d556c21ed084fedcb0b); `Bridge/KeystoneBridge/Screen.h`)
- Add direct Tuya-cloud on/off controls for cloud-only outlets and switches in Keystone ([`9fc81a90`](https://github.com/soum91/keystone/commit/9fc81a90632a845074e884ed42d444e65167bbc3); `Keystone/Views/HomeDevicesView.swift`)
- Track Tuya cloud switch states and confirm cloud commands using existing QR session ([`0b9aa900`](https://github.com/soum91/keystone/commit/0b9aa900b3b466ba400e7481faf42f47465fe7a0); `Keystone/Tuya/HomeDevices.swift`)
- Expose actual Tuya cloud switch channels, including cloud-only power strips ([`735948fb`](https://github.com/soum91/keystone/commit/735948fb45f5eb0da442eb02d435e4d39e38ef9d); `Keystone/Tuya/HomeDevices.swift`)
- Support QR-authorized Tuya cloud power commands without a local device connection ([`6a1d0185`](https://github.com/soum91/keystone/commit/6a1d0185860910d5fb948211c59f30618fe347ff); `Keystone/Strip/TuyaCloud.swift`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-87...build-93)

## [firmware-build-185] - 2026-11-23

## Verified changes since firmware-build-180

- Clear legacy persisted OTA error on first boot into new firmware too ([`e43d6ebd`](https://github.com/soum91/keystone/commit/e43d6ebdd03ac2100d5de14521c17f75d915203b); `Bridge/KeystoneBridge/RemoteOTA.h`)
- Clear stale HTTPS OTA error when firmware was updated through another path ([`0ed6b5b8`](https://github.com/soum91/keystone/commit/0ed6b5b8079b811885e01f392a9552e66f783fb6); `Bridge/KeystoneBridge/RemoteOTA.h`)
- Prefer isolated local OTA preparation and verify upload server readiness before sending firmware ([`458705d7`](https://github.com/soum91/keystone/commit/458705d7403bd47a4d2b39112ec69b6f5c121321); `Keystone/App/Store.swift`)
- Wire isolated local OTA server into early boot; bump firmware 1.11.12 ([`38e90f18`](https://github.com/soum91/keystone/commit/38e90f18b07f32189c51d9851bcf760c665b6e6c); `Bridge/KeystoneBridge/KeystoneBridge.ino`)
- Add minimal Wi-Fi-only authenticated local OTA upload boot with automatic recovery ([`3fbe3982`](https://github.com/soum91/keystone/commit/3fbe398267887ee0bec13a2778b8b8e344d1a1c7); `Bridge/KeystoneBridge/LocalOTA.h`)
- Add authenticated local-only request to reboot into isolated firmware-upload mode ([`90a4998f`](https://github.com/soum91/keystone/commit/90a4998ff617cacbf3fa0d556c21ed084fedcb0b); `Bridge/KeystoneBridge/Screen.h`)
- Add direct Tuya-cloud on/off controls for cloud-only outlets and switches in Keystone ([`9fc81a90`](https://github.com/soum91/keystone/commit/9fc81a90632a845074e884ed42d444e65167bbc3); `Keystone/Views/HomeDevicesView.swift`)
- Track Tuya cloud switch states and confirm cloud commands using existing QR session ([`0b9aa900`](https://github.com/soum91/keystone/commit/0b9aa900b3b466ba400e7481faf42f47465fe7a0); `Keystone/Tuya/HomeDevices.swift`)
- Expose actual Tuya cloud switch channels, including cloud-only power strips ([`735948fb`](https://github.com/soum91/keystone/commit/735948fb45f5eb0da442eb02d435e4d39e38ef9d); `Keystone/Tuya/HomeDevices.swift`)
- Support QR-authorized Tuya cloud power commands without a local device connection ([`6a1d0185`](https://github.com/soum91/keystone/commit/6a1d0185860910d5fb948211c59f30618fe347ff); `Keystone/Strip/TuyaCloud.swift`)
- Preserve Tuya Smart QR sessions and allow reauthorization without clearing home device setup ([`c01210cc`](https://github.com/soum91/keystone/commit/c01210ccb2560113d9552b751c1f750fd11f8946); `Keystone/Strip/TuyaCloud.swift`, `Keystone/Views/HomeDevicesView.swift`, `Keystone/Views/StripSetupView.swift`)
- Use valid three-part Keystone app versions and verify FlareStore feed after publishing ([`97f6886c`](https://github.com/soum91/keystone/commit/97f6886c8f1db1cf18e55361251cd10d67365072); `.github/workflows/build.yml`)
- Auto-test Tuya LAN protocol in strip detector, refresh key, and require local bridge for setup ([`a8d672e1`](https://github.com/soum91/keystone/commit/a8d672e1cd87f20894c8aa524373389490d43c7d); `Keystone/Views/StripManualView.swift`, `Keystone/Views/StripSetupView.swift`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-180...firmware-build-185)

## [build-87] - 2026-11-23

## Verified changes since build-85

- Preserve Tuya Smart QR sessions and allow reauthorization without clearing home device setup ([`c01210cc`](https://github.com/soum91/keystone/commit/c01210ccb2560113d9552b751c1f750fd11f8946); `Keystone/Strip/TuyaCloud.swift`, `Keystone/Views/HomeDevicesView.swift`, `Keystone/Views/StripSetupView.swift`)
- Use valid three-part Keystone app versions and verify FlareStore feed after publishing ([`97f6886c`](https://github.com/soum91/keystone/commit/97f6886c8f1db1cf18e55361251cd10d67365072); `.github/workflows/build.yml`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-85...build-87)

## [build-85] - 2026-11-23

## Verified changes since build-81

- Auto-test Tuya LAN protocol in strip detector, refresh key, and require local bridge for setup ([`a8d672e1`](https://github.com/soum91/keystone/commit/a8d672e1cd87f20894c8aa524373389490d43c7d); `Keystone/Views/StripManualView.swift`, `Keystone/Views/StripSetupView.swift`)
- Add Tuya Smart launch and safe guided outlet DP verification for Surge ([`160b038d`](https://github.com/soum91/keystone/commit/160b038daa903b332253beb296c0113ae56dc93d); `Bridge/KeystoneBridge/Strip.h`, `Keystone/Tuya/TuyaSmartApp.swift`, `Keystone/Views/HomeDevicesView.swift`, and 2 more)
- Diagnose true Tuya strip LAN connectivity and show per-outlet setup failures inline ([`97c8b5f0`](https://github.com/soum91/keystone/commit/97c8b5f0e6802b9641ad0e71fbde29c8636c06c6); `Keystone/Views/HomeDevicesView.swift`)
- Parse Tuya strip data point mappings robustly and reuse known device DP codes ([`2f558a02`](https://github.com/soum91/keystone/commit/2f558a029203b7944aa659c14c3faf3c84783449); `Keystone/Strip/TuyaCloud.swift`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-81...build-85)

## [firmware-build-180] - 2026-11-23

## Verified changes since firmware-build-179

- Add Tuya Smart launch and safe guided outlet DP verification for Surge ([`160b038d`](https://github.com/soum91/keystone/commit/160b038daa903b332253beb296c0113ae56dc93d); `Bridge/KeystoneBridge/Strip.h`, `Keystone/Tuya/TuyaSmartApp.swift`, `Keystone/Views/HomeDevicesView.swift`, and 2 more)
- Diagnose true Tuya strip LAN connectivity and show per-outlet setup failures inline ([`97c8b5f0`](https://github.com/soum91/keystone/commit/97c8b5f0e6802b9641ad0e71fbde29c8636c06c6); `Keystone/Views/HomeDevicesView.swift`)
- Parse Tuya strip data point mappings robustly and reuse known device DP codes ([`2f558a02`](https://github.com/soum91/keystone/commit/2f558a029203b7944aa659c14c3faf3c84783449); `Keystone/Strip/TuyaCloud.swift`)
- Explain memory-blocked Govee and phone-feed fallback on Home dashboard ([`b0e2d792`](https://github.com/soum91/keystone/commit/b0e2d792bb4521a0edd09cb246b234756731265a); `Keystone/Views/DashboardView.swift`)
- Decode deferred DewPoint Govee packet telemetry in Keystone ([`8d8488a4`](https://github.com/soum91/keystone/commit/8d8488a45765b81445016cc1d13091d58a60f018); `Shared/Bridge.swift`)
- Show Equinox/DewPoint Govee feed diagnostics and correct stale source label ([`641193e3`](https://github.com/soum91/keystone/commit/641193e31373435ae00f0a1ee623fe2f1db8c898); `Keystone/Views/BridgeView.swift`)
- Avoid treating Tuya master switch as an extra strip outlet when individual relays exist ([`129a5bc7`](https://github.com/soum91/keystone/commit/129a5bc7a29038f35cfe5b080bce186f0ddd1f92); `Keystone/Strip/TuyaCloud.swift`)
- Let Keystone promote existing Smart Life plugs to Surge multi-outlet controls; deep-link setup ([`4f15be72`](https://github.com/soum91/keystone/commit/4f15be726cfd453cdbc19665d7563fe68804e61e); `Keystone/App/KeystoneApp.swift`, `Keystone/Views/BridgeView.swift`, `Keystone/Views/HomeDevicesView.swift`, and 4 more)
- Restore original neon Surge icon as app and FlareStore artwork ([`85e16745`](https://github.com/soum91/keystone/commit/85e16745e1b3bb3d78fb0f83e2810a89f196a53f); `SocketApp/Art/surge-neon-original.webp`, `SocketApp/CHANGELOG.md`, `SocketApp/README.md`, and 1 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-179...firmware-build-180)

## [socket-build-9] - 2026-11-23

## Verified changes since socket-build-8

- Explain memory-blocked Govee and phone-feed fallback on Home dashboard ([`b0e2d792`](https://github.com/soum91/keystone/commit/b0e2d792bb4521a0edd09cb246b234756731265a); `Keystone/Views/DashboardView.swift`)
- Decode deferred DewPoint Govee packet telemetry in Keystone ([`8d8488a4`](https://github.com/soum91/keystone/commit/8d8488a45765b81445016cc1d13091d58a60f018); `Shared/Bridge.swift`)
- Show Equinox/DewPoint Govee feed diagnostics and correct stale source label ([`641193e3`](https://github.com/soum91/keystone/commit/641193e31373435ae00f0a1ee623fe2f1db8c898); `Keystone/Views/BridgeView.swift`)
- Avoid treating Tuya master switch as an extra strip outlet when individual relays exist ([`129a5bc7`](https://github.com/soum91/keystone/commit/129a5bc7a29038f35cfe5b080bce186f0ddd1f92); `Keystone/Strip/TuyaCloud.swift`)
- Let Keystone promote existing Smart Life plugs to Surge multi-outlet controls; deep-link setup ([`4f15be72`](https://github.com/soum91/keystone/commit/4f15be726cfd453cdbc19665d7563fe68804e61e); `Keystone/App/KeystoneApp.swift`, `Keystone/Views/BridgeView.swift`, `Keystone/Views/HomeDevicesView.swift`, and 4 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/socket-build-8...socket-build-9)

## [build-81] - 2026-11-23

## Verified changes since build-78

- Explain memory-blocked Govee and phone-feed fallback on Home dashboard ([`b0e2d792`](https://github.com/soum91/keystone/commit/b0e2d792bb4521a0edd09cb246b234756731265a); `Keystone/Views/DashboardView.swift`)
- Decode deferred DewPoint Govee packet telemetry in Keystone ([`8d8488a4`](https://github.com/soum91/keystone/commit/8d8488a45765b81445016cc1d13091d58a60f018); `Shared/Bridge.swift`)
- Show Equinox/DewPoint Govee feed diagnostics and correct stale source label ([`641193e3`](https://github.com/soum91/keystone/commit/641193e31373435ae00f0a1ee623fe2f1db8c898); `Keystone/Views/BridgeView.swift`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-78...build-81)

## [build-78] - 2026-11-23

## Verified changes since build-76

- Avoid treating Tuya master switch as an extra strip outlet when individual relays exist ([`129a5bc7`](https://github.com/soum91/keystone/commit/129a5bc7a29038f35cfe5b080bce186f0ddd1f92); `Keystone/Strip/TuyaCloud.swift`)
- Let Keystone promote existing Smart Life plugs to Surge multi-outlet controls; deep-link setup ([`4f15be72`](https://github.com/soum91/keystone/commit/4f15be726cfd453cdbc19665d7563fe68804e61e); `Keystone/App/KeystoneApp.swift`, `Keystone/Views/BridgeView.swift`, `Keystone/Views/HomeDevicesView.swift`, and 4 more)
- Restore original neon Surge icon as app and FlareStore artwork ([`85e16745`](https://github.com/soum91/keystone/commit/85e16745e1b3bb3d78fb0f83e2810a89f196a53f); `SocketApp/Art/surge-neon-original.webp`, `SocketApp/CHANGELOG.md`, `SocketApp/README.md`, and 1 more)
- Correct isolated OTA serial diagnostic newline ([`68aa98bb`](https://github.com/soum91/keystone/commit/68aa98bbde8307b0c3d95cecd497338e7d5c7a42); `Bridge/KeystoneBridge/RemoteOTA.h`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-76...build-78)

## [build-76] - 2026-11-23

## Verified changes since build-75

- Show actual remote OTA failure instead of assuming low memory ([`7de28302`](https://github.com/soum91/keystone/commit/7de28302612f9bc0e2ec28ed069f896954768aac); `Keystone/App/Store.swift`)
- Run firmware maintenance OTA before normal ESP32/HomeKit initialization ([`818a1f31`](https://github.com/soum91/keystone/commit/818a1f31919c4488f6c837556ef197bb292869e0); `Bridge/KeystoneBridge/KeystoneBridge.ino`)
- Boot into isolated Wi-Fi-only internet OTA before HomeSpan to free TLS memory ([`ee6ecdc1`](https://github.com/soum91/keystone/commit/ee6ecdc172f7034733f83528fdea45f0156c8275); `Bridge/KeystoneBridge/RemoteOTA.h`)
- Generate branded Surge iOS icon, package release artwork and enforce compiled app icon ([`381e04f8`](https://github.com/soum91/keystone/commit/381e04f8d6dfe592e370836ef6297bc053988702); `.github/workflows/socket-app.yml`, `SocketApp/README.md`, `SocketApp/scripts/make_surge_icon.py`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-75...build-76)

## [socket-build-8] - 2026-11-23

## Verified changes since socket-build-7

- Restore original neon Surge icon as app and FlareStore artwork ([`85e16745`](https://github.com/soum91/keystone/commit/85e16745e1b3bb3d78fb0f83e2810a89f196a53f); `SocketApp/Art/surge-neon-original.webp`, `SocketApp/CHANGELOG.md`, `SocketApp/README.md`, and 1 more)
- Correct isolated OTA serial diagnostic newline ([`68aa98bb`](https://github.com/soum91/keystone/commit/68aa98bbde8307b0c3d95cecd497338e7d5c7a42); `Bridge/KeystoneBridge/RemoteOTA.h`)
- Show actual remote OTA failure instead of assuming low memory ([`7de28302`](https://github.com/soum91/keystone/commit/7de28302612f9bc0e2ec28ed069f896954768aac); `Keystone/App/Store.swift`)
- Run firmware maintenance OTA before normal ESP32/HomeKit initialization ([`818a1f31`](https://github.com/soum91/keystone/commit/818a1f31919c4488f6c837556ef197bb292869e0); `Bridge/KeystoneBridge/KeystoneBridge.ino`)
- Boot into isolated Wi-Fi-only internet OTA before HomeSpan to free TLS memory ([`ee6ecdc1`](https://github.com/soum91/keystone/commit/ee6ecdc172f7034733f83528fdea45f0156c8275); `Bridge/KeystoneBridge/RemoteOTA.h`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/socket-build-7...socket-build-8)

## [firmware-build-179] - 2026-11-23

## Verified changes since firmware-build-175

- Correct isolated OTA serial diagnostic newline ([`68aa98bb`](https://github.com/soum91/keystone/commit/68aa98bbde8307b0c3d95cecd497338e7d5c7a42); `Bridge/KeystoneBridge/RemoteOTA.h`)
- Show actual remote OTA failure instead of assuming low memory ([`7de28302`](https://github.com/soum91/keystone/commit/7de28302612f9bc0e2ec28ed069f896954768aac); `Keystone/App/Store.swift`)
- Run firmware maintenance OTA before normal ESP32/HomeKit initialization ([`818a1f31`](https://github.com/soum91/keystone/commit/818a1f31919c4488f6c837556ef197bb292869e0); `Bridge/KeystoneBridge/KeystoneBridge.ino`)
- Boot into isolated Wi-Fi-only internet OTA before HomeSpan to free TLS memory ([`ee6ecdc1`](https://github.com/soum91/keystone/commit/ee6ecdc172f7034733f83528fdea45f0156c8275); `Bridge/KeystoneBridge/RemoteOTA.h`)
- Generate branded Surge iOS icon, package release artwork and enforce compiled app icon ([`381e04f8`](https://github.com/soum91/keystone/commit/381e04f8d6dfe592e370836ef6297bc053988702); `.github/workflows/socket-app.yml`, `SocketApp/README.md`, `SocketApp/scripts/make_surge_icon.py`)
- Rename Socket UI to Surge, discover Keystone via Bonjour and explain firmware pairing failures ([`4edcfcda`](https://github.com/soum91/keystone/commit/4edcfcda05b03b8112b66defb23cdd8435d4051c); `.github/scripts/update-socket-source.py`, `SocketApp/CHANGELOG.md`, `SocketApp/README.md`, and 7 more)
- Publish Socket IPA in shared FlareStore feed and preserve multi-app source entries ([`e3d09369`](https://github.com/soum91/keystone/commit/e3d0936927e03050f527cfba8460fdadf960ab7e); `.github/scripts/update-socket-source.py`, `.github/scripts/update-source.py`, `.github/workflows/socket-app.yml`)
- Avoid redundant Keystone IPA builds for standalone Socket changes ([`ef469920`](https://github.com/soum91/keystone/commit/ef469920cc6815cdd9da7ed758dcd39245027222); `.github/workflows/build.yml`)
- Separate AppShortcutsBuilder expressions without array comma ([`ecf64602`](https://github.com/soum91/keystone/commit/ecf646025c12d564a3cefed252c446405a6ad22c); `SocketApp/Sources/SocketIntents.swift`)
- Fix AppShortcutsBuilder syntax for Socket iOS compilation ([`c329f0c2`](https://github.com/soum91/keystone/commit/c329f0c2307524ba206094d90d60b84e6ee95254); `SocketApp/Sources/SocketIntents.swift`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-175...firmware-build-179)

## [socket-build-7] - 2026-11-23

## Verified changes since socket-build-6

- Generate branded Surge iOS icon, package release artwork and enforce compiled app icon ([`381e04f8`](https://github.com/soum91/keystone/commit/381e04f8d6dfe592e370836ef6297bc053988702); `.github/workflows/socket-app.yml`, `SocketApp/README.md`, `SocketApp/scripts/make_surge_icon.py`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/socket-build-6...socket-build-7)

## [socket-build-6] - 2026-11-23

## Verified changes since socket-build-5

- Rename Socket UI to Surge, discover Keystone via Bonjour and explain firmware pairing failures ([`4edcfcda`](https://github.com/soum91/keystone/commit/4edcfcda05b03b8112b66defb23cdd8435d4051c); `.github/scripts/update-socket-source.py`, `SocketApp/CHANGELOG.md`, `SocketApp/README.md`, and 7 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/socket-build-5...socket-build-6)

## [build-75] - 2026-11-23

## Verified changes since build-74

- Rename Socket UI to Surge, discover Keystone via Bonjour and explain firmware pairing failures ([`4edcfcda`](https://github.com/soum91/keystone/commit/4edcfcda05b03b8112b66defb23cdd8435d4051c); `.github/scripts/update-socket-source.py`, `SocketApp/CHANGELOG.md`, `SocketApp/README.md`, and 7 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-74...build-75)

## [socket-build-5] - 2026-11-23

## Verified changes since socket-build-4

- Publish Socket IPA in shared FlareStore feed and preserve multi-app source entries ([`e3d09369`](https://github.com/soum91/keystone/commit/e3d0936927e03050f527cfba8460fdadf960ab7e); `.github/scripts/update-socket-source.py`, `.github/scripts/update-source.py`, `.github/workflows/socket-app.yml`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/socket-build-4...socket-build-5)

## [build-74] - 2026-11-23

## Verified changes since build-73

- Publish Socket IPA in shared FlareStore feed and preserve multi-app source entries ([`e3d09369`](https://github.com/soum91/keystone/commit/e3d0936927e03050f527cfba8460fdadf960ab7e); `.github/scripts/update-socket-source.py`, `.github/scripts/update-source.py`, `.github/workflows/socket-app.yml`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-73...build-74)

## [build-73] - 2026-11-23

## Verified changes since build-67

- Avoid redundant Keystone IPA builds for standalone Socket changes ([`ef469920`](https://github.com/soum91/keystone/commit/ef469920cc6815cdd9da7ed758dcd39245027222); `.github/workflows/build.yml`)
- Separate AppShortcutsBuilder expressions without array comma ([`ecf64602`](https://github.com/soum91/keystone/commit/ecf646025c12d564a3cefed252c446405a6ad22c); `SocketApp/Sources/SocketIntents.swift`)
- Fix AppShortcutsBuilder syntax for Socket iOS compilation ([`c329f0c2`](https://github.com/soum91/keystone/commit/c329f0c2307524ba206094d90d60b84e6ee95254); `SocketApp/Sources/SocketIntents.swift`)
- Restrict Socket pairing to outlet control and display its pairing in Keystone ([`5ac7c0dc`](https://github.com/soum91/keystone/commit/5ac7c0dc305cc2bf03b2171959702fbb587d67bd); `Bridge/KeystoneBridge/Extras.h`, `Bridge/KeystoneBridge/Screen.h`, `Keystone/Views/BridgeView.swift`, and 2 more)
- Complete Socket iPhone UI, App Intents, scoped bridge authentication and IPA CI ([`15e730cc`](https://github.com/soum91/keystone/commit/15e730ccf1101a8901f8c12ee8f65c7d15b01074); `.github/workflows/socket-app.yml`, `Bridge/KeystoneBridge/Control.h`, `Bridge/KeystoneBridge/Extras.h`, and 6 more)
- Start standalone Socket app project and Keystone client ([`3be5aacb`](https://github.com/soum91/keystone/commit/3be5aacb6aacec3382e1fcdc58a0290bcb0c5b14); `SocketApp/Sources/SocketCore.swift`, `SocketApp/project.yml`)
- Document Equinox-primary Govee feed and DewPoint/BLE fallback ([`ab78c1da`](https://github.com/soum91/keystone/commit/ab78c1da57d3bd916a5c96357826cf979cd76a27); `Bridge/README.md`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-67...build-73)

## [firmware-build-175] - 2026-11-23

## Verified changes since firmware-build-173

- Restrict Socket pairing to outlet control and display its pairing in Keystone ([`5ac7c0dc`](https://github.com/soum91/keystone/commit/5ac7c0dc305cc2bf03b2171959702fbb587d67bd); `Bridge/KeystoneBridge/Extras.h`, `Bridge/KeystoneBridge/Screen.h`, `Keystone/Views/BridgeView.swift`, and 2 more)
- Complete Socket iPhone UI, App Intents, scoped bridge authentication and IPA CI ([`15e730cc`](https://github.com/soum91/keystone/commit/15e730ccf1101a8901f8c12ee8f65c7d15b01074); `.github/workflows/socket-app.yml`, `Bridge/KeystoneBridge/Control.h`, `Bridge/KeystoneBridge/Extras.h`, and 6 more)
- Start standalone Socket app project and Keystone client ([`3be5aacb`](https://github.com/soum91/keystone/commit/3be5aacb6aacec3382e1fcdc58a0290bcb0c5b14); `SocketApp/Sources/SocketCore.swift`, `SocketApp/project.yml`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-173...firmware-build-175)

## [socket-build-4] - 2026-11-23

## Verified changes since build-67

- Avoid redundant Keystone IPA builds for standalone Socket changes ([`ef469920`](https://github.com/soum91/keystone/commit/ef469920cc6815cdd9da7ed758dcd39245027222); `.github/workflows/build.yml`)
- Separate AppShortcutsBuilder expressions without array comma ([`ecf64602`](https://github.com/soum91/keystone/commit/ecf646025c12d564a3cefed252c446405a6ad22c); `SocketApp/Sources/SocketIntents.swift`)
- Fix AppShortcutsBuilder syntax for Socket iOS compilation ([`c329f0c2`](https://github.com/soum91/keystone/commit/c329f0c2307524ba206094d90d60b84e6ee95254); `SocketApp/Sources/SocketIntents.swift`)
- Restrict Socket pairing to outlet control and display its pairing in Keystone ([`5ac7c0dc`](https://github.com/soum91/keystone/commit/5ac7c0dc305cc2bf03b2171959702fbb587d67bd); `Bridge/KeystoneBridge/Extras.h`, `Bridge/KeystoneBridge/Screen.h`, `Keystone/Views/BridgeView.swift`, and 2 more)
- Complete Socket iPhone UI, App Intents, scoped bridge authentication and IPA CI ([`15e730cc`](https://github.com/soum91/keystone/commit/15e730ccf1101a8901f8c12ee8f65c7d15b01074); `.github/workflows/socket-app.yml`, `Bridge/KeystoneBridge/Control.h`, `Bridge/KeystoneBridge/Extras.h`, and 6 more)
- Start standalone Socket app project and Keystone client ([`3be5aacb`](https://github.com/soum91/keystone/commit/3be5aacb6aacec3382e1fcdc58a0290bcb0c5b14); `SocketApp/Sources/SocketCore.swift`, `SocketApp/project.yml`)
- Document Equinox-primary Govee feed and DewPoint/BLE fallback ([`ab78c1da`](https://github.com/soum91/keystone/commit/ab78c1da57d3bd916a5c96357826cf979cd76a27); `Bridge/README.md`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-67...socket-build-4)

## [build-67] - 2026-11-23

## Verified changes since build-66

- Display active Equinox, DewPoint, or bridge BLE Govee source in Keystone ([`c48ac8a8`](https://github.com/soum91/keystone/commit/c48ac8a8a37a87705610162105c11371ac6eab20); `Keystone/Views/DashboardView.swift`)
- Prefer Equinox Govee UDP feed over DewPoint with BLE fallback ([`baeabe99`](https://github.com/soum91/keystone/commit/baeabe99dbe7d3d888fbaa412e2addd8a0949aee); `Bridge/KeystoneBridge/Govee.h`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-66...build-67)

## [firmware-build-173] - 2026-11-23

## Verified changes since firmware-build-170

- Document Equinox-primary Govee feed and DewPoint/BLE fallback ([`ab78c1da`](https://github.com/soum91/keystone/commit/ab78c1da57d3bd916a5c96357826cf979cd76a27); `Bridge/README.md`)
- Display active Equinox, DewPoint, or bridge BLE Govee source in Keystone ([`c48ac8a8`](https://github.com/soum91/keystone/commit/c48ac8a8a37a87705610162105c11371ac6eab20); `Keystone/Views/DashboardView.swift`)
- Prefer Equinox Govee UDP feed over DewPoint with BLE fallback ([`baeabe99`](https://github.com/soum91/keystone/commit/baeabe99dbe7d3d888fbaa412e2addd8a0949aee); `Bridge/KeystoneBridge/Govee.h`)
- Serialize Keystone IPA build publishing to avoid CI log branch conflicts ([`1c6a379d`](https://github.com/soum91/keystone/commit/1c6a379d3b8d726f40f5f527cdd4ba3bb1fccceb); `.github/workflows/build.yml`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-170...firmware-build-173)

## [firmware-build-170] - 2026-11-23

## Verified changes since firmware-build-169

- Serialize firmware publish jobs and block stale release/Pages downgrades ([`e7119724`](https://github.com/soum91/keystone/commit/e71197244478a0b2499a51249bfc16b76cb0b9e1); `.github/workflows/bridge.yml`)
- Select highest versioned firmware asset even when release jobs overlap ([`609f6b82`](https://github.com/soum91/keystone/commit/609f6b82f89a2598402daa5baed73a75bb80bb74); `Keystone/App/Store.swift`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-169...firmware-build-170)

## [build-66] - 2026-11-23

## Verified changes since build-65

- Serialize Keystone IPA build publishing to avoid CI log branch conflicts ([`1c6a379d`](https://github.com/soum91/keystone/commit/1c6a379d3b8d726f40f5f527cdd4ba3bb1fccceb); `.github/workflows/build.yml`)
- Serialize firmware publish jobs and block stale release/Pages downgrades ([`e7119724`](https://github.com/soum91/keystone/commit/e71197244478a0b2499a51249bfc16b76cb0b9e1); `.github/workflows/bridge.yml`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-65...build-66)

## [build-65] - 2026-11-23

## Verified changes since build-64

- Select highest versioned firmware asset even when release jobs overlap ([`609f6b82`](https://github.com/soum91/keystone/commit/609f6b82f89a2598402daa5baed73a75bb80bb74); `Keystone/App/Store.swift`)
- Document safe verified internet OTA design and first local update requirement ([`9b1ae24f`](https://github.com/soum91/keystone/commit/9b1ae24f7f3fd1b2d295e5dd1c014160b3e3e132); `Bridge/README.md`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-64...build-65)

## [firmware-build-169] - 2026-11-23

## Verified changes since firmware-build-166

- Document safe verified internet OTA design and first local update requirement ([`9b1ae24f`](https://github.com/soum91/keystone/commit/9b1ae24f7f3fd1b2d295e5dd1c014160b3e3e132); `Bridge/README.md`)
- Show remote OTA capability and update state in Keystone firmware settings ([`6210a682`](https://github.com/soum91/keystone/commit/6210a6827c23480b1a8fd415bee4aefe022c875a); `Keystone/Views/BridgeView.swift`)
- Allow internet firmware updates via encrypted relay; verify installed build after reboot ([`154b5923`](https://github.com/soum91/keystone/commit/154b5923cd919e316c1eda3b57f1c78f5a54ea93); `Keystone/App/Store.swift`)
- Decode bridge internet OTA status in Keystone iOS app ([`53906b81`](https://github.com/soum91/keystone/commit/53906b816a00f694c805c32f18f6be8602b1cd00); `Shared/Bridge.swift`)
- Allow only authenticated Keystone remote OTA command through encrypted MQTT relay ([`aeb95e78`](https://github.com/soum91/keystone/commit/aeb95e78a88d0e55c4f3a530a702d0609f37d7c3); `Bridge/KeystoneBridge/Relay.h`)
- Integrate internet OTA maintenance boot into Keystone worker and status ([`7a8f5b81`](https://github.com/soum91/keystone/commit/7a8f5b819d49e066d5296044fef8ff6fc84c40b0); `Bridge/KeystoneBridge/KeystoneBridge.ino`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-166...firmware-build-169)

## [firmware-build-168] - 2026-11-23

## Verified changes since firmware-build-167

- Allow only authenticated Keystone remote OTA command through encrypted MQTT relay ([`aeb95e78`](https://github.com/soum91/keystone/commit/aeb95e78a88d0e55c4f3a530a702d0609f37d7c3); `Bridge/KeystoneBridge/Relay.h`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-167...firmware-build-168)

## [firmware-build-166] - 2026-11-23

## Verified changes since firmware-build-165

- Introduce verified HTTPS pull OTA handler for remote bridge maintenance ([`891553f8`](https://github.com/soum91/keystone/commit/891553f85ce8fe84cb22864749e38cffca7d3152); `Bridge/KeystoneBridge/RemoteOTA.h`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-165...firmware-build-166)

## [firmware-build-167] - 2026-11-23

## Verified changes since firmware-build-165

- Integrate internet OTA maintenance boot into Keystone worker and status ([`7a8f5b81`](https://github.com/soum91/keystone/commit/7a8f5b819d49e066d5296044fef8ff6fc84c40b0); `Bridge/KeystoneBridge/KeystoneBridge.ino`)
- Introduce verified HTTPS pull OTA handler for remote bridge maintenance ([`891553f8`](https://github.com/soum91/keystone/commit/891553f85ce8fe84cb22864749e38cffca7d3152); `Bridge/KeystoneBridge/RemoteOTA.h`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-165...firmware-build-167)

## [build-64] - 2026-11-23

## Verified changes since build-62

- Show remote OTA capability and update state in Keystone firmware settings ([`6210a682`](https://github.com/soum91/keystone/commit/6210a6827c23480b1a8fd415bee4aefe022c875a); `Keystone/Views/BridgeView.swift`)
- Allow internet firmware updates via encrypted relay; verify installed build after reboot ([`154b5923`](https://github.com/soum91/keystone/commit/154b5923cd919e316c1eda3b57f1c78f5a54ea93); `Keystone/App/Store.swift`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-62...build-64)

## [firmware-build-165] - 2026-11-23

## Verified changes since firmware-build-163

- Publish build marker and SHA-256 sidecar for verified internet OTA ([`8a5ba7c1`](https://github.com/soum91/keystone/commit/8a5ba7c1393e4c9c7f40a81f1a93bf54bf45689a); `.github/workflows/bridge.yml`)
- Keystone app: display HomeKit secure-session state and recovery diagnostics ([`df063c7d`](https://github.com/soum91/keystone/commit/df063c7d1844db889c1a641bde89274a9b20400f); `Bridge/README.md`, `Keystone/Views/BridgeView.swift`, `Shared/Bridge.swift`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-163...firmware-build-165)

## [build-62] - 2026-11-23

## Verified changes since build-61

- Decode bridge internet OTA status in Keystone iOS app ([`53906b81`](https://github.com/soum91/keystone/commit/53906b816a00f694c805c32f18f6be8602b1cd00); `Shared/Bridge.swift`)
- Allow only authenticated Keystone remote OTA command through encrypted MQTT relay ([`aeb95e78`](https://github.com/soum91/keystone/commit/aeb95e78a88d0e55c4f3a530a702d0609f37d7c3); `Bridge/KeystoneBridge/Relay.h`)
- Integrate internet OTA maintenance boot into Keystone worker and status ([`7a8f5b81`](https://github.com/soum91/keystone/commit/7a8f5b819d49e066d5296044fef8ff6fc84c40b0); `Bridge/KeystoneBridge/KeystoneBridge.ino`)
- Introduce verified HTTPS pull OTA handler for remote bridge maintenance ([`891553f8`](https://github.com/soum91/keystone/commit/891553f85ce8fe84cb22864749e38cffca7d3152); `Bridge/KeystoneBridge/RemoteOTA.h`)
- Publish build marker and SHA-256 sidecar for verified internet OTA ([`8a5ba7c1`](https://github.com/soum91/keystone/commit/8a5ba7c1393e4c9c7f40a81f1a93bf54bf45689a); `.github/workflows/bridge.yml`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-61...build-62)

## [firmware-build-164] - 2026-11-22

## Verified changes since firmware-build-162

- Keystone app: display HomeKit secure-session state and recovery diagnostics ([`df063c7d`](https://github.com/soum91/keystone/commit/df063c7d1844db889c1a641bde89274a9b20400f); `Bridge/README.md`, `Keystone/Views/BridgeView.swift`, `Shared/Bridge.swift`)
- HomeSpan: recover one prolonged HomeKit session loss; disable Wi-Fi modem sleep and expose diagnostics ([`f936543d`](https://github.com/soum91/keystone/commit/f936543ddf55eb5f9fc84236754bfe1e658e9a49); `Bridge/KeystoneBridge/KeystoneBridge.ino`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-162...firmware-build-164)

## [firmware-build-163] - 2026-11-22

## Verified changes since firmware-build-162

- HomeSpan: recover one prolonged HomeKit session loss; disable Wi-Fi modem sleep and expose diagnostics ([`f936543d`](https://github.com/soum91/keystone/commit/f936543ddf55eb5f9fc84236754bfe1e658e9a49); `Bridge/KeystoneBridge/KeystoneBridge.ino`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-162...firmware-build-163)

## [build-61] - 2026-11-22

## Verified changes since build-60

- Keystone app: display HomeKit secure-session state and recovery diagnostics ([`df063c7d`](https://github.com/soum91/keystone/commit/df063c7d1844db889c1a641bde89274a9b20400f); `Bridge/README.md`, `Keystone/Views/BridgeView.swift`, `Shared/Bridge.swift`)
- HomeSpan: recover one prolonged HomeKit session loss; disable Wi-Fi modem sleep and expose diagnostics ([`f936543d`](https://github.com/soum91/keystone/commit/f936543ddf55eb5f9fc84236754bfe1e658e9a49); `Bridge/KeystoneBridge/KeystoneBridge.ino`)
- Govee fallback: remember named BLE address for iOS-pinned sensor ([`c34dd45b`](https://github.com/soum91/keystone/commit/c34dd45bc039f13e6bb0f137056ce16b5a0ec631); `Bridge/KeystoneBridge/Govee.h`)
- Fix DewPoint feed expiry: never reuse older local BLE validity for stale phone data ([`4d8aff44`](https://github.com/soum91/keystone/commit/4d8aff44476c485edd91c999eddfa9e420bf2904); `Bridge/KeystoneBridge/Govee.h`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-60...build-61)

## [firmware-build-162] - 2026-11-22

## Verified changes since firmware-build-161

- Govee fallback: remember named BLE address for iOS-pinned sensor ([`c34dd45b`](https://github.com/soum91/keystone/commit/c34dd45bc039f13e6bb0f137056ce16b5a0ec631); `Bridge/KeystoneBridge/Govee.h`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-161...firmware-build-162)

## [firmware-build-161] - 2026-11-22

## Verified changes since firmware-build-160

- Fix DewPoint feed expiry: never reuse older local BLE validity for stale phone data ([`4d8aff44`](https://github.com/soum91/keystone/commit/4d8aff44476c485edd91c999eddfa9e420bf2904); `Bridge/KeystoneBridge/Govee.h`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-160...firmware-build-161)

## [firmware-build-160] - 2026-11-22

## Verified changes since firmware-build-159

- Bridge + app: ingest DewPoint iOS Govee feed and show source in Keystone ([`3023cb7c`](https://github.com/soum91/keystone/commit/3023cb7c6555c6c6f27e4009b9b22cc17633bdda); `Bridge/KeystoneBridge/Govee.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/README.md`, and 2 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-159...firmware-build-160)

## [build-60] - 2026-11-22

## Verified changes since build-59

- Bridge + app: ingest DewPoint iOS Govee feed and show source in Keystone ([`3023cb7c`](https://github.com/soum91/keystone/commit/3023cb7c6555c6c6f27e4009b9b22cc17633bdda); `Bridge/KeystoneBridge/Govee.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/README.md`, and 2 more)
- Delay local BLE while waiting for feed and preserve HomeKit accessory IDs ([`204c98f2`](https://github.com/soum91/keystone/commit/204c98f2151b9afb9151dd4d828d4950cab7b5d9); `Bridge/KeystoneBridge/Govee.h`, `Bridge/README.md`)
- Bridge: prefer DewPoint LAN Govee feed; fall back to memory-safe local BLE ([`25acaec0`](https://github.com/soum91/keystone/commit/25acaec0c295debabf366311ee30befaa76ddd7b); `Bridge/KeystoneBridge/Govee.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/README.md`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-59...build-60)

## [firmware-build-159] - 2026-11-21

## Verified changes since firmware-build-158

- Delay local BLE while waiting for feed and preserve HomeKit accessory IDs ([`204c98f2`](https://github.com/soum91/keystone/commit/204c98f2151b9afb9151dd4d828d4950cab7b5d9); `Bridge/KeystoneBridge/Govee.h`, `Bridge/README.md`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-158...firmware-build-159)

## [firmware-build-158] - 2026-11-21

## Verified changes since firmware-build-157

- Bridge: prefer DewPoint LAN Govee feed; fall back to memory-safe local BLE ([`25acaec0`](https://github.com/soum91/keystone/commit/25acaec0c295debabf366311ee30befaa76ddd7b); `Bridge/KeystoneBridge/Govee.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/README.md`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-157...firmware-build-158)

## [firmware-build-157] - 2026-11-21

## Verified changes since firmware-build-156

- Fix Apple Home accessory sending: LAN-only acknowledgement, verify applied device list, prevent false success ([`fe3f1239`](https://github.com/soum91/keystone/commit/fe3f12390773789d06d017bb57cf600ef95505f8); `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Keystone/Tuya/HomeDevices.swift`, `Keystone/Views/HomeDevicesView.swift`, and 1 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-156...firmware-build-157)

## [build-59] - 2026-11-21

## Verified changes since build-58

- Fix Apple Home accessory sending: LAN-only acknowledgement, verify applied device list, prevent false success ([`fe3f1239`](https://github.com/soum91/keystone/commit/fe3f12390773789d06d017bb57cf600ef95505f8); `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Keystone/Tuya/HomeDevices.swift`, `Keystone/Views/HomeDevicesView.swift`, and 1 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-58...build-59)

## [firmware-build-156] - 2026-11-21

## Verified changes since firmware-build-155

- Bridge 1.11.5: reduce network starvation and preserve local HomeKit during DNS outages ([`725f0def`](https://github.com/soum91/keystone/commit/725f0def701404de227e3dc4ebe477dfa3e68d31); `Bridge/KeystoneBridge/Govee.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/Strip.h`, and 5 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-155...firmware-build-156)

## [build-58] - 2026-11-21

## Verified changes since build-57

- Bridge 1.11.5: reduce network starvation and preserve local HomeKit during DNS outages ([`725f0def`](https://github.com/soum91/keystone/commit/725f0def701404de227e3dc4ebe477dfa3e68d31); `Bridge/KeystoneBridge/Govee.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/Strip.h`, and 5 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-57...build-58)

## [firmware-build-155] - 2026-11-21

## Verified changes since firmware-build-154

- Bridge 1.11.4: recover memory for Govee, accept Tuya STATUS, fix relay response race ([`93683954`](https://github.com/soum91/keystone/commit/93683954f45cd80976da10ecb279e42dea72ef1f); `Bridge/KeystoneBridge/Govee.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/Relay.h`, and 3 more)
- Fix build: rename download status variable ([`80e6c1c8`](https://github.com/soum91/keystone/commit/80e6c1c80f50f564e78a0c58ad4c54ac04b13f51); `Keystone/App/Store.swift`)
- Keystone: re-check GitHub before every firmware update; clear errors for stale links ([`8acd472f`](https://github.com/soum91/keystone/commit/8acd472f67cdf1d19f0902bb46bc079d60a491ff); `Keystone/App/Store.swift`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-154...firmware-build-155)

## [build-57] - 2026-11-21

## Verified changes since build-56

- Bridge 1.11.4: recover memory for Govee, accept Tuya STATUS, fix relay response race ([`93683954`](https://github.com/soum91/keystone/commit/93683954f45cd80976da10ecb279e42dea72ef1f); `Bridge/KeystoneBridge/Govee.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/Relay.h`, and 3 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-56...build-57)

## [build-56] - 2026-11-18

## Verified changes since build-54

- Fix build: rename download status variable ([`80e6c1c8`](https://github.com/soum91/keystone/commit/80e6c1c80f50f564e78a0c58ad4c54ac04b13f51); `Keystone/App/Store.swift`)
- Keystone: re-check GitHub before every firmware update; clear errors for stale links ([`8acd472f`](https://github.com/soum91/keystone/commit/8acd472f67cdf1d19f0902bb46bc079d60a491ff); `Keystone/App/Store.swift`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-54...build-56)

## [build-54] - 2026-11-18

## Verified changes since build-53

- Bridge 1.11.3: listen for Tuya announcements only in short windows (fixes updates timing out and a sluggish bridge on 1.11.1) ([`e2b71f27`](https://github.com/soum91/keystone/commit/e2b71f2751e5e33f31239c0936d267d43365fdb1); `Bridge/KeystoneBridge/Extras.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/TuyaApply.h`, and 2 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-53...build-54)

## [firmware-build-154] - 2026-11-18

## Verified changes since firmware-build-153

- Bridge 1.11.3: listen for Tuya announcements only in short windows (fixes updates timing out and a sluggish bridge on 1.11.1) ([`e2b71f27`](https://github.com/soum91/keystone/commit/e2b71f2751e5e33f31239c0936d267d43365fdb1); `Bridge/KeystoneBridge/Extras.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/TuyaApply.h`, and 2 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-153...firmware-build-154)

## [firmware-build-153] - 2026-11-18

## Verified changes since firmware-build-152

- Bridge 1.11.2: settings work through the relay too (screen off now sticks); Keystone checks the screen change took ([`bfd653cf`](https://github.com/soum91/keystone/commit/bfd653cfd46bd3b46336cb54e5f50346891bd609); `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/Relay.h`, `Bridge/KeystoneBridge/Screen.h`, and 3 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-152...firmware-build-153)

## [build-53] - 2026-11-18

## Verified changes since build-52

- Bridge 1.11.2: settings work through the relay too (screen off now sticks); Keystone checks the screen change took ([`bfd653cf`](https://github.com/soum91/keystone/commit/bfd653cfd46bd3b46336cb54e5f50346891bd609); `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/Relay.h`, `Bridge/KeystoneBridge/Screen.h`, and 3 more)
- Fix build: move applySeen/handleTuyaSeen into TuyaApply.h (Arduino prototype order) ([`cc16b40c`](https://github.com/soum91/keystone/commit/cc16b40c1def495f962e0e3bce0f7f97ad4f40af); `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/TuyaApply.h`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-52...build-53)

## [firmware-build-152] - 2026-11-18

## Verified changes since firmware-build-150

- Fix build: move applySeen/handleTuyaSeen into TuyaApply.h (Arduino prototype order) ([`cc16b40c`](https://github.com/soum91/keystone/commit/cc16b40c1def495f962e0e3bce0f7f97ad4f40af); `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/TuyaApply.h`)
- Bridge 1.11.1 hears Tuya devices announce their address; Keystone uses it instead of scanning ([`330cf0c5`](https://github.com/soum91/keystone/commit/330cf0c58246ec8f7b134f39aab18569ffaf1088); `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/TuyaDiscover.h`, `Keystone/Tuya/HomeDevices.swift`, and 1 more)
- Keystone: Put everything in Apple Home button (all Smart Life lights, switches, plugs and the purifier) ([`9be3c3d4`](https://github.com/soum91/keystone/commit/9be3c3d42f8c5d76d8485fc755b266f87091f4c7); `Keystone/Tuya/HomeDevices.swift`, `Keystone/Views/HomeDevicesView.swift`)
- Keystone: air purifier to Apple Home from the Devices screen ([`ef1d8df4`](https://github.com/soum91/keystone/commit/ef1d8df4352cd9a33fc4e1dc395d630f77597f5f); `Keystone/Strip/TuyaCloud.swift`, `Keystone/Tuya/HomeDevices.swift`, `Keystone/Views/HomeDevicesView.swift`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-150...firmware-build-152)

## [build-52] - 2026-11-18

## Verified changes since build-51

- Bridge 1.11.1 hears Tuya devices announce their address; Keystone uses it instead of scanning ([`330cf0c5`](https://github.com/soum91/keystone/commit/330cf0c58246ec8f7b134f39aab18569ffaf1088); `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/TuyaDiscover.h`, `Keystone/Tuya/HomeDevices.swift`, and 1 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-51...build-52)

## [build-51] - 2026-11-18

## Verified changes since build-50

- Keystone: Put everything in Apple Home button (all Smart Life lights, switches, plugs and the purifier) ([`9be3c3d4`](https://github.com/soum91/keystone/commit/9be3c3d42f8c5d76d8485fc755b266f87091f4c7); `Keystone/Tuya/HomeDevices.swift`, `Keystone/Views/HomeDevicesView.swift`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-50...build-51)

## [build-50] - 2026-11-18

## Verified changes since build-49

- Keystone: air purifier to Apple Home from the Devices screen ([`ef1d8df4`](https://github.com/soum91/keystone/commit/ef1d8df4352cd9a33fc4e1dc395d630f77597f5f); `Keystone/Strip/TuyaCloud.swift`, `Keystone/Tuya/HomeDevices.swift`, `Keystone/Views/HomeDevicesView.swift`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-49...build-50)

## [firmware-build-150] - 2026-11-18

## Verified changes since firmware-build-148

- Fix build: qrImage shadowing, screen::adminOK ([`93ec637f`](https://github.com/soum91/keystone/commit/93ec637fd0645256aa9e9f7b1e783d2f508866c1); `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Keystone/Views/HomeDevicesView.swift`)
- Keystone puts Smart Life lights, switches and plugs in Apple Home itself (bridge 1.11.0) ([`437cfef9`](https://github.com/soum91/keystone/commit/437cfef94cabab0d5e33ae0ee7381f88d917d4a4); `Bridge/KeystoneBridge/Extras.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Keystone/Strip/TuyaCloud.swift`, and 8 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-148...firmware-build-150)

## [build-49] - 2026-11-18

## Verified changes since build-47

- Fix build: qrImage shadowing, screen::adminOK ([`93ec637f`](https://github.com/soum91/keystone/commit/93ec637fd0645256aa9e9f7b1e783d2f508866c1); `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Keystone/Views/HomeDevicesView.swift`)
- Keystone puts Smart Life lights, switches and plugs in Apple Home itself (bridge 1.11.0) ([`437cfef9`](https://github.com/soum91/keystone/commit/437cfef94cabab0d5e33ae0ee7381f88d917d4a4); `Bridge/KeystoneBridge/Extras.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Keystone/Strip/TuyaCloud.swift`, and 8 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-47...build-49)

## [build-47] - 2026-11-17

## Verified changes since build-46

- Relay: second broker (HiveMQ) as fallback; bridge 1.10.13 switches brokers on failure, Keystone asks through both ([`b52bd874`](https://github.com/soum91/keystone/commit/b52bd8748b84bb9449f49a2268e37a32a33223da); `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/Relay.h`, `Keystone/Views/BridgeView.swift`, and 2 more)
- CI: pin ESP32 Arduino core to 3.3.12 (3.3.13 overflows IRAM by 1664 bytes) ([`da8bf239`](https://github.com/soum91/keystone/commit/da8bf23901867902cc7e71155671a7d79263b025); `.github/workflows/bridge.yml`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-46...build-47)

## [firmware-build-148] - 2026-11-17

## Verified changes since firmware-build-147

- Relay: second broker (HiveMQ) as fallback; bridge 1.10.13 switches brokers on failure, Keystone asks through both ([`b52bd874`](https://github.com/soum91/keystone/commit/b52bd8748b84bb9449f49a2268e37a32a33223da); `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/Relay.h`, `Keystone/Views/BridgeView.swift`, and 2 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-147...firmware-build-148)

## [firmware-build-147] - 2026-11-17

## Verified changes since firmware-build-145

- CI: pin ESP32 Arduino core to 3.3.12 (3.3.13 overflows IRAM by 1664 bytes) ([`da8bf239`](https://github.com/soum91/keystone/commit/da8bf23901867902cc7e71155671a7d79263b025); `.github/workflows/bridge.yml`)
- Bridge 1.10.12: switch off any device (lights, TV, sound bar, purifier, IR, strip, router, Govee); relay diagnostics ([`f5be0514`](https://github.com/soum91/keystone/commit/f5be051422407ec5c15cdfce13f247213fdf3ae7); `Bridge/KeystoneBridge/Extras.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/Relay.h`, and 6 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-145...firmware-build-147)

## [build-46] - 2026-11-17

## Verified changes since build-45

- Bridge 1.10.12: switch off any device (lights, TV, sound bar, purifier, IR, strip, router, Govee); relay diagnostics ([`f5be0514`](https://github.com/soum91/keystone/commit/f5be051422407ec5c15cdfce13f247213fdf3ae7); `Bridge/KeystoneBridge/Extras.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/Relay.h`, and 6 more)
- Bridge 1.10.11: IR remotes show only their power switch in Apple Home (buttons stay in the apps) to save RAM ([`ebf43630`](https://github.com/soum91/keystone/commit/ebf436308c1add21baa423e2aacbac3d90245fdc); `Bridge/KeystoneBridge/Extras.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-45...build-46)

## [firmware-build-145] - 2026-11-15

## Verified changes since firmware-build-144

- Bridge 1.10.11: IR remotes show only their power switch in Apple Home (buttons stay in the apps) to save RAM ([`ebf43630`](https://github.com/soum91/keystone/commit/ebf436308c1add21baa423e2aacbac3d90245fdc); `Bridge/KeystoneBridge/Extras.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-144...firmware-build-145)

## [firmware-build-144] - 2026-11-15

## Verified changes since firmware-build-143

- Bridge 1.10.10: release the classic-Bluetooth RAM reserve at boot, relay waits for 16 KB block; Keystone shows Free before Apple Home and Freed at boot ([`a55e4eaf`](https://github.com/soum91/keystone/commit/a55e4eafcb7ef474a32ba6c5d08adb784282feb8); `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/Relay.h`, `Keystone/Views/BridgeView.swift`, and 1 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-143...firmware-build-144)

## [build-45] - 2026-11-15

## Verified changes since build-44

- Bridge 1.10.10: release the classic-Bluetooth RAM reserve at boot, relay waits for 16 KB block; Keystone shows Free before Apple Home and Freed at boot ([`a55e4eaf`](https://github.com/soum91/keystone/commit/a55e4eafcb7ef474a32ba6c5d08adb784282feb8); `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/Relay.h`, `Keystone/Views/BridgeView.swift`, and 1 more)
- Bridge 1.10.9: sound bar secure link waits for memory instead of crashing the bridge (crash during bar poll at 7 KB free) ([`d5922e87`](https://github.com/soum91/keystone/commit/d5922e875c609e1cbfb0a0e91537e8392ed79c75); `Bridge/KeystoneBridge/KeystoneBridge.ino`)
- Bridge 1.10.8: plain relays and plugs get a Switch tile in Apple Home (kind=switch from Afterglow) ([`f41b0325`](https://github.com/soum91/keystone/commit/f41b032591cae25b2e7ab97bd2057403fd46f0ed); `Bridge/KeystoneBridge/KeystoneBridge.ino`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-44...build-45)

## [firmware-build-143] - 2026-11-15

## Verified changes since firmware-build-142

- Bridge 1.10.9: sound bar secure link waits for memory instead of crashing the bridge (crash during bar poll at 7 KB free) ([`d5922e87`](https://github.com/soum91/keystone/commit/d5922e875c609e1cbfb0a0e91537e8392ed79c75); `Bridge/KeystoneBridge/KeystoneBridge.ino`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-142...firmware-build-143)

## [firmware-build-142] - 2026-11-14

## Verified changes since firmware-build-141

- Bridge 1.10.8: plain relays and plugs get a Switch tile in Apple Home (kind=switch from Afterglow) ([`f41b0325`](https://github.com/soum91/keystone/commit/f41b032591cae25b2e7ab97bd2057403fd46f0ed); `Bridge/KeystoneBridge/KeystoneBridge.ino`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-141...firmware-build-142)

## [firmware-build-141] - 2026-11-14

## Verified changes since firmware-build-140

- Power strip: 'When power comes back' setting (relay_status) via Smart Life detection; bridge 1.10.7 ([`7c6dc15e`](https://github.com/soum91/keystone/commit/7c6dc15e9af29dca897336813af56c6d9001df20); `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/Strip.h`, `Keystone/Strip/TuyaCloud.swift`, and 2 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-140...firmware-build-141)

## [build-44] - 2026-11-14

## Verified changes since build-43

- Power strip: 'When power comes back' setting (relay_status) via Smart Life detection; bridge 1.10.7 ([`7c6dc15e`](https://github.com/soum91/keystone/commit/7c6dc15e9af29dca897336813af56c6d9001df20); `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/Strip.h`, `Keystone/Strip/TuyaCloud.swift`, and 2 more)
- Bridge 1.10.6: breadcrumbs no longer walk the heap (bridge went unreachable on 1.10.4/1.10.5) ([`446e7aeb`](https://github.com/soum91/keystone/commit/446e7aeba3d4c73b10bcd2b78041c51e2642d0c8); `Bridge/KeystoneBridge/KeystoneBridge.ino`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-43...build-44)

## [firmware-build-140] - 2026-11-14

## Verified changes since firmware-build-139

- Bridge 1.10.6: breadcrumbs no longer walk the heap (bridge went unreachable on 1.10.4/1.10.5) ([`446e7aeb`](https://github.com/soum91/keystone/commit/446e7aeba3d4c73b10bcd2b78041c51e2642d0c8); `Bridge/KeystoneBridge/KeystoneBridge.ino`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-139...firmware-build-140)

## [firmware-build-139] - 2026-11-14

## Verified changes since firmware-build-138

- Firmware updates on a low-memory bridge: upload from a fresh boot; bridge frees relay buffer at OTA start ([`a46b09a4`](https://github.com/soum91/keystone/commit/a46b09a4f232f02aed74f8ff4373fe25596c2082); `Bridge/KeystoneBridge/Extras.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/Strip.h`, and 1 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-138...firmware-build-139)

## [build-43] - 2026-11-14

## Verified changes since build-42

- Firmware updates on a low-memory bridge: upload from a fresh boot; bridge frees relay buffer at OTA start ([`a46b09a4`](https://github.com/soum91/keystone/commit/a46b09a4f232f02aed74f8ff4373fe25596c2082); `Bridge/KeystoneBridge/Extras.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/Strip.h`, and 1 more)
- Bridge 1.10.4: breadcrumb helper as a macro so Arduino prototypes stay below the structs ([`3a91aae4`](https://github.com/soum91/keystone/commit/3a91aae4dda27764c1d90e42f76e9194730d6451); `Bridge/KeystoneBridge/KeystoneBridge.ino`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-42...build-43)

## [firmware-build-138] - 2026-11-14

## Verified changes since firmware-build-136

- Bridge 1.10.4: breadcrumb helper as a macro so Arduino prototypes stay below the structs ([`3a91aae4`](https://github.com/soum91/keystone/commit/3a91aae4dda27764c1d90e42f76e9194730d6451); `Bridge/KeystoneBridge/KeystoneBridge.ino`)
- Bridge 1.10.4: crash breadcrumbs, Home memory cost, Bluetooth only with real headroom ([`1fd61433`](https://github.com/soum91/keystone/commit/1fd61433ed64c278914fd8373b2f4c1d68cb4135); `Bridge/KeystoneBridge/Govee.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Keystone/Views/BridgeView.swift`, and 1 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-136...firmware-build-138)

## [build-42] - 2026-11-14

## Verified changes since build-41

- Bridge 1.10.4: crash breadcrumbs, Home memory cost, Bluetooth only with real headroom ([`1fd61433`](https://github.com/soum91/keystone/commit/1fd61433ed64c278914fd8373b2f4c1d68cb4135); `Bridge/KeystoneBridge/Govee.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Keystone/Views/BridgeView.swift`, and 1 more)
- Bridge 1.10.3: power strip as one Home accessory, back off when memory is low ([`bf3b2d3b`](https://github.com/soum91/keystone/commit/bf3b2d3bc8c7c72c0c68705f1508c65951aca71f); `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/Strip.h`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-41...build-42)

## [firmware-build-136] - 2026-11-14

## Verified changes since firmware-build-135

- Bridge 1.10.3: power strip as one Home accessory, back off when memory is low ([`bf3b2d3b`](https://github.com/soum91/keystone/commit/bf3b2d3bc8c7c72c0c68705f1508c65951aca71f); `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/Strip.h`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-135...firmware-build-136)

## [firmware-build-135] - 2026-11-13

## Verified changes since firmware-build-134

- Bridge 1.10.2: up to 4 phones per app; Keystone lists paired phones and can forget one ([`44922b1e`](https://github.com/soum91/keystone/commit/44922b1e908673105e2abe130744b02801c96b4c); `Bridge/KeystoneBridge/Control.h`, `Bridge/KeystoneBridge/Extras.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`, and 5 more)
- Firmware update: wait for the bridge to restart between retries, keep the screen awake ([`125582e5`](https://github.com/soum91/keystone/commit/125582e54c967f3a7589e40eb07a4a70e937143c); `Keystone/App/Store.swift`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-134...firmware-build-135)

## [build-41] - 2026-11-13

## Verified changes since build-40

- Bridge 1.10.2: up to 4 phones per app; Keystone lists paired phones and can forget one ([`44922b1e`](https://github.com/soum91/keystone/commit/44922b1e908673105e2abe130744b02801c96b4c); `Bridge/KeystoneBridge/Control.h`, `Bridge/KeystoneBridge/Extras.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`, and 5 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-40...build-41)

## [build-40] - 2026-11-11

## Verified changes since build-39

- Firmware update: wait for the bridge to restart between retries, keep the screen awake ([`125582e5`](https://github.com/soum91/keystone/commit/125582e54c967f3a7589e40eb07a4a70e937143c); `Keystone/App/Store.swift`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-39...build-40)

## [firmware-build-134] - 2026-11-11

## Verified changes since firmware-build-133

- Power strip: set up from Smart Life, bridge finds the strip's IP itself ([`da7e4f0c`](https://github.com/soum91/keystone/commit/da7e4f0c4af64f101f7bcfb24a94971433465494); `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/Strip.h`, `Keystone/Strip/TuyaCloud.swift`, and 5 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-133...firmware-build-134)

## [build-39] - 2026-11-11

## Verified changes since build-38

- Power strip: set up from Smart Life, bridge finds the strip's IP itself ([`da7e4f0c`](https://github.com/soum91/keystone/commit/da7e4f0c4af64f101f7bcfb24a94971433465494); `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/Strip.h`, `Keystone/Strip/TuyaCloud.swift`, and 5 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-38...build-39)

## [firmware-build-133] - 2026-11-11

## Verified changes since firmware-build-132

- Add Tuya Wi-Fi power strip: Apple Home outlets + Keystone controls ([`d0cfd241`](https://github.com/soum91/keystone/commit/d0cfd24159ca55bd9956a38c1e7a900a9bf48e48); `Bridge/KeystoneBridge/Control.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/Strip.h`, and 5 more)
- Internet sources: always show Add a source, and say which radio is taken by what ([`7c403d53`](https://github.com/soum91/keystone/commit/7c403d538e699237c01ef2bdfd39ba4a76776eca); `Keystone/Router/RouterSources.swift`)
- Enforce visible installed version/build across app releases ([`36674d2d`](https://github.com/soum91/keystone/commit/36674d2db423e0912f557fed27277f7498117f4f); `.github/workflows/build.yml`, `.github/workflows/version-ui.yml`, `scripts/check_version_ui.py`, and 1 more)
- Internet sources: 'Automatic weight' wording ([`e6dc8e30`](https://github.com/soum91/keystone/commit/e6dc8e302230f7a4d1360d1dba1a775836a86641); `Keystone/Router/RouterSources.swift`)
- Show actual installed app version and build in UI ([`26f61c73`](https://github.com/soum91/keystone/commit/26f61c73be401811abbf2200848baa662b77703e); `Keystone/Views/DashboardView.swift`)
- Internet sources: note that links that can't connect are switched off ([`ca6518be`](https://github.com/soum91/keystone/commit/ca6518be3ee2dd1b3d97b757a959f8d6aa474c7d); `Keystone/Router/RouterSources.swift`)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/firmware-build-132...firmware-build-133)

## [build-38] - 2026-11-11

## Verified changes since build-37

- Add Tuya Wi-Fi power strip: Apple Home outlets + Keystone controls ([`d0cfd241`](https://github.com/soum91/keystone/commit/d0cfd24159ca55bd9956a38c1e7a900a9bf48e48); `Bridge/KeystoneBridge/Control.h`, `Bridge/KeystoneBridge/KeystoneBridge.ino`, `Bridge/KeystoneBridge/Strip.h`, and 5 more)

[Inspect exact code changes](https://github.com/soum91/keystone/compare/build-37...build-38)

This log records verified, release-specific changes. The [Factual release changelog](.github/workflows/release-changelog.yml) GitHub Action adds entries based on the actual commits between published releases. Entries are not fabricated for older versions that have not been audited.


## Unreleased — Tuya Smart / Surge setup diagnostics
- Open Tuya Smart instead of Smart Life from Keystone's QR login screens (with App Store fallback).
- Parse actual numeric Tuya DP mappings from more documented response shapes; retain cached DP codes.
- Verify the strip's LAN protocol and key before advertising outlet setup as successful, and show the detailed failure directly beneath the plug with a Copy action.
- Added manual read-only DP diffing to identify independently switched outlets; never treat every Boolean DP as a safe switch.
- Expanded the bridge's read-only probe beyond DP 7 to capture USB channels with larger DP IDs.

## Unreleased — Tuya QR session persistence
- Refresh the latest stored Tuya Smart token rather than reusing a stale view snapshot; coalesce concurrent refresh attempts and preserve credentials on failures.
- Add explicit Reconnect Tuya Smart (without clearing strip or Home devices) on the device-import and strip setup screens.
- Keep the rotating token in App Group private storage; the system does not depend on Safari cookies.
