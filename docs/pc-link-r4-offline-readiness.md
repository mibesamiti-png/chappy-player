# PC Link R4A — offline preflight and explicit QR-v3 launch UX

**Status: implementation + CI preview; real Windows↔Android QR-v3 pairing remains unverified.**

## Why

The existing `Start-ChappyPairing.cmd` explicitly starts the older QR-v2 ownership
confirmation. Developers otherwise need to remember several QR-v3 command flags.
This batch adds safer QR-v3 entrypoints while **preserving** the QR-v2 launcher,
existing cryptographic protocol and all consent requirements.

## New Windows preview launchers

| File | Purpose | Network or key side effects |
| --- | --- | --- |
| `Start-ChappyIdentitySetup.cmd` | Manually create a Windows user DPAPI-protected PC signing identity after typing exactly `CREATE` | No network, never overwrites existing key |
| `Start-ChappyPairingV3.cmd` | Run local offline preflight, show warnings, require console confirmation, then explicitly start one QR-v3 session | Starts temporary LAN listener only after confirmation and passing preflight |
| `Start-ChappyKnownPhoneV3.cmd` | Same QR-v3 flow, with explicit selection of a previously verified Android public fingerprint | Never auto-selects or auto-trusts phone; still requires both proofs and both approvals |
| `Start-ChappyPairing.cmd` | **Unchanged**, legacy QR-v2 session | Must not silently upgrade/downgrade |

These are shipped in **Windows Companion Preview** CI artifacts, not bundled
into a newly published Android APK or Windows installer.

## Offline doctor (`ChappyCompanion.exe --doctor`)

Checks these without advertising mDNS, opening a server listener, writing files
or generating identity keys:

1. The required `zeroconf`, `cryptography` and `qrcode` imports are available.
2. A PC identity key is readable for this Windows user. No fingerprint or secret
   is printed.
3. A candidate private IPv4 adapter exists. No IP address is printed.

Diagnostics use fixed `PC-DOCTOR-*` codes, no raw exception message, hostname,
device ID or IP. Exit code 0 means these **local** prerequisites are ready;
exit code 1 means they need attention, and exit code 2 means invalid mixed CLI
options. Doctor cannot verify the Windows firewall, Android LAN permission,
mDNS propagation, adapter choice on a multi-homed PC, TLS reachability or any
real-phone handshake. It is not a permission grant or connection attempt.

**Windows steps before physical QA**:

1. Download the **new** `chappy-companion-windows-preview` artifact from a
   successful Windows Companion Preview workflow run; extract the complete ZIP.
2. If this Windows user has no PC key, run
   `Start-ChappyIdentitySetup.cmd`, inspect the prompt and type `CREATE`.
3. Run `ChappyCompanion.exe --doctor` or use
   `Start-ChappyPairingV3.cmd`. If doctor fails, do not start the listener.
4. On an Android Debug host with QR-v3, open Network Lab and discover the
   temporary `Chappy PC ...` advertisement, then scan its fresh QR. Ensure
   the selected PC private IP and port match the QR.
5. Only approve matching short codes on **both** devices. PC user types
   `YES`; Android user approves the independent phone signature. Optional
   save-to-history is another explicit choice; history is **not** a connection
   permission or a reusable session token.
6. Stop the preview or allow its short-lived lifetime to expire. A new QR
   and fresh consent are required on the next run.

No new file transfer, computer control, persistent trusted session, device
surveillance or background connection is added in this batch.

## Tests

- `python3 tools/test_pc_link_readiness.py`: success, missing modules/key/LAN,
  malformed fingerprint, no raw local/private data, no listener with `--doctor`,
  invalid CLI combinations, launcher QR-v3 flags, no auto-keygen.
- Flutter widget test ensures Android's pairing page identifies the new Windows
  launchers and does not treat instructions as successful verification.
- Quick CI runs Flutter/unit and the new offline preflight suite.
- Windows Companion Preview CI runs the same suite and packs all three new
  launchers into the EXE artifact, then checks the frozen EXE's offline
  `--doctor` startup.

Future step: finish authenticated, capability-scoped session and **separately
approved** read-only PC status. Do not treat successful QR-v3 identity
verification as granting those capabilities. Real 2-device QA matrix remains
`docs/pc-link-two-device-qa-matrix.md`; it still has no PASS assertions.
