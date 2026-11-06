"""Short-lived, exact-format PC-to-Android QR bootstrap invitation.

This URL is only a one-session TLS connection locator. The phone still pins
the certificate and the Windows PC still requires on-screen YES approval.
No app link/website is opened from QR; never put QR payload in mDNS TXT.
"""
from __future__ import annotations

import re
import time
from urllib.parse import parse_qs, urlencode, urlsplit

from companion import validate_lan_ipv4

SCHEME = "chappy-pair"
HOST = "invite"
MAX_QR_BYTES = 256
MAX_AGE_SECONDS = 1800
FULL_PIN = re.compile(r"[0-9a-f]{64}\Z")
TICKET = re.compile(r"[0-9a-f]{32}\Z")


def create_invitation(
    ip: str, port: int, fingerprint: str, expires_at: int, ticket: str,
    *, now: int | None = None,
) -> str:
    address = validate_lan_ipv4(ip)
    if not 1 <= port <= 65535 or not isinstance(expires_at, int):
        raise ValueError("Invalid pairing endpoint")
    if FULL_PIN.fullmatch(fingerprint) is None or TICKET.fullmatch(ticket) is None:
        raise ValueError("Invalid certificate pin or ticket")
    current = int(time.time()) if now is None else now
    if expires_at <= current or expires_at - current > MAX_AGE_SECONDS:
        raise ValueError("Invitation must expire in 1–1800 seconds")
    query = urlencode({
        "v": "1", "ip": address, "port": str(port),
        "fp": fingerprint, "exp": str(expires_at), "ticket": ticket,
    })
    data = "chappy-pair://invite?" + query
    if len(data.encode("ascii")) > MAX_QR_BYTES:
        raise ValueError("Invitation too long")
    return data


def parse_invitation(value: str, *, now: int | None = None) -> dict[str, object]:
    if len(value) > MAX_QR_BYTES or not value.isascii():
        raise ValueError("Invalid QR payload")
    uri = urlsplit(value)
    if (uri.scheme != SCHEME or uri.netloc != HOST or uri.path or
            uri.fragment or not uri.query):
        raise ValueError("Not a Chappy QR invitation")
    parsed = parse_qs(uri.query, strict_parsing=True, keep_blank_values=True)
    if set(parsed) != {"v", "ip", "port", "fp", "exp", "ticket"}:
        raise ValueError("Unknown or missing invitation fields")
    if any(len(items) != 1 for items in parsed.values()):
        raise ValueError("Duplicate invitation field")
    one = {key: vals[0] for key, vals in parsed.items()}
    if one["v"] != "1" or not re.fullmatch(r"[1-9][0-9]{0,4}", one["port"]):
        raise ValueError("Invalid invitation version/port")
    if not re.fullmatch(r"[0-9]{10}", one["exp"]):
        raise ValueError("Invalid invitation expiry")
    address = validate_lan_ipv4(one["ip"])
    port, expiry = int(one["port"]), int(one["exp"])
    # Validate and canonicalize via the same constructor used to make the QR.
    create_invitation(
        address, port, one["fp"], expiry, one["ticket"], now=now,
    )
    return {
        "ip": address, "port": port, "fingerprint": one["fp"],
        "expires_at": expiry, "ticket": one["ticket"],
    }
