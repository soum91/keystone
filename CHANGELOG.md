# Changelog

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

