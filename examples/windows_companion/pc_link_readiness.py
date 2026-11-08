"""Read-only PC Link readiness checks. Never opens a listener or creates keys.

These are local troubleshooting hints, NOT proof that Android can connect.
No IP, public fingerprint, username, device name or exception is printed.
"""
from __future__ import annotations

import importlib
import re
from collections.abc import Callable

_REQUIRED = ("zeroconf", "cryptography", "qrcode")


def doctor(
    *,
    load_dependency: Callable[[str], object] | None = None,
    read_identity: Callable[[], str | None] | None = None,
    find_lan: Callable[[], str] | None = None,
    report: Callable[[str], None] = print,
) -> bool:
    """Check local prerequisites only; return False if manual setup is needed."""
    if load_dependency is None:
        load_dependency = importlib.import_module
    if read_identity is None:
        from windows_identity import identity_status
        read_identity = identity_status
    if find_lan is None:
        from companion import discover_local_ipv4
        find_lan = discover_local_ipv4

    ready = True
    for module in _REQUIRED:
        try:
            load_dependency(module)
        except (ImportError, OSError, RuntimeError, ValueError):
            report("PC-DOCTOR-DEPS: " + module + " is not available.")
            ready = False
        else:
            report("PC-DOCTOR-DEPS-OK: " + module)

    try:
        fingerprint = read_identity()
        if fingerprint is None:
            report("PC-DOCTOR-KEY: PC identity not created. "
                   "Run --identity-create explicitly before QR-v3.")
            ready = False
        elif not isinstance(fingerprint, str) or re.fullmatch(
            r"[0-9a-f]{64}", fingerprint
        ) is None:
            report("PC-DOCTOR-KEY: PC identity status is invalid.")
            ready = False
        else:
            # Do not reveal even the PUBLIC fingerprint in diagnostic output.
            report("PC-DOCTOR-KEY-OK: PC identity is available.")
    except (OSError, RuntimeError, ValueError, ImportError):
        report("PC-DOCTOR-KEY: identity access failed; check current Windows user.")
        ready = False

    try:
        from companion import validate_lan_ipv4
        address = find_lan()
        validate_lan_ipv4(address)
        report("PC-DOCTOR-LAN-OK: a private IPv4 candidate was found.")
    except (OSError, RuntimeError, ValueError):
        report("PC-DOCTOR-LAN: no private LAN address found. "
               "Check Wi-Fi/Ethernet and use --ip if needed.")
        ready = False

    if ready:
        report("PC-DOCTOR-READY: Local prerequisites found. "
               "Windows Firewall and Android connectivity are NOT tested.")
    else:
        report("PC-DOCTOR-NOT-READY: No connection was started; "
               "fix the listed local prerequisites.")
    return ready
