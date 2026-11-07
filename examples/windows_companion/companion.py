"""Chappy Companion: opt-in Windows LAN discovery beacon (no PC control).

Starts only with --start. Default is still an inert DNS-SD beacon.
With explicit --pair, exposes one pinned-TLS PC-approved confirmation exchange;
it grants no persistent device trust, command execution, packet capture,
file transfer, credential store, or background service.
"""

from __future__ import annotations

import argparse
import ipaddress
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
        "--identity-qr", action="store_true",
        help="EXPERIMENTAL: with --start --pair --qr use opt-in P-256 proof QR-v3 (phone client pending)",
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
    if args.identity_create or args.identity_status or args.identity_revoke:
        if args.pair or args.qr or args.identity_qr or args.ip or args.minutes != DEFAULT_MINUTES:
            print("Identity commands cannot be combined with network options",
                  file=sys.stderr)
            return 2
        try:
            from windows_identity import (
                create_identity, identity_status, revoke_identity,
            )
            if args.identity_status:
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
                print("WARNING: This revokes the local PC signing identity.")
                print("Future authenticated pairing will require a new identity.")
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
    if args.identity_qr and not (args.start and args.pair and args.qr):
        print("--identity-qr requires --start --pair --qr", file=sys.stderr)
        return 2
    if not args.start:
        print("Not advertising. Use --start to opt in. See --help.")
        return 0
    if args.qr and not args.pair:
        print("--qr requires --pair", file=sys.stderr)
        return 2
    if not 1 <= args.minutes <= MAX_MINUTES:
        print("Duration must be between 1 and 30 minutes", file=sys.stderr)
        return 2
    try:
        address = validate_lan_ipv4(args.ip) if args.ip else discover_local_ipv4()
        if args.pair:
            from pairing_server import run_pairing
            run_pairing(address, args.minutes, qr=args.qr,
                        identity_qr=args.identity_qr)
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
