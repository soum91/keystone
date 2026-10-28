# Keystone Bridge (Apple Home)

ESP32 firmware that puts your Tuya lights in Apple Home and runs the TV automations, with no HomePod, Apple TV, cloud or phone involved.

In Home you get:

- **Lights** from Afterglow: on, brightness, white temperature, colour, plus a **Lights Follow TV** switch.
- **Sony TV** tile (from Afterglow's TV settings): power, inputs, volume, and the Control Center remote (Bravia REST + IRCC; needs IP control with a pre-shared key).
- **Air purifier** from Exhale (Settings › Apple Home bridge): purifier tile with speed and auto/manual, PM2.5 air quality sensor, filter life, child lock, display switch. With Keep display off on in Exhale, the bridge turns the display back off whenever it comes on by itself.
- **IR remotes** from Redshift (Settings › Apple Home bridge): power as a switch, other buttons as one-tap buttons. IR can't report back, so the switch shows what was last sent.
- **Vizio sound bar** from Subwave.
- **Govee thermometer** (H5102 and similar) over Bluetooth, like a Govee gateway: temperature, humidity, battery. On first boot it picks the strongest Govee sensor it hears within 30 s; `@G` on the serial console picks again.
- **Vicohome camera** from Nightjar (Settings › Apple Home bridge): a Motion sensor, a Person sensor and the battery, from Vicohome's cloud every ~20 s, so expect 10 to 30 s of lag. Optional rule the bridge runs itself (no home hub needed): a person on camera turns chosen lights on, and they go off after a few quiet minutes. It can also push **ntfy alerts** (the ntfy iOS app shows the snapshot in the notification; tap opens Nightjar) when the camera sees a person, optionally checked by Claude first (flags someone right at the lens, touching or covering the camera, or at the food).

Firmware updates go over Wi-Fi from Afterglow › Settings › Apple Home bridge › Firmware, after the first USB flash.

## What you need

- An ESP32 (WROOM-32) dev board with USB, like the ideaspark one with the built-in OLED, on a USB charger. CI builds only plain ESP32 firmware; S3/C3 builds can be re-enabled in .github/workflows/bridge.yml
- A computer with Chrome or Edge, once, for flashing
- 2.4 GHz Wi-Fi, same network as the lights

## 1. Flash

Easiest: on a **computer** (Chrome or Edge on Windows, Mac, Linux or ChromeOS; phones can't do USB flashing) open **https://soum91.github.io/keystone/**, plug the board in, click **Connect and install**, pick the port, tick Erase on the first install. It picks the right firmware for your chip.

No port in the list:
- Swap the cable. Charge-only micro-USB cables are the number one cause.
- Boards with a CH340 USB chip (ideaspark and most cheap ESP32s) need the WCH driver on Windows ([CH341SER.EXE](https://www.wch-ic.com/downloads/CH341SER_EXE.html)); macOS mostly has it built in, otherwise [WCH's Mac driver](https://www.wch-ic.com/downloads/CH34XSER_MAC_ZIP.html).
- Stuck on "Connecting": hold BOOT, tap EN/RST, release BOOT, retry.

By hand: files are on [Releases](https://github.com/soum91/keystone/releases/tag/firmware-latest). `-full.bin` at `0x0` for a first install, `-app.bin` at `0x10000` to update without losing Wi-Fi and the Home pairing, using https://espressif.github.io/esptool-js/.

Boards with a built-in 0.96" OLED (like the ideaspark ESP32) show setup steps, the bridge's IP and live status on the screen.

## 2. Wi-Fi

Join the open network **Keystone-Setup** (the setup page pops up), or use the web installer's **Connect to Wi-Fi** over USB. Pick your 2.4 GHz Wi-Fi; the Apple Home code is `466-37-726` unless you set one.

## 3. Pair with Afterglow

Afterglow › Settings › Apple Home bridge. It finds the bridge on the network, pairs, and sends your lights (local keys and IPs stay on your Wi-Fi). Run **Find lights on Wi-Fi** first; only lights with a Wi-Fi address can be bridged. Whenever lights, scenes or automations change, the app resends on its own next time you open it.

## 4. Add to Home

Home app › + › Add Accessory › More options › **Keystone Bridge** › Add Anyway › setup code.

## TV automations

Set in Afterglow › Settings › TV & automations, run on the bridge:

- **TV off**: a scene (default all off), optionally only between two times, after a fixed delay or one it learns. Learning: when you switch a rule light off yourself within 20 min of the TV going off, that gap is recorded (last 9 kept); the delay is the median, 60 s until there are two. If you turn a light back on within 3 min of the bridge switching it off, it records that it should have waited longer. Turning the TV back on cancels the countdown.
- **TV on**: optional scene.
- **Late-night sweep**: all off at a set time unless the TV is on.

TV state comes from the Bravia REST API every 4 s; two "standby" answers (or three timeouts) in a row count as off.

## Sound bar (Subwave)

Since firmware 1.1 the bridge also switches a Vizio sound bar with the TV, set up from the [Subwave](https://github.com/soum91/subwave) app (Follow the TV). Subwave pairs on its own token, so it doesn't touch Afterglow's pairing.

- **TV off**: sound bar off after a delay you set (default 5 s), optionally only between two times. Turning the TV back on before then cancels it.
- **TV on**: optional, sound bar on.
- Over Wi-Fi it uses SmartCast's discrete power off/on (`/key_command/`, codeset 11), so it's safe even if the bar already followed the TV over HDMI-CEC. If the bar doesn't answer on Wi-Fi it's in deep standby, which counts as off.
- Over IR (through the Tuya blaster) the remote only has a power toggle, so a TV rule only presses it when Wi-Fi says the bar is in the wrong state, or, for bars not on Wi-Fi, when you turn on "Use IR power toggle" (only if the bar does not follow the TV by itself).
- In Home you get a **Sound Bar** switch and a **Sound Bar Follows TV** switch. Both appear after Subwave sends its first config (the bridge restarts once).
- If Afterglow has no TV set, the bridge uses the TV address from Subwave.

## Serial console (115200)

- `@i` lights, TV, learned delay, sound bar, recent events
- `@R` forget the paired phone (to pair a different one)
- `@G` forget the Govee thermometer and pick again
- `@B` forget the phone paired from Subwave
- `?` HomeSpan commands (Wi-Fi reset, unpair, factory reset)

## Notes

- Many bulbs accept only one local connection. The bridge never holds one open (connect, send, close), and polls each light every 15 s, so the app and Smart Life still work.
- Adding or removing lights restarts the bridge (about 20 s) so Home sees the change. Accessory IDs come from the Tuya device ID, so rooms you assigned in Home stick.
