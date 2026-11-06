# NETLAB-00/01 — Chappy Network Lab DNS-SD discovery MVP

Status: SOURCE CANDIDATE ONLY. Android physical-device QA and signed production release are NOT done.

Related: [Issue #52](https://github.com/mibesamiti-png/chappy-player/issues/52) / [Notion roadmap](https://app.notion.com/p/410948b74937818f8eeaca22609052b2).

## Implemented

- The trusted Flutter host home screen opens Chappy Network Lab. This is NOT exposed to third-party .chappy HTML/JS.
- Every scan requires a manual tap on 探索開始 followed by a confirmation: 15秒間だけ探す. Exactly one fixed DNS-SD type is selected: HTTP (_http._tcp.), Windows/Linux workstation (_workstation._tcp.), or printer (_ipp._tcp.).
- Android NsdManager discovers advertised services and resolves an IP address/port when possible, WITHOUT opening a socket to a target. At most 24 services are shown and scanning stops after 15 seconds.
- An explicit Stop button ends discovery. On Activity pause/destroy results are cleared; the Flutter page also stops discovery when closed or backgrounded.
- Wi-Fi or Ethernet connection required. On older devices, temporary Wi-Fi multicast lock is released upon stop and pause.
- Android 17 / API 37 when targetSdk >=37: discovery deliberately fails closed until the privacy-preserving FLAG_SHOW_PICKER service picker is compiled and tested for the target API. No ACCESS_LOCAL_NETWORK permission is requested.
- No packet capture, router credentials, automatic background monitoring, general LAN scanning, arbitrary PC control or remote WebView access.

## Architecture

- tools/android/NativeNetworkDiscovery.kt — NSD lifecycle, fixed types, scan size/time limits.
- tools/android/MainActivity.kt — separate trusted dev.chappy.player/network_lab MethodChannel requiring foreground Activity.
- lib/core/lan_discovery_client.dart — typed start/snapshot/stop adapter.
- lib/screens/network_lab_page.dart — consent, scan selection, polling and results.
- lib/main.dart — host-only entry point.
- tools/patch_android.py — native class install + normal ACCESS_NETWORK_STATE and CHANGE_WIFI_MULTICAST_STATE permissions.
- test/network_lab_page_widget_test.dart; tools/test_network_lab_contract.py — consent, cleanup, and non-exposure tests.

The existing Chappy.network publicly routed HTTPS/WSS game transport is unchanged: do not relax its public IP/DNS/TLS checks for LAN features.

## Physical device validation checklist

1. Join a network you own/manage. Ensure a PC or printer advertises a supported DNS-SD service; Wi-Fi alone is not enough.
2. Home → Network Lab → select type → 探索開始 → 15秒間だけ探す. Check displayed names and, if resolved, IP/port.
3. Verify manual Stop, fifteen-second automatic stop, app pause/lock, and closing the page all cease discovery.
4. Verify unadvertised devices remain absent, guest-isolated networks find nothing, Wi-Fi absence produces an error, and Android 17 target-37 restrictions fail safely.
5. Confirm existing file imports, saved media, .chappy execution and updater have not regressed. Never uninstall the permanently signed production APK as a debug shortcut.

## Known limitations and follow-up

- This finds services that participate in DNS-SD, not all local devices. Windows PCs often need an advertising service/companion.
- Access point isolation, multicast filtering and device DNS-SD behavior affect discovery. IP/port may be unresolved.
- Real Android NSD results, permission behavior and connectivity changes are not proven by CI.
- Android 17 picker, Windows companion/service advertisement, authentication, router metrics, self-device throughput, authorized PC traffic metadata, own-device VPN diagnostics, and signed release are still unimplemented.
