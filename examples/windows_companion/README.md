# Chappy Companion — Windows discovery beacon v0.1.0 (prototype)

A temporary, user-initiated mDNS/DNS-SD beacon which helps **Chappy Network Lab** find your own Windows PC on the same private Wi-Fi.

**What it does:** advertises a short-lived `_workstation._tcp.local.` service with a session-random name, private IPv4, and an ephemeral TCP port. The TCP listener closes probes immediately and accepts **no commands, files, authentication tokens, telemetry, or raw packets**. It makes no outbound internet connection, has no autostart/Windows service, and stops by default after 10 minutes. It is **not** an authenticated PC companion yet.

**What it does not do:** show PC traffic, run PC commands, transfer files, expose private folders, monitor other devices, install a VPN, or automatically pair your phone. Those require separate design and consent.

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
