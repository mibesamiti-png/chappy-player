# Chappy Companion — Windows discovery beacon v0.1.0 (prototype)

A temporary, user-initiated mDNS/DNS-SD beacon (with an optional one-session pinned-TLS PC confirmation preview) which helps **Chappy Network Lab** find your own Windows PC on the same private Wi-Fi.

**What it does:** advertises a short-lived `_workstation._tcp.local.` service with a session-random name, private IPv4, and an ephemeral TCP port. By default, the inert TCP listener closes probes immediately and accepts **no commands, files, authentication tokens, telemetry, or raw packets**. With **explicit** `--start --pair`, a separate one-time, fingerprint-pinned TLS approval endpoint replaces the inert listener; it still accepts no commands, files, telemetry or credentials. It makes no outbound internet connection, has no autostart/Windows service, and stops by default after 10 minutes. It is **not** a persistently authenticated PC companion yet.

**What it does not do:** persist a paired relationship, show PC traffic, run PC commands, transfer files, expose private folders, monitor other devices, install a VPN, or automatically pair your phone. Those require separate design and consent.

## Windows usage

Preferred (no Python installation): download the artifact named `chappy-companion-windows-preview` from a **successful** [Windows Companion Preview GitHub Actions run](https://github.com/mibesamiti-png/chappy-player/actions/workflows/build-windows-companion.yml), unzip it to a folder on your own PC, and double-click `Start-ChappyCompanion.cmd`. The batch file **asks you to confirm** and then runs `ChappyCompanion.exe --start --minutes 10`. The console must remain open while advertising. You may stop early with Ctrl+C. This is a debug/preview artifact, not a formally signed installer; verify the source repository before executing an unsigned preview. We have **not** automatically run it on your PC.

Alternatively, with Python 3.11+ installed:

```powershell
py -m pip install -r examples/windows_companion/requirements.txt
py examples/windows_companion/companion.py --start --minutes 10
```

To select a specific adapter (Windows `ipconfig` shows its IPv4):

```powershell
py examples/windows_companion/companion.py --start --ip 192.168.1.20 --minutes 10
```

Only RFC1918 private IPv4 addresses (10/8, 172.16/12 and 192.168/16) are accepted. An IP must also be **assigned to the current PC**; binding fails safely otherwise. Automatic IP selection uses the outgoing interface and may pick the wrong adapter on a VPN/multi-network PC — use `--ip` when that happens. No raw socket capture or PC control port is opened.

## R5A PC→Android one-file receive preview

Use the opt-in `Start-ChappyFileOnceV3.cmd` script to select ONE existing 1-byte-to-4MiB regular local file BEFORE the PC starts a listener. With a fresh QR-v3 proof, PC must type `SEND` and Android must separately consent, verify SHA-256, and choose the save destination via the native picker. No PC directory listing, arbitrary path requests, remote control or automatic sync. This is a **Debug preview**; Windows↔Android physical test is pending. [Details](../../docs/pc-link-r5a-file-receive.md).

## R5B Android → Windows one-file upload preview

Use `Start-ChappyUploadOnceV3.cmd`: Windows owner selects a NEW local full destination path before starting the listener, then shares a fresh QR-v3 with Android's Network Lab. Windows requires normal QR-v3 YES **plus separate RECEIVE**. Android picks a file with a matching basename, validates a new upload-only P-256 signature, and separately consents. Strict 4 MiB limit, SHA-256, no overwrite, no shell, no directory listing or trust persistence. This remains **source/CI only**; two-device QA outstanding. See [R5B notes](../../docs/pc-link-r5b-upload-once.md).

## R4C opt-in real PC status preview

Use `Start-ChappyStatusOnceV3.cmd` only if you want a **single** read-only PC status inspection after a real QR-v3 mutual proof. PC must approve identity with YES, then independently type STATUS after Android requests the PC status. Android must separately consent again. CPU count, memory totals, uptime only; no file, remote control, traffic contents or persistent pairing. See [R4C notes](../../docs/pc-link-r4c-status-once.md). Actual physical Windows↔Android QA is still outstanding.

## New: QR-v3 mutual identity launch (R4A preview)

For the **current QR-v3 mutual-key proof**, do **not** use the older
`Start-ChappyPairing.cmd` (that launches QR-v2). Extract the latest successful
Windows Companion Preview ZIP and choose:

1. `Start-ChappyIdentitySetup.cmd` only if you deliberately want to create
   this Windows user's DPAPI-protected PC signing identity. Type `CREATE` when
   prompted. Existing identities are not silently replaced.
2. `Start-ChappyPairingV3.cmd` to check local prerequisites with
   `--doctor`, show warnings, request your acknowledgement and start
   `--start --pair --qr --identity-pair --minutes 10`.
3. `Start-ChappyKnownPhoneV3.cmd` only if you want to manually select a
   previously verified Android public fingerprint before starting QR-v3.
   A matching fingerprint does not bypass fresh mutual proof or consent.

`ChappyCompanion.exe --doctor` independently checks required modules, local
PC identity availability and candidate private IPv4, **without opening a
listening port, creating keys or printing secrets / IP / hostname**.
A successful local check does **not** establish that Wi-Fi, Windows Firewall
or Android pairing works. All PC and phone approvals remain mandatory.
Details: [R4A offline preflight and QR-v3 guide](../../docs/pc-link-r4-offline-readiness.md).

## Phone discovery

1. Connect Android and PC to the **same trusted private Wi-Fi/LAN**. Guest Wi-Fi, AP/client isolation and multicast filtering may prevent mDNS discovery.
2. Launch the Windows beacon manually and leave its console running.
3. On an Android debug build containing [Network Lab PR #53](https://github.com/mibesamiti-png/chappy-player/pull/53): Home → Network Lab → **PC・ワークステーション** → 探索開始 → 15秒間だけ探す.
4. Look for the name `Chappy PC <random>` with IP and temporary port. The random suffix changes each session. It is only a **discovery signal**, not a verified/paired PC; anyone sharing the LAN may observe the service and a different device could imitate it.
5. Close the console/press Ctrl+C or let the timer expire. Discovery advertisement is unregistered; no background agent remains.

Windows Defender Firewall may prompt about local Python/EXE network access; authorize only if the network is a trusted **Private** network and you intended to run the beacon. Do not disable the firewall or expose the beacon to the internet. Some Windows setups block mDNS UDP 5353 inbound; lack of discovery doesn't justify opening all ports.

## Developer testing

- `python tools/test_windows_companion.py` uses the Python standard library to test IP/name validation and explicit startup.
- The Windows CI workflow installs pinned `zeroconf`, constructs the real `ServiceInfo` in tests, and creates the **console EXE preview** using PyInstaller. CI does not prove real Android-to-Windows mDNS on a physical Wi-Fi network.
- No production Chappy Player APK, stable mini-app catalog or signing materials are changed by this preview.

## Next design milestone

Add mutual pairing and authenticated, encrypted PC status/traffic metadata with explicit PC and phone approval. **Never** infer trust merely from DNS-SD results; beacons can be spoofed. Then add an opt-in, read-only metrics view before any remote control.


## Optional: one-time PC identity confirmation (prototype)

Run `Start-ChappyPairing.cmd` instead of `Start-ChappyCompanion.cmd`, or execute `ChappyCompanion.exe --start --pair --minutes 10` explicitly. This creates a fresh TLS certificate and displays its **full SHA-256 fingerprint** on the PC console. From the compatible Android Network Lab preview, select the discovered Chappy PC, manually enter that **entire** fingerprint, and compare the six-character confirmation codes on both devices. Only if they match should the PC user type `YES`. Confirmation can be used once per PC launch and expires; no ongoing PC permission or stored pairing key results.

The basic `Start-ChappyCompanion.cmd` is still discovery-only and cannot complete a TLS pairing request. **Do not treat a service name or short confirmation code as identity evidence without the full TLS fingerprint copied from the PC display.**

Protocol details, Android 17 restrictions, threat model and QA: [NETLAB-03A one-session pinned TLS preview](../../docs/network-lab-session-pairing.md). Android APK source integration is not a published signed Android update. The preview EXE is also unsigned and needs owner-initiated local testing.


## QR code invitation (NETLAB-03B-1 preview)

The `Start-ChappyPairing.cmd` launcher now runs `ChappyCompanion.exe --start --pair --qr --minutes 10`. In this mode Windows displays a scannable **temporary QR code** in the console. Open Network Lab on Android, discover/select **Chappy PC ...**, tap **PCの招待QRをカメラで読み取る**, then aim at the QR on your *own physical PC screen*. The Android application refuses QR payloads with a different IP/port than the selected discovered PC.

The QR encodes a private LAN IP/port, the full freshly generated TLS certificate fingerprint, a fresh 128-bit invitation identifier, and an expiry timestamp (maximum 10 minutes). It is a short-lived secret: don't publish screenshots. Android validates its format, time, pin and discovery endpoint before sending a one-shot TLS request. Windows rejects missing, wrong, expired and repeated identifiers before prompting the PC user for the separate **YES** approval. The 6-character comparison code must still match on both devices.

For older builds without a QR reader, the legacy **manual fingerprint-only** preview is still available using `ChappyCompanion.exe --start --pair --minutes 10` (without `--qr`). QR mode never silently falls back to this older mode.

Windows console uses `chcp 65001` for the block-character QR. If the rendered QR is corrupted or the camera cannot read it, use the non-QR legacy preview instead. The first QR preview does **not** register persistent device keys, work in background, transfer files, or grant PC/phone access. A successful scan is not proof of persistent pairing.

See [QR security, expiry, device test and remaining work](../../docs/network-lab-qr-bootstrap.md).


## Offline Windows device identity foundation (NETLAB-03B-2)

The **optional** PC identity is separate from the temporary discovery beacon
and one-shot QR connection confirmation. It supports a future *mutually
authenticated* PC/Android pairing design, but **does not pair or reconnect
anything yet**.

From an extracted Windows preview artifact folder, run these in a console:

```powershell
.\ChappyCompanion.exe --identity-status
.\ChappyCompanion.exe --identity-create
.\ChappyCompanion.exe --identity-status
.\ChappyCompanion.exe --identity-revoke
```

`--identity-create` must be an **explicit** user action. It creates one
P-256 identity key protected with **Windows current-user DPAPI**, storing only
encrypted key material under `%LOCALAPPDATA%\ChappyCompanion`.
`--identity-status` displays the *public* SHA-256 fingerprint, not a secret.
`--identity-revoke` requires you to type exactly **REVOKE** and removes
the local key. Recreating it changes the fingerprint irreversibly.
Never move the encrypted identity file between PCs or put it on GitHub.

These identity commands do **not** advertise mDNS, open any listening port,
grant PC commands, access files, read traffic or silently trust a phone. The
existing `--start --pair --qr` still only approves one transient
confirmation and **does not consume or register** this new persistent identity.

On Android Debug, open **Network Lab → PC連携用の端末キーを準備・削除** to
independently prepare a key in Android KeyStore. No keys are shared between
devices yet. Real authenticated pairing and per-device revoke lists remain
future work in [the identity foundation design](../../docs/pc-link-identity-foundation.md).

## Previously verified Android key comparison (NETLAB-03B-6B preview)

After completing a QR-v3 mutual P-256 proof and **separately typing `SAVE`**
to store the phone's public key fingerprint in current-user DPAPI history,
you can manually compare that phone's identity in the *next* one-shot session.

```powershell
.\ChappyCompanion.exe --verified-list
.\ChappyCompanion.exe --start --pair --qr --identity-pair --compare-known-phone
```

Before creating a network listener, the console shows numbered previously
verified Android public-key fingerprints. Read the full fingerprint and type
`SELECT 1` (or the correct number). Empty/corrupted history or Enter cancels
**without advertising the PC**. The PC then displays a fresh QR-v3 invite.
A different phone key **claim** is rejected before the PC `YES` prompt;
an equal claim is **not authentication** and must still pass the fresh
Android private-key proof, PC approval and Android consent. There is no
automatic trust, stored access grant, PC control or remote key revocation.

To change phones or rotate a key deliberately, stop the current session, run
a new ordinary QR-v3 mutual verification, then choose whether to `SAVE` the
new public fingerprint and `--verified-forget` the old record. A saved
record is a history note only, not a paired or trusted device.

Full security boundaries and real-device QA to do:
[NETLAB-03B-6B Windows known-phone comparison](../../docs/pc-link-windows-known-phone-comparison.md).
