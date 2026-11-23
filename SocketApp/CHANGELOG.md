# Socket changelog

## Unreleased
- Added Socket SwiftUI dashboard and dynamic outlet status from Keystone /api/info.
- Added native Shortcuts actions for selecting a socket and switching all channels.
- Added app-specific scoped bridge pairing, Keychain persistence and a standalone IPA build workflow.
- Hardware datapoint mapping and first IPA build have not yet been verified.

## Upcoming Surge redesign
- Rename app display to Surge without changing the bundle identifier.
- Add branded app icon and automatic Keystone LAN discovery.
- Diagnose outdated firmware and distinguish the bridge address from the strip IP.
- Repair FlareStore publishing script's malformed URL validation.

## Icon restored
- Replaced the unrelated procedurally drawn icon with the original teal-neon smart power strip design.
- Xcode and FlareStore publish the same icon asset through the Surge release workflow.


## Unreleased — setup handoff
- Diagnose missing strip mapping without confusing it with Wi-Fi loss.
- Open Keystone's power strip setup from Surge and hide unusable Shortcuts until configured.
- Add one-tap multi-outlet setup beside the existing Smart Life plug in Keystone, using its existing Tuya login.
- Reject single-channel guesses and leave generic Apple Home controls untouched until the user decides otherwise.

## Tuya Smart cloud fallback
- QR account authorization and direct Tuya cloud channel control when Keystone is offline/unconfigured.
- iOS Keychain token storage, real Tuya switch-code detection, cloud-aware Shortcuts, safe All Off protection.
- Re-discover the paired Keystone bridge after DHCP changes and correct the stale-IP error message.
