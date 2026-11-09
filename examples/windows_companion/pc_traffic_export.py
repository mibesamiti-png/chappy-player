"""Owner-invoked Windows PC traffic COUNTER export, not packet capture.

Counts total bytes for ALL interfaces (Wi-Fi, Ethernet, VPN etc). Never
records IPs, other hosts, payload, URLs, process or interface identifiers.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import time
from collections.abc import Callable

FORMAT = "chappy.remote-traffic.v1"
MAX_BYTES = (1 << 52) - 1
MAX_SAMPLES = 30


def system_counters() -> tuple[int, int]:
    import psutil
    result = psutil.net_io_counters(pernic=False, nowrap=True)
    if result is None:
        raise RuntimeError("PC network counters unavailable")
    return result.bytes_recv, result.bytes_sent


def _checked(raw: tuple[int, int]) -> tuple[int, int]:
    if (not isinstance(raw, tuple) or len(raw) != 2 or
            any(type(x) is not int or not 0 <= x <= MAX_BYTES for x in raw)):
        raise ValueError("Invalid network counters")
    return raw


def capture(*, samples: int = 10,
            reader: Callable[[], tuple[int, int]] = system_counters,
            sleeper: Callable[[float], None] = time.sleep) -> dict[str, object]:
    if type(samples) is not int or not 5 <= samples <= MAX_SAMPLES:
        raise ValueError("Choose 5-30 seconds")
    previous = _checked(reader())
    points: list[dict[str, int]] = []
    for _ in range(samples):
        sleeper(1.0)
        current = _checked(reader())
        if current[0] < previous[0] or current[1] < previous[1]:
            raise ValueError("Network counter reset; no report created")
        points.append({"rx_bytes": current[0] - previous[0],
                       "tx_bytes": current[1] - previous[1]})
        previous = current
    return {
        "format": FORMAT,
        "source": "windows_pc",
        "coverage": "all_interfaces",
        "interval_ms": 1000,
        "samples": points,
        "totals": {
            "rx_bytes": sum(point["rx_bytes"] for point in points),
            "tx_bytes": sum(point["tx_bytes"] for point in points),
        },
    }


def write_report(report: dict[str, object], path: Path) -> Path:
    """Exclusive local create, never overwriting any existing user file."""
    encoded = (json.dumps(report, ensure_ascii=True, separators=(",", ":"))
               + "\n").encode("ascii")
    if len(encoded) > 16 * 1024:
        raise ValueError("Report exceeds 16 KiB")
    created = False
    try:
        with path.open("xb") as output:
            created = True
            output.write(encoded)
            output.flush()
            os.fsync(output.fileno())
    except BaseException:
        if created:
            path.unlink(missing_ok=True)
        raise
    return path


def suggested_filename() -> str:
    return "chappy-pc-traffic-" + time.strftime("%Y%m%d-%H%M%S") + ".json"
