# Network R7 — Browser and one-shot network diagnostics (Debug preview)

Status: **implementation and CI candidate; physical Android QA NOT RUN.** The host browser is not a production-hardened general web browser. This specification distinguishes what code tests prove from device behavior and platform limitations.

## 1. Scope / entry

- A new R7 browser is launched *only* by the Android Chappy Player trusted host: Home → Browser (R7 preview) or Network Lab → Browser. It does not run on app startup, and there is no new mini-app network/browser/PC bridge.
- Input: a manually typed public HTTPS DNS name. Scheme is prefixed with https only when absent. Back/forward/reload are user actions. No bookmarks, remote history, URL telemetry, downloads, external apps or automatic page launch.
- URL validation denies non-HTTPS schemes (including http, file, data, javascript, intent, content, blob), username/password in URL, non-443 ports, IP literal, localhost and common LAN/private development suffixes, malformed host/whitespace/backslashes, and oversized URLs. Redirected top-level navigations use the *same* preflight and are blocked rather than upgraded.
- JavaScript defaults OFF and requires a separate foreground consent to enable *only for the current browser session*. Site permission requests (camera/microphone/etc.) are always denied. No ChappyHost or mini-app JS channel is injected into this browser.
- On app backgrounding or page disposal, the host ends the active session, requests about:blank, disables JS and drops its view. Resuming is not an automatic navigation.

## 2. Browser security boundaries and known limitations

1. **Important:** Flutter webview_flutter 4.13.1 does not provide a complete subresource/JavaScript fetch filter, a public-DNS pinning guarantee, or a per-WebView Android cookie partition. The host URL preflight is **not** a DNS-rebinding firewall, not a complete LAN access ban for all subrequests, and not a security sandbox against all malicious websites. Hence JavaScript is opt-in; use only trusted sites. Do not advertise it as an unrestricted safe browser.
2. The Android WebView cookie jar and cache may be shared with .chappy embedded WebViews. Clearing them is explicitly confirmed and may log the user out of mini-app websites. Never claim independent storage or silent automatic deletion. Cache, local storage and global WebView cookies are cleared on manual approval; the current native navigation controller is then replaced with a fresh one. Other platform/browser storage and OS-level records are not claimed to be wiped.
3. No JavaScript channel is added, no browser capability appears in local_app_server.dart, AppRunnerPage or the .chappy manifest permissions. The original optional app.network HTTPS/WSS API remains separate, as does the existing 15-second approved DNS-SD LAN discovery.
4. Top-level HTTP and direct LAN IP navigation are denied in this R7 preview; a later LAN Web UI is a separate, consented feature with separate threat review. File downloads, popup windows, custom Android intents, device camera/mic and browser uploads are not advertised as supported here.

## 3. One-shot network diagnosis

- Only Network Lab → Network connection diagnostic, then a **second user-initiated confirmation** starts the test. Opening the page performs zero DNS/HTTP requests.
- Stage 1: count non-loopback active interfaces using dart:io; drop all names, addresses and network identifiers.
- Stage 2: resolve only the fixed public DNS hostname `example.com`, timeout 5 seconds.
- Stage 3: a single HEAD request to fixed `https://example.com/` (no redirect following, no response body, no WebView cookies), with bounded waits. Note that the hostname can require additional DNS resolution internally.
- Report only interface count, success/failure of DNS and HTTPS, and HTTPS status code. Raw IP addresses, credentials, response body, request/redirect URLs and verbose errors are not shown or logged. The remote site can still observe the source IP for this request.
- Cancellation, app backgrounding and page disposal cancel the HTTP client or ignore in-flight results. The current run never auto-retries, polls or scans a subnet. Ordinary DNS resolution cancellation depends on the OS; stale results are discarded.
- No background job, VPN, privileged OS service, full network packet capture, LAN sweep, shell command or PC keystroke.

## 4. Browser Lab — private manual QA only

- Source: `sample_apps/browser_lab`; package: `local.chappy.browser_lab` v0.1.0, generated manifest `permissions: []`.
- Manual checklist has 12 items: browser entry, public HTTPS, rejected URL schemes/hosts, back/forward/reload, opt-in JS and lifecycle, WebView media denial, explicit shared-cookie warning, diagnostic idle, approved diagnosis, cancellation/backgrounding, offline, mini-app bridge isolation.
- The checkboxes do not perform browsing or networking; their copyable report only contains case IDs and checked status. No durable storage or automatic QA pass report.
- The existing Game Server Lab is **unchanged**; it has its own HTTPS/WSS consent flow and cannot invoke this new host-only diagnosis.

## 5. Test evidence / release constraints

- Pure Flutter tests: `test/browser_url_policy_test.dart` and `test/network_diagnostic_service_test.dart` plus `test/network_diagnostic_page_widget_test.dart` (separate approval, cancel, no background replay). Existing Network Lab widget tests also check the new entry controls.
- Python static boundary: `tools/test_network_r7_boundary.py`; Browser Lab zero-permission packaging: `tools/test_browser_lab.py`; offline UI simulation: `tools/test_browser_lab.js`. Quick CI packages the private .chappy preview without public catalog publication.
- Compatibility APK workflow produces separately verified ARM64, ARM32 and x86-64 **Debug** APK artifacts when the PR's final HEAD passes. CI-only tests cannot prove Android WebView rendering, permission prompts, DNS behavior on Wi-Fi, or physical browser UX.
- Physical Android QA remains **0/12 NOT RUN** until the user tests an installed APK and records evidence. The unrelated PC Link physical QA stays **0/15** and media-key **0/13** NOT RUN. Signed Stable publishing and public app catalog updates are not authorized by R7.

## 6. Next steps after source/CI R7

- Physical 12-case Android/OS QA and review of shared-cookie behavior across multiple mini-apps.
- Browser-grade DNS pinning / subresource requests, per-profile WebView isolation, private LAN web UI, site downloads and JavaScript ergonomics need a separate design/review before expanding the preview; do not claim those are implemented.
- Later Game Server R8 should preserve its own explicit consent, rather than granting blanket LAN access or silently opening WSS sessions.
