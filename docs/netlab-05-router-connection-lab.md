# NETLAB-05 — Router Connection Lab (OpenWrt-only first adapter)

**Status:** Source prototype on a feature branch. No target router model has been supplied. Do not claim other retail routers work. Physical router↔Android connection, authentication and UI QA have **not run**. Game R8 remains in STATE/ROADMAP as the previous planned next batch, pending this priority change.

## Goal and expected output

On the user's **own managed OpenWrt router**, use the LuCI ubus JSON-RPC API to inspect the **currently tracked source-IP-to-destination-IP/port/protocol** entries of one **explicitly authorized device** (for example an Android phone). Unlike NETLAB-04A/B, which read only the user's **Windows PC aggregate bytes**, this phase reads the router's current connection tracking data. The target is an explicitly entered private IPv4, not a covert network sweep.

This does **not** reveal visited URLs, message contents, HTTPS payloads, phone apps, or prove a connection belongs to any named app. Device hostnames come from router-supplied DHCP hints and do **not** prove Android OS identity. Connections can be missing due to router offload, bridge mode, NAT, IPv6, VPN, DoH/Private DNS, upstream gateways and device sleep. HTTP/3 QUIC often uses UDP/443; that alone does not identify the service. No domain-to-IP attribution is implemented.

Relevant upstream OpenWrt LuCI definitions:
- [LuCI `getConntrackList` RPC definition](https://github.com/openwrt/luci/blob/master/modules/luci-base/root/usr/share/rpcd/ucode/luci)
- [LuCI status read ACL](https://github.com/openwrt/luci/blob/master/modules/luci-mod-status/root/usr/share/rpcd/acl.d/luci-mod-status.json)
- [OpenWrt ubus](https://openwrt.org/docs/techref/ubus)

## User flow (first adapter)

1. Owner installs/configures a supported OpenWrt LuCI/rpcd service on their own router. HTTPS is **mandatory**, not optional; LAN HTTP alone is unsupported. Use an independently verified TLS certificate **SHA-256 DER fingerprint** (64 lowercase hex after normalization).
2. Open Chappy Player main Android host → Network Lab → **管理ルーターの端末別接続先を確認（OpenWrt）**. Enter the router private IPv4, HTTPS port, TLS pin, LuCI **read-only** username/password, and an **approved target device IPv4**. The owner must check the affirmative authorization box.
3. Each request gets a **new explicit confirmation dialog** stating router/target address and destination-IP privacy scope. The host checks foreground, active Wi-Fi with no VPN/cellular route, as in NETLAB-04B. No scanning, ARP probing, mDNS trust, optional HTTP or public IP.
4. Dart `HttpClient` is configured with an **empty trust store** and a certificate fingerprint callback. The *actual response peer certificate* is also compared against the pin for each RPC. Redirects/proxies are denied. The only methods allowed are `session.login`, `luci-rpc.getDHCPLeases`, `luci.getConntrackList`. The RPC login requests a 60-second session. Credentials and session token live in method-local memory; not stored, logged or exported.
5. Up to 256 KiB of HTTPS JSON per response, a maximum of 1,200 conntrack records and 120 displayed distinct destinations. Only original-direction records whose `src` exactly matches the user-entered device IP are displayed; invalid addresses, ports, protocols and duplicate `protocol+destination+port` are skipped. DHCP hostname is optional. Aggregated stored packet contents, DNS logs or WAN browser history are not read.
6. The result appears only in trusted native Flutter host RAM. The user can clear it or request a new, separately consented one-shot session. App pause/lock/navigation away terminates the connection and clears the result; never backfill a history. No recurring task, background service, .chappy JS capability, or Stable/catalog publication.

## Router requirements and limitations

This specific adapter requires OpenWrt with LuCI's authenticated `/ubus` JSON-RPC, `luci.getConntrackList` and `luci-rpc.getDHCPLeases` and an HTTPS endpoint accessible from Android. A suitable narrowly scoped read-only `rpcd` user is strongly recommended; the app does not create/modify router ACLs. Some installed router versions, packages and ACL configurations may use different outputs or not expose these calls. **Lack of support must fail closed**.

*We do not know the user's router manufacturer/model*, so integration with NEC/Buffalo/TP-Link/UniFi/ASUS or their proprietary APIs is deliberately **not claimed**. A dedicated adapter requires the model/API and verification. No fallback to router HTML scraping with admin credentials; no plaintext HTTP or API token stored. If the user's router has no approved connection-table API, the UI should explicitly report unsupported rather than pretend the connections were recovered.

## Tests and release gates

- `test/router_connection_snapshot_test.dart`: target IP filtering, other-device isolation, invalid fields, duplicate suppression, bounded list, signed TLS pin inputs.
- `test/router_connection_lab_widget_test.dart`: no router request without owner affirmation and explicit action (UI and permission boundary).
- `tools/test_router_connection_boundary.py`: static regression to ensure no .chappy JS bridge, no HTTP fallback, no arbitrary router RPC methods, no auto-polling.
- CI: exact feature branch HEAD Quick CI and Android Debug ABI builds required before main merge; final handoff metadata update after merge.
- Physical QA: actual router HTTPS certificate verification, OpenWrt ACL response, multiple device source mapping, failure on wrong password/pin/route changes, Android pause/lock, IPv6 and hardware offloading behavior — **not run until the user provides a compatible router and tests it**.
- Prior NETLAB-04A/B and Game R8 code/plan, ASMR and other mini-apps remain unchanged. No Stable APK or published catalog update without separate approval.

## Planned next adapters

Obtain the actual router manufacturer/model/firmware and supported administrator API. Add a capability matrix for *device list*, *active connections*, *DNS name attribution* (only observed/available, never asserted), and *per-device bandwidth*. Do not conflate these data types or use unconsented deep packet inspection.
