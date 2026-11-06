# NETLAB-03A — PC ↔ Android one-session ownership confirmation preview

Status: SOURCE CANDIDATE; **NOT persistent pairing, authorization or a production feature**.

Related: [Issue #52](https://github.com/mibesamiti-png/chappy-player/issues/52), [Network Lab discovery](network-lab-discovery.md).

## What this actually proves

- A user manually starts Chappy Companion on their **own Windows PC**, selecting the pairing-preview mode. The PC creates a fresh, one-session ECDSA P-256 self-signed TLS certificate with the chosen private IPv4 address in its SubjectAlternativeName, and prints its **full SHA-256 certificate fingerprint** in the visible console.
- Windows advertises a temporary `_workstation._tcp.local.` service with the real TLS listener port. This service announcement is **not trusted**: devices on the LAN can forge service names.
- On Android, the trusted Network Lab UI lets the user select a discovered Chappy PC and enter the **full 64-hex fingerprint copied from the actual PC console**. It refuses public/unparsed IPs and fingerprints of wrong length. It initiates a TLS connection only from the foreground on a local Wi-Fi/Ethernet network.
- The Android TLS client checks the exact certificate fingerprint in `onBadCertificate` **and again from the peer certificate after connection**, even if the certificate would normally be CA trusted. The client sends no request data before a successful pin check. No fallback to plaintext or unpinned TLS.
- Android generates a cryptographically random 16-byte nonce and shows its SHA-256 digest's first **six hex characters** as a short, human comparison code. It sends the nonce inside the pinned TLS request. The PC prints the same code and accepts **only if the user explicitly types `YES` on that PC** within 25 seconds. Confirmation expires and the HTTPS listener closes afterwards; one claim per started session.
- The only response is the approved/denied state and the same nonce. The Android client verifies the nonce, response size and protocol. **No credential, authorization token, password or persisted pairing record is created.** No other API is exposed.
- The session has a max 10-minute default / 30-minute absolute start-window, max 256-byte request, 2KiB client response limit, 3s handshake timeout on PC, 6s connect timeout on Android, 25s user approval deadline and 35s client response deadline.
- Changing Android app lifecycle away from foreground cancels the socket; the PC server is in-process only and tears down the mDNS advertisement, cert/key and sockets on exit. The TLS private key is generated fresh and temp files are unlinked after loading.

## Windows steps (preview only)

1. Obtain `chappy-companion-windows-preview` from a **successful** Windows Companion Preview workflow run. It contains `ChappyCompanion.exe`, `Start-ChappyCompanion.cmd` and `Start-ChappyPairing.cmd`.
2. Extract files to a folder on your own Windows PC. On a trusted private LAN, **double-click `Start-ChappyPairing.cmd`**. Or run `ChappyCompanion.exe --start --pair --minutes 10` manually; optionally pass `--ip 192.168.x.x` to select the PC's intended private LAN adapter.
3. The console prints a temporary service name, IP, port and **64-hex fingerprint**. Keep the console open. If Windows Firewall prompts, allow only on a trusted **Private** network; never disable all firewall rules.
4. On a compatible Android debug build of Chappy Player, open Network Lab, choose **PC・ワークステーション**, tap 探索開始, approve the 15-second service scan, select the `Chappy PC...` entry, enter the **entire fingerprint** and tap **このPCとの接続を確認**.
5. Compare the six-character code on the phone with the one printed by the PC. Only if both match, type exactly `YES` on the PC within 25 seconds.
6. Android reports whether this **one** confirmation succeeded. PC closes the confirmation server; no future permission remains. Close the PC console after use.

**Security notes:** Never use a fingerprint provided only by an untrusted network announcement; take it from the physical PC console. A matching 6-digit code alone is NOT sufficient authentication; the independently entered full TLS fingerprint is required. A malicious device can advertise the same DNS-SD service name; that never bypasses the certificate pin. This prototype does NOT transfer files, control the PC, monitor other devices or save credentials. Windows executable is an unsigned CI preview; test only if you trust the source.

## Main development tests

- `python tools/test_windows_companion.py` — original inert beacon behavior and no-autostart.
- `python tools/test_windows_pairing.py` — 16-byte nonce cross-language digest vector, first-claim-only, invalid payload/denied/approved responses, TLS certificate SAN/fresh pin on Windows CI, and privacy/source guards.
- `flutter test test/companion_pairing_test.dart` — private-IP and full fingerprint validation, code vector and foreground UI behavior (no local sockets used by these unit tests).
- Source analysis, Android debug Kotlin build, plus Windows PyInstaller executable CI are separate gates; **no signed APK is released by this PR**.

## What remains before genuine authenticated pairing

- Human-friendly QR-based transfer of IP:port+full TLS fingerprint, protected against swapping QR targets.
- Real Windows/Android on-Wi-Fi test for mDNS, inbound TLS, firewall and code approval; accept/reject/timeout cases and Android lifecycle/pause.
- Persistent key establishment with mutual device authentication, secure credential storage and revoke UI. A one-time PC console approval is NOT equivalent to persistent trust.
- Capability-scoped, **read-only** PC network traffic metrics after those safeguards, with explicit approvals. PC control and file transfer remain out of scope.
- Android 17 target SDK 37+ privacy-preserving LAN picker. This preview fails closed at the trusted native capability gate when the current app targets 37+.

Do not publish a signed production APK or change Stable catalogs without explicit user instruction and device QA.
