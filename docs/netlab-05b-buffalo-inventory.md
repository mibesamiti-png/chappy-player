# NETLAB-05B (partial): BUFFALO AirStation registered/unknown client inventory

**Status:** First BUFFALO-compatible **offline/manual-import** host UI implementation. This is not automatic router discovery, an official BUFFALO router API adapter, or real-time connection inspection. The user confirmed the router vendor is BUFFALO, but **has not supplied the exact model/firmware**, so capability detection, admin API compatibility, any per-device WAN flow attribution and physical QA remain blocked.

## User objective

The user wants to see other Android and other devices on the managed home router even when they **have not installed Chappy Player or enrolled/paird their devices**. This is an owner's device inventory/security-management function. The application must never claim that an unrecognized device is an intruder. "未登録" means only "not marked known *in this screen*." DHCP names/MAC/IP are not a validated Android OS identity; MAC randomization is common.

## Verified BUFFALO manufacturer guidance

- [BUFFALO FAQ 15741: check routers' attached devices via Device Control or Status → Client Monitor](https://www.buffalo.jp/support/faq/detail/15741.html)
- [BUFFALO official AirStation Android/iOS app](https://www.buffalo.jp/topics/special/detail/airstation-app.html)
- [BUFFALO FAQ 16150: find router IP via AirStation](https://www.buffalo.jp/support/faq/detail/16150.html)

These manufacturer instructions confirm device-list **viewing** on compatible router models. They do NOT document a stable public automated connection-tracking API for every BUFFALO model. Some routers are AP/bridge mode, and not all Ethernet/static-IP devices appear in every list.

## Implemented host-only UI

1. Android **Network Lab → BUFFALOの接続端末一覧（未登録機器も確認）**.
2. Owner opens BUFFALO's existing authorized Device Control / Client Monitor view, copies rows with LAN private IP and/or MAC, optionally a hostname. Paste e.g. `192.168.11.10, AA:BB:CC:DD:EE:01, FamilyPhone`. MAC-only and IP-only rows are supported; both may lack a user-supplied name.
3. Check **管理するBUFFALOルーターの一覧** and tap to parse.
4. Displays all parsed client rows, including never-enrolled/no-Chappy devices. Starts with all "未登録・要確認"; owner can mark identified MACs "既知にする" for this session. The UI counts unknown vs total. IP-only rows cannot be reliably marked known.
5. No data is saved; background, leaving/dispose, clear button discard the list and known flags. At most 32KiB pasted text, 256 lines, 128 parsed devices; only local RFC1918 IPv4 addresses and valid MAC fields; deduplicates; rejects ambiguous multiple-device rows, huge/unsafe names and HTML-like text.
6. No router credentials, HTTP or direct API access, stealth LAN scan, packet sniffing, DNS/SNI/HTTPS content, background monitor, mini-app JS permissions, or automatic uploads.

## Future automatic BUFFALO adapter (NOT IMPLEMENTED)

Required first: actual model number, firmware version, router/AP mode and what its management UI shows. Then research the model's supported read-only management interface. Do not guess undocumented admin URLs, request router passwords through plaintext HTTP, or silently scrape credentials. If the model has no supported read-only API, retain the authorized official management UI + local import method, and label it manual.

Per-device destination-IP/port tracking is separate from mere client inventory and cannot be inferred from the client-list data. It should only be added with a validated owner-controlled routing/firewall telemetry API, appropriate network governance and clear privacy boundaries. Existing OpenWrt-only NETLAB-05A adapter remains separate, not falsely treated as BUFFALO-compatible.

## Test and verification gates

- `test/buffalo_client_inventory_test.dart`: parser fixtures, unregistered device support, malformed/huge data, private IP only, deduplication, optional MAC and IP.
- `test/buffalo_inventory_widget_test.dart`: no action before management consent; unknown and known UI stay in RAM.
- `tools/test_buffalo_inventory_boundary.py`: offline-only, host-only security contract.
- Quick CI and Android Debug 3 ABI on exact implementation HEAD; physical BUFFALO router/Android and package installation remain **not run**.
- Game R8 eight tasks retained for later. NETLAB-04A/04B, OpenWrt NETLAB-05A, ASMR and Stable signed releases remain unchanged.
