# NATIVE-NET-01 / NATIVE-GAME-01 — Opt-in HTTPS and WebSocket game transport

**Status: source implementation, CI and Android device tests pending.** This is the *client-side communication foundation*, not a hosted game-server service. Existing signed Chappy Player **v0.3.0**, Stable Chappy Recorder **v0.1.0** and stable catalog are unchanged.

## Purpose and APIs

A mini-app must explicitly declare `"permissions":["network"]` in `manifest.json`. The installer labels this **暗号化サーバー通信**. The Flutter host asks for a session-level network permission and separately asks the user to approve each exact `scheme://host:port` destination. Approval lasts only while that mini-app is in the foreground.

```javascript
const health = await Chappy.network.request(
  'https://your-game.example.org/status', 'GET', '');
const joined = await Chappy.network.connect(
  'wss://your-game.example.org/room');
await Chappy.network.send(JSON.stringify({type:'join',room:'test'}));
const {connected, messages, dropped} = await Chappy.network.poll();
await Chappy.network.close();
```

Supported calls:

- `Chappy.network.request(url, method='GET', body='')` → `{status,text}`: HTTPS GET/POST, request body limited to **8KiB**, UTF-8 response to **64KiB**, redirects blocked, bounded connection/response timeouts, no custom auth headers.
- `Chappy.network.connect(url)` → `{connected:true,origin}`: one WSS connection per mini-app at a time, TLS verified against a public DNS hostname, WebSocket compression disabled, max **8KiB per inbound message**.
- `Chappy.network.send(text)` → boolean: text frames of 8KiB or less; max **20 calls per second**, no binary or arbitrary native commands.
- `Chappy.network.poll()` → `{connected,messages,dropped}`: drains at most 16 text frames. Buffered queue is capped at 64 frames; oldest frames are discarded with a visible drop count. Polling allows a simple text-only game input proof of concept; later phases should provide a true event stream with state synchronization.
- `Chappy.network.close()` → boolean: explicitly close the connection. Backgrounding, leaving the app or disposing the runner also closes the socket, cancels active HTTPS requests and clears the per-origin approval set.

## TLS, DNS and sandbox boundaries

- Only **https://** and **wss://**, default port 443 or explicit 443/8443/9443. The user sees and approves the *exact destination origin*. URLs with embedded user credentials, fragments, IP literals, local domains and malformed hostnames are refused.
- After origin approval, the client resolves DNS, rejects **any private, loopback, link-local, mapped, reserved or multicast address** and connects through a pinned socket factory to the approved public IP. The TLS library still validates the certificate for the original hostname. This avoids a second DNS lookup pointing to a different address during connection. HTTP proxies and redirects are disabled.
- The embedded WebView retains **CSP `connect-src 'none'`**; it cannot use `fetch`, arbitrary `WebSocket` or raw sockets itself. All network operations go through the Flutter broker's checks, with no OS system privileges added to untrusted JavaScript.
- The local page cannot launch native commands based on remote messages. A server message is a string only; the Game Server Lab renders it with `textContent`, not `innerHTML`. Remote JSON data never gains device control privileges.
- This is not server authentication beyond TLS: the game backend should implement its own user accounts/room tokens, anti-abuse and access control. Do not send passwords or private user files in raw chat messages.
- No plain FTP/SFTP, unrestricted LAN connections, background sockets, microphones/cameras controlled remotely, binary asset uploads or PC remote control in this stage.

## Demo mini-app and reference backend

`sample_apps/game_server_lab/index.html` packages as **Chappy Game Server Lab v0.1.0** with `network`, `motion` and `haptics` capabilities. Server URL fields begin empty and it **never connects automatically**. Manual buttons test WSS connect/send/poll/close, HTTPS GET/POST, sending a single gravity reading as JSON, and manually playing a tick haptic. Haptics never run as a result of remote commands. Logs remain in-memory in the mini-app page.

An optional **loopback-only Python game room server** is in `examples/game_server_demo/server.py`. It accepts bounded JSON ping, join, position state and gravity messages. The Android client cannot connect directly to loopback/private IPs; use a separately secured test domain, valid TLS and trusted WSS reverse proxy. The sample backend is **not** a public production server. See its README.

## Implementation/testing notes

- `lib/core/miniapp_game_network.dart` uses `dart:io` `HttpClient` and `WebSocket`, public-DNS resolution, an IP-pinned `connectionFactory`, strict TLS and bounded queues. One instance is owned by each foreground `AppRunnerPage`.
- No new Android platform channel, native library or dependency is needed for network in this phase: the existing manifest already includes `android.permission.INTERNET`; the user's per-mini-app network permission is separately validated.
- Tests: `test/miniapp_game_network_test.dart` (URL/IP/DNS and lifecycle), `tools/test_game_network_contract.py` (sandbox/security policy), `tools/test_game_server_example.py` (server message validator), `tools/test_game_server_lab.js` (manual user actions and background cleanup), `tools/test_bootstrap.js` (JS RPC), and package/catalog validation.
- The normal PR CI must pass Flutter analyze/test, all JS/Python tests and an actual Android debug APK build on the **exact** PR head. Android real-device QA is still needed for TLS certificate handling, DNS pinning, a genuine WSS server, reconnection, inbound flood, low connectivity, permission denial and pause/resume.
- **Stage limitation:** network protocol and backend example are not yet fully deployed, performance tested or production hardened. The next steps are production-grade user authentication, server-authoritative game state, controlled reconnect/backoff and eventual signed client release.

No automatic background network jobs or externally hosted server have been started by this PR.
