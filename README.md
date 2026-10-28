# Keystone

Control panel for the Keystone Bridge, the ESP32 Apple Home bridge (firmware in [soum91/afterglow](https://github.com/soum91/afterglow/tree/main/Bridge)).

- **Home:** bridge status (online, Wi-Fi signal, uptime, firmware), room temperature and humidity from the Govee sensor, PM2.5 and purifier state, TV state with the TV-off countdown and learned delay, lights, sound bar, IR remotes, and the activity log. Toggles for "Lights follow the TV" and "Sound bar follows the TV".
- **Display:** a live preview of the bridge's OLED, plus screen on/off, brightness, upside down, which pages it cycles through (clock, room, air, lights, TV) and how fast, 24-hour clock, °C/°F, night mode (dim clock or screen off) and whether the TV-off countdown shows at night. "Flash the screen" makes the bridge say hello so you know which board is which.
- **Bridge:** rename it in Apple Home, firmware updates over Wi-Fi, network details, pairings with Afterglow/Subwave/Exhale/Redshift (reset any of them), re-pick the Govee sensor, restart, change Wi-Fi.
- **Widget:** room temperature and humidity, TV, lights on and PM2.5, small, medium and lock screen.

Pairing needs bridge firmware 1.4 or newer. Older bridges: update once from Afterglow › Settings › Apple Home bridge › Firmware.

## Build

Every push to `main` builds `Keystone-<version>-build-<N>.ipa` on GitHub Actions and publishes it as release `build-N` with a changelog. Sideload with AltStore, SideStore or Sideloadly (keep app extensions for the widget). FlareStore/AltStore source: `https://raw.githubusercontent.com/soum91/keystone/source/source.json`.

## Bridge firmware

The Keystone Bridge firmware lives in [`Bridge/`](Bridge/README.md) (moved here from soum91/afterglow). Every firmware change builds `KeystoneBridge-<chip>-build-<N>-{full,app}.bin` as release `firmware-build-N` and moves `firmware-latest`, which Keystone (and Afterglow) update from. Build numbers continue from the afterglow era (run + 100). The web installer is published to the `gh-pages` branch for https://soum91.github.io/keystone/.

