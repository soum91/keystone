# Socket policy
- Application author/publisher: soum91. No private identity or credentials in source.
- Keep Socket app code isolated to SocketApp; Keystone owns all ESP32 firmware, OTA, HomeKit pairing and physical devices.
- Every release must display the actual installed version and build number; don't substitute the latest available version.
- Releases must describe evidenced changes and known limitations, never generic filler.
- Don't claim that a queued control command proves physical switching. Never guess an outlet's data point.
- Keep bridge tokens in iOS Keychain and limit Socket access to strip controls.
- For any future diagnostic report implement Copy with read-back verification, native Share and Save .txt via Files, selectable full text, and clear errors. Do not claim hardware tests without device validation.
