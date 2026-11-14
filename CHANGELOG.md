# Changelog

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

