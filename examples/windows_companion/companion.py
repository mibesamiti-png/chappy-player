"""Chappy Companion: opt-in Windows LAN discovery beacon (no PC control).

Starts only with --start. Default is still an inert DNS-SD beacon.
With explicit --pair, exposes one pinned-TLS PC-approved confirmation exchange;
it grants no persistent device trust, command execution, packet capture,
file transfer, credential store, or background service.
"""

from __future__ import annotations

import argparse
import ipaddress
import re
import secrets
import socket
import sys
import time
from contextlib import closing

SERVICE_TYPE = "_workstation._tcp.local."
MAX_MINUTES = 30
DEFAULT_MINUTES = 10
LAN_RANGES = tuple(
    ipaddress.ip_network(block)
    for block in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
)


def validate_lan_ipv4(value: str) -> str:
    """Reject public, loopback, link-local and documentation addresses."""
    try:
        ip = ipaddress.ip_address(value)
    except ValueError as exc:
        raise ValueError("A numeric private IPv4 address is required") from exc
    if not isinstance(ip, ipaddress.IPv4Address) or not any(
        ip in network for network in LAN_RANGES
    ):
        raise ValueError("Choose an IPv4 address on your private Wi-Fi/LAN")
    return str(ip)


def discover_local_ipv4() -> str:
    """Choose an existing outbound private IPv4; UDP connect sends no packet."""
    candidates: list[str] = []
    with closing(socket.socket(socket.AF_INET, socket.SOCK_DGRAM)) as probe:
        try:
            probe.connect(("192.0.2.1", 9))
            candidates.append(probe.getsockname()[0])
        except OSError:
            pass
    try:
        candidates.extend(
            info[4][0]
            for info in socket.getaddrinfo(
                socket.gethostname(), None, socket.AF_INET, socket.SOCK_STREAM
            )
        )
    except OSError:
        pass
    for item in candidates:
        try:
            return validate_lan_ipv4(item)
        except ValueError:
            continue
    raise ValueError(
        "No private LAN IPv4 found; run ipconfig and supply --ip 192.168.x.x"
    )


def service_identity(nonce: str) -> tuple[str, str]:
    """One-session randomized name; never publish the actual Windows hostname."""
    if len(nonce) != 8 or any(char not in "0123456789abcdef" for char in nonce):
        raise ValueError("Invalid ephemeral service identifier")
    return (
        "Chappy PC " + nonce + "." + SERVICE_TYPE,
        "chappy-" + nonce + ".local.",
    )


def service_descriptor(ip: str, port: int, nonce: str) -> dict[str, object]:
    validate_lan_ipv4(ip)
    if not (1 <= port <= 65535):
        raise ValueError("Invalid service port")
    name, server = service_identity(nonce)
    return {
        "type_": SERVICE_TYPE,
        "name": name,
        "server": server,
        "addresses": [socket.inet_aton(ip)],
        "port": port,
        "properties": {b"app": b"chappy", b"mode": b"discovery-only"},
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Chappy PC discovery beacon (visible, temporary, no control)"
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--traffic-export", action="store_true",
        help="Export approved local PC traffic counters to a NEW JSON; no listener",
    )
    mode.add_argument(
        "--doctor", action="store_true",
        help="Offline QR-v3 preflight: no listener, no key creation, no secrets",
    )
    mode.add_argument(
        "--start", action="store_true",
        help="Explicitly advertise this PC on the current private LAN",
    )
    mode.add_argument(
        "--identity-create", action="store_true",
        help="Create one current-user DPAPI protected P-256 PC identity (NO pairing)",
    )
    mode.add_argument(
        "--identity-status", action="store_true",
        help="Display public PC identity fingerprint (never the private key)",
    )
    mode.add_argument(
        "--identity-revoke", action="store_true",
        help="Explicitly DELETE this PC's local identity after typed confirmation",
    )
    mode.add_argument(
        "--verified-list", action="store_true",
        help="Show only manually stored, DPAPI-protected verified phone fingerprints",
    )
    mode.add_argument(
        "--verified-forget", metavar="PHONE_SHA256",
        help="Locally delete one verified phone history record after typed FORGET",
    )
    mode.add_argument(
        "--verified-clear", action="store_true",
        help="Locally erase ALL verified phone history after typed CLEAR (keep PC identity)",
    )
    parser.add_argument(
        "--ip", help="Private IPv4 of this PC's selected Wi-Fi/LAN adapter",
    )
    parser.add_argument(
        "--pair", action="store_true",
        help="Use short-lived, fingerprint-verified TLS PC approval instead of an inert beacon",
    )
    parser.add_argument(
        "--qr", action="store_true",
        help="With --start --pair, show an expiring, one-time QR pairing invitation",
    )
    parser.add_argument(
        "--identity-pair", action="store_true",
        help="Explicit QR-v3 mutual device key proof (requires --start --pair --qr)",
    )
    parser.add_argument(
        "--status-once", action="store_true",
        help="Opt in to one separately approved read-only PC status after QR-v3",
    )
    parser.add_argument(
        "--traffic-read-once", action="store_true",
        help="Owner-operated PC, signed QR-v3, one-time traffic counters",
    )
    parser.add_argument(
        "--traffic-read-seconds", type=int, default=10,
        help="With --traffic-read-once only, 5-30 seconds (default: 10)",
    )
    parser.add_argument(
        "--media-once", action="store_true",
        help="One separately consented multimedia key over signed QR-v3",
    )
    parser.add_argument(
        "--receive-file-once", action="store_true",
        help="One Android file to an explicit NEW PC destination via fresh QR-v3",
    )
    parser.add_argument(
        "--send-file-once", action="store_true",
        help="Share only ONE PC-selected 4 MiB file after a new QR-v3 proof",
    )
    parser.add_argument(
        "--compare-known-phone", action="store_true",
        help="Manually choose a saved DPAPI phone fingerprint BEFORE QR-v3; "
             "no auto-trust, still requires PC YES and mutual proof",
    )
    parser.add_argument(
        "--traffic-seconds", type=int, default=10,
        help="With --traffic-export: 5-30 seconds (default 10)",
    )
    parser.add_argument(
        "--traffic-out", help="With --traffic-export: new JSON file path",
    )
    parser.add_argument(
        "--minutes", type=int, default=DEFAULT_MINUTES,
        help="Automatic stop after 1–30 minutes (default: 10)",
    )
    return parser


def run_beacon(ip: str, minutes: int) -> None:
    """Publish only a DNS-SD PTR/SRV/TXT/A and close all incoming TCP probes."""
    from zeroconf import IPVersion, ServiceInfo, Zeroconf

    address = validate_lan_ipv4(ip)
    if not 1 <= minutes <= MAX_MINUTES:
        raise ValueError("Duration must be between 1 and 30 minutes")

    # The advertised port is real but intentionally has no control protocol.
    with closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as listener:
        listener.bind((address, 0))
        listener.listen(4)
        listener.settimeout(0.3)
        port = listener.getsockname()[1]
        nonce = secrets.token_hex(4)
        info = ServiceInfo(**service_descriptor(address, port, nonce))
        zeroconf = Zeroconf(interfaces=[address], ip_version=IPVersion.V4Only)
        registered = False
        try:
            zeroconf.register_service(info, allow_name_change=False)
            registered = True
            print("Chappy Companion discovery ON")
            print("LAN IP: " + address + " / temporary port: " + str(port))
            print("Advertised: " + info.name)
            print("Only presence is announced. No commands or files are served.")
            print("Automatically stops in " + str(minutes) + " minute(s).")
            print("Press Ctrl+C to stop earlier.")
            stop_at = time.monotonic() + 60 * minutes
            while time.monotonic() < stop_at:
                try:
                    connection, _ = listener.accept()
                    # Peer probes are not authenticated and get no response.
                    connection.close()
                except socket.timeout:
                    continue
        finally:
            try:
                if registered:
                    zeroconf.unregister_service(info)
            finally:
                zeroconf.close()
            print("Chappy Companion discovery OFF")


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if not 5 <= args.traffic_read_seconds <= 30 or (
        not args.traffic_read_once and args.traffic_read_seconds != 10
    ):
        print("Traffic read duration must be 5-30s and requires --traffic-read-once", file=sys.stderr)
        return 2
    if args.traffic_export:
        if (args.start or args.pair or args.qr or args.identity_pair or args.ip
                or args.compare_known_phone or args.status_once
                or args.media_once or args.traffic_read_once or args.receive_file_once or args.send_file_once
                or args.minutes != DEFAULT_MINUTES
                or not 5 <= args.traffic_seconds <= 30):
            print("Traffic export is separate from PC Link; 5-30s only",
                  file=sys.stderr)
            return 2
        from pathlib import Path
        from pc_traffic_export import capture, suggested_filename, write_report
        print("This PC only: aggregate traffic for ALL interfaces, not just Wi-Fi.")
        print("No network listener, no other devices and no packet contents.")
        try:
            answer = input("Type TRAFFIC to capture THIS PC now: ").strip()
            if answer != "TRAFFIC":
                print("Cancelled without capture.")
                return 2
            output = (Path(args.traffic_out) if args.traffic_out
                      else Path.cwd() / suggested_filename())
            report = capture(samples=args.traffic_seconds)
            write_report(report, output)
            print("Saved local report: " + str(output))
            print("Manually copy it to Android, then import in Network Lab.")
            return 0
        except (OSError, ValueError, RuntimeError, EOFError, ImportError):
            print("Traffic export failed; no data uploaded.", file=sys.stderr)
            return 1
    if args.traffic_out is not None or args.traffic_seconds != 10:
        print("Traffic output options require --traffic-export",
              file=sys.stderr)
        return 2
    if args.doctor:
        if (args.pair or args.qr or args.identity_pair or
                args.compare_known_phone or args.status_once or args.send_file_once or args.receive_file_once or args.media_once or args.traffic_read_once or args.ip or
                args.minutes != DEFAULT_MINUTES):
            print("--doctor cannot be combined with network options",
                  file=sys.stderr)
            return 2
        from pc_link_readiness import doctor
        return 0 if doctor() else 1
    if (args.identity_create or args.identity_status or args.identity_revoke
            or args.verified_list or args.verified_forget is not None
            or args.verified_clear):
        if (args.pair or args.qr or args.identity_pair or args.compare_known_phone or args.status_once or args.send_file_once or args.receive_file_once or args.media_once or args.traffic_read_once or args.ip
                or args.minutes != DEFAULT_MINUTES):
            print("Identity commands cannot be combined with network options",
                  file=sys.stderr)
            return 2
        try:
            from windows_identity import (
                create_identity, identity_status, revoke_identity,
            )
            if args.verified_list:
                from verified_phone_history import list_verified_phones
                rows = list_verified_phones()
                print("Previously QR-v3 verified phones (LOCAL HISTORY ONLY):")
                for row in rows:
                    print(row["fingerprint"] + "  verified_at=" +
                          str(row["verified_at"]))
                if not rows:
                    print("None saved.")
                print("No automatic pairing, remote control or connection.")
            elif args.verified_clear:
                from verified_phone_history import clear_verified_phone_history
                print("WARNING: All previously verified phone PUBLIC fingerprints")
                print("will be removed from this Windows user account.")
                print("PC signing identity will NOT be revoked or rotated.")
                print("This will NOT contact, disconnect or revoke a remote phone.")
                try:
                    answer = input("Type CLEAR to erase ALL local verification history: ")
                except (EOFError, OSError):
                    print("No changes made.")
                    return 2
                if answer.strip() != "CLEAR":
                    print("No changes made.")
                    return 2
                clear_verified_phone_history()
                print("Local verification history cleared; PC identity unchanged.")
            elif args.verified_forget is not None:
                from verified_phone_history import (
                    list_verified_phones, forget_verified_phone,
                )
                fp = args.verified_forget
                if re.fullmatch(r"[0-9a-f]{64}", fp) is None:
                    print("Expected 64 lowercase hex characters", file=sys.stderr)
                    return 2
                if not any(row["fingerprint"] == fp
                           for row in list_verified_phones()):
                    print("No matching verification history found.")
                    return 0
                print("This removes only local public fingerprint history.")
                print("Phone SHA-256: " + fp)
                if input("Type FORGET to remove this history record: ").strip() != "FORGET":
                    print("No changes made.")
                    return 2
                forget_verified_phone(fp)
                print("Local fingerprint history removed; no remote action.")
            elif args.identity_status:
                public_id = identity_status()
                print("PC identity fingerprint (SHA-256 public key): " +
                      (public_id or "NOT CREATED"))
                print("No phone is paired. No network service started.")
            elif args.identity_create:
                public_id = create_identity()
                print("PC identity created (current Windows user DPAPI).")
                print("Public SHA-256 fingerprint: " + public_id)
                print("No phone is paired. No network service started.")
            else:
                print("WARNING: This deletes the local PC signing identity")
                print("AND its current-user verified-phone fingerprint history.")
                print("The old key cannot be recovered; a new key has a NEW")
                print("public fingerprint and requires fresh QR-v3 verification.")
                print("Android device keys and Android-side history are NOT")
                print("changed or remotely revoked by this local operation.")
                answer = input("Type REVOKE to remove the PC identity: ").strip()
                if answer != "REVOKE":
                    print("No changes made.")
                    return 2
                removed = revoke_identity()
                print("PC identity revoked." if removed else "No identity existed.")
            return 0
        except (OSError, RuntimeError, ValueError, FileExistsError) as exc:
            print("PC identity operation failed: " + str(exc), file=sys.stderr)
            return 1
    if args.traffic_read_once and not (args.start and args.pair and args.qr and args.identity_pair):
        print("--traffic-read-once requires --start --pair --qr --identity-pair", file=sys.stderr)
        return 2
    if args.traffic_read_once and (
        args.status_once or args.media_once or args.send_file_once or args.receive_file_once
    ):
        print("Traffic requires a separate QR-v3 invitation", file=sys.stderr)
        return 2
    if args.media_once and not (args.start and args.pair and args.qr and args.identity_pair):
        print("--media-once requires --start --pair --qr --identity-pair", file=sys.stderr)
        return 2
    if args.media_once and (args.status_once or args.send_file_once or args.receive_file_once):
        print("Media/status/file modes need separate QR sessions", file=sys.stderr)
        return 2
    if args.compare_known_phone and not (
        args.start and args.pair and args.qr and args.identity_pair
    ):
        print("--compare-known-phone requires --start --pair --qr --identity-pair",
              file=sys.stderr)
        return 2
    if args.receive_file_once and not (
        args.start and args.pair and args.qr and args.identity_pair
    ):
        print("--receive-file-once requires --start --pair --qr --identity-pair", file=sys.stderr)
        return 2
    if args.receive_file_once and (args.send_file_once or args.status_once):
        print("File upload/download and status use independent QR sessions", file=sys.stderr)
        return 2
    if args.send_file_once and not (
        args.start and args.pair and args.qr and args.identity_pair
    ):
        print("--send-file-once requires --start --pair --qr --identity-pair",
              file=sys.stderr)
        return 2
    if args.send_file_once and args.status_once:
        print("Status and files require separate QR-v3 sessions", file=sys.stderr)
        return 2
    if args.status_once and not (args.start and args.pair and args.qr and args.identity_pair):
        print("--status-once requires --start --pair --qr --identity-pair",
              file=sys.stderr)
        return 2
    if args.identity_pair and not args.start:
        print("--identity-pair requires explicit --start", file=sys.stderr)
        return 2
    if not args.start:
        print("Not advertising. Use --start to opt in. See --help.")
        return 0
    if args.qr and not args.pair:
        print("--qr requires --pair", file=sys.stderr)
        return 2
    if args.identity_pair and not (args.pair and args.qr):
        print("--identity-pair requires --start --pair --qr", file=sys.stderr)
        return 2
    if not 1 <= args.minutes <= MAX_MINUTES:
        print("Duration must be between 1 and 30 minutes", file=sys.stderr)
        return 2
    try:
        expected_phone = None
        if args.compare_known_phone:
            from verified_phone_history import select_expected_verified_phone
            # Selection happens OFFLINE before discovering an adapter, opening
            # any listener or advertising mDNS. No default or auto-selected key.
            expected_phone = select_expected_verified_phone()
            if expected_phone is None:
                print("No phone selected. Nothing advertised.")
                return 2
        address = validate_lan_ipv4(args.ip) if args.ip else discover_local_ipv4()
        if args.pair:
            from pairing_server import run_pairing
            options = {"qr": args.qr, "identity_mode": args.identity_pair}
            if expected_phone is not None:
                options["expected_phone_fingerprint"] = expected_phone
            # Preserve exact legacy invocation for existing owners and QA.
            if args.status_once:
                options["status_once"] = True
            if args.send_file_once:
                options["file_once"] = True
            if args.receive_file_once:
                options["upload_once"] = True
            if args.media_once:
                options["media_once"] = True
            if args.traffic_read_once:
                options["traffic_once"] = True
                options["traffic_seconds"] = args.traffic_read_seconds
            run_pairing(address, args.minutes, **options)
        else:
            run_beacon(address, args.minutes)
        return 0
    except KeyboardInterrupt:
        print("\nStopped by user.")
        return 0
    except (OSError, RuntimeError, ValueError) as exc:
        print("Discovery not started: " + str(exc), file=sys.stderr)
        return 1
    except ImportError:
        print("Install Python dependencies: pip install -r requirements.txt",
              file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
