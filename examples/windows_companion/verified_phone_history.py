"""DPAPI-protected, local-only history of phone fingerprints verified by QR-v3.

History is NOT a trusted-device authorization list and is NEVER consulted to
approve future network sessions. Store only after both QR-v3 proofs succeeded
and the PC operator separately typed SAVE. No automatic enrollment.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import tempfile
import time

from windows_identity import _dpapi, _identity_path, identity_status

HISTORY_FILENAME = "verified-phones-v1.dpapi"
PREFIX = b"CHAPPY_VERIFIED_PHONE_HISTORY_V1\x00"
MAX_RECORDS = 24
MAX_BLOB = 8192
HEX_FP = re.compile(r"[0-9a-f]{64}\Z")


def _valid_fp(value: object) -> bool:
    return isinstance(value, str) and HEX_FP.fullmatch(value) is not None


def _history_path(directory: Path | None = None) -> Path:
    identity_path = _identity_path(directory)
    target = identity_path.with_name(HISTORY_FILENAME)
    if target.is_symlink():
        raise OSError("History file must not be a symlink")
    return target


def _unique_json_pairs(pairs: list[tuple[str, object]]) -> dict:
    result: dict = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate verified-phone history field")
        result[key] = value
    return result


def _owner(directory: Path | None) -> str:
    fingerprint = identity_status(directory)
    if not _valid_fp(fingerprint):
        raise ValueError("Create PC device identity before using history")
    return fingerprint


def _read(directory: Path | None, owner: str) -> list[dict[str, object]]:
    path = _history_path(directory)
    if not path.exists():
        return []
    blob = path.read_bytes()
    if not 1 <= len(blob) <= MAX_BLOB:
        raise ValueError("Invalid encrypted verified-phone history length")
    clear = _dpapi(blob, protect=False)
    if not clear.startswith(PREFIX) or len(clear) > MAX_BLOB:
        raise ValueError("Invalid verified-phone history format")
    document = json.loads(
        clear[len(PREFIX):].decode("utf-8"),
        object_pairs_hook=_unique_json_pairs,
    )
    if not isinstance(document, dict) or set(document) != {
        "schema", "owner", "records"
    } or type(document["schema"]) is not int or document["schema"] != 1:
        raise ValueError("Invalid verified-phone history structure")
    if document["owner"] != owner:
        raise ValueError("PC device key changed: old history is not reusable")
    records = document["records"]
    if not isinstance(records, list) or len(records) > MAX_RECORDS:
        raise ValueError("Invalid verified-phone record count")
    seen: set[str] = set()
    validated: list[dict[str, object]] = []
    for row in records:
        if not isinstance(row, dict) or set(row) != {"fingerprint", "verified_at"}:
            raise ValueError("Invalid verified-phone row structure")
        fingerprint = row["fingerprint"]
        timestamp = row["verified_at"]
        if (
            not _valid_fp(fingerprint)
            or fingerprint in seen
            or type(timestamp) is not int
            or timestamp <= 0
        ):
            raise ValueError("Invalid or duplicate verified-phone row")
        seen.add(fingerprint)
        validated.append({"fingerprint": fingerprint, "verified_at": timestamp})
    return validated


def list_verified_phones(directory: Path | None = None) -> list[dict[str, object]]:
    """Read only; no key generation, no listener, and no file write."""
    return _read(directory, _owner(directory))


def _write(records: list[dict[str, object]], directory: Path | None, owner: str) -> None:
    path = _history_path(directory)
    if len(records) > MAX_RECORDS:
        raise ValueError("Verified-phone history is full")
    data = PREFIX + json.dumps({
        "schema": 1, "owner": owner, "records": records,
    }, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("ascii")
    if len(data) > MAX_BLOB:
        raise ValueError("Verified-phone history exceeds storage limit")
    encrypted = _dpapi(data, protect=True)
    if not 1 <= len(encrypted) <= MAX_BLOB:
        raise ValueError("Encrypted history exceeds storage limit")
    # Write to an exclusive private temp file, fsync, then atomically replace.
    fd, temp_path = tempfile.mkstemp(prefix=".verified-phone-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as out:
            out.write(encrypted)
            out.flush()
            os.fsync(out.fileno())
        if path.is_symlink():
            raise OSError("History file must not be a symlink")
        os.replace(temp_path, path)
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)


def remember_verified_phone(
    fingerprint: str, directory: Path | None = None,
) -> bool:
    """Called ONLY after a verified QR-v3 phone proof and separate PC SAVE."""
    if not _valid_fp(fingerprint):
        raise ValueError("Expected a verified 64-character Android public fingerprint")
    owner = _owner(directory)
    if fingerprint == owner:
        raise ValueError("PC cannot be its own verified phone")
    records = _read(directory, owner)
    if any(row["fingerprint"] == fingerprint for row in records):
        return False
    if len(records) >= MAX_RECORDS:
        raise ValueError("Verified-phone history is full")
    records.append({"fingerprint": fingerprint, "verified_at": int(time.time())})
    _write(records, directory, owner)
    return True


def forget_verified_phone(fingerprint: str, directory: Path | None = None) -> bool:
    if not _valid_fp(fingerprint):
        raise ValueError("Expected a 64-character phone fingerprint")
    owner = _owner(directory)
    records = _read(directory, owner)
    updated = [row for row in records if row["fingerprint"] != fingerprint]
    if len(updated) == len(records):
        return False
    if updated:
        _write(updated, directory, owner)
    else:
        _history_path(directory).unlink(missing_ok=True)
    return True


def clear_verified_phone_history(directory: Path | None = None) -> None:
    """Delete local history during PC key revocation, even when corrupt."""
    _history_path(directory).unlink(missing_ok=True)


def offer_remember_verified_phone(fingerprint: str) -> bool:
    """Separate offline PC consent AFTER a successful one-shot mutual proof."""
    if not _valid_fp(fingerprint):
        raise ValueError("Only verified Android public fingerprints are valid")
    print()
    print("QR-v3 mutual P-256 verification succeeded.")
    print("Android public key SHA-256: " + fingerprint)
    print("Save this public fingerprint in current-user DPAPI history?")
    print("This grants NO auto-reconnect, PC control, files or future trust.")
    try:
        answer = input("Type SAVE to store this history ONLY (anything else skips): ")
    except (EOFError, OSError):
        return False
    if answer.strip() != "SAVE":
        print("Verification history not saved.")
        return False
    try:
        saved = remember_verified_phone(fingerprint)
    except (OSError, ValueError) as exc:
        print("History could not be saved: " + type(exc).__name__)
        return False
    print("Public fingerprint saved." if saved else "Already in history.")
    return saved
