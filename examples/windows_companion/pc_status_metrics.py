"""Only a tiny, user-approved read-only aggregate of local Windows metrics.

Never query device name, username, process list, files, IP, MAC, browsing
activity, packet metadata, installed apps or microphone/camera.
No exception content or personal paths are returned to Android.
"""
from __future__ import annotations

import os
import platform


def read_pc_status() -> dict[str, object]:
    result: dict[str, object] = {
        "available": False,
        "logical_cpus": None,
        "memory_total_bytes": None,
        "memory_available_bytes": None,
        "uptime_seconds": None,
    }
    if platform.system() != "Windows":
        return result

    try:
        import ctypes

        class MEMORYSTATUSEX(ctypes.Structure):
            _fields_ = [
                ("length", ctypes.c_ulong),
                ("memory_load", ctypes.c_ulong),
                ("total_physical", ctypes.c_ulonglong),
                ("available_physical", ctypes.c_ulonglong),
                ("total_page_file", ctypes.c_ulonglong),
                ("available_page_file", ctypes.c_ulonglong),
                ("total_virtual", ctypes.c_ulonglong),
                ("available_virtual", ctypes.c_ulonglong),
                ("available_extended_virtual", ctypes.c_ulonglong),
            ]

        info = MEMORYSTATUSEX()
        info.length = ctypes.sizeof(info)
        kernel = ctypes.windll.kernel32
        if kernel.GlobalMemoryStatusEx(ctypes.byref(info)) != 0:
            total, available = int(info.total_physical), int(info.available_physical)
            if 0 < total and 0 <= available <= total:
                result["memory_total_bytes"] = total
                result["memory_available_bytes"] = available
        kernel.GetTickCount64.restype = ctypes.c_ulonglong
        uptime_ms = int(kernel.GetTickCount64())
        if uptime_ms >= 0:
            result["uptime_seconds"] = uptime_ms // 1000
    except (AttributeError, OSError, TypeError, ValueError, OverflowError):
        pass
    try:
        cores = os.cpu_count()
        if type(cores) is int and 0 < cores <= 4096:
            result["logical_cpus"] = cores
    except (OSError, RuntimeError):
        pass
    result["available"] = any(
        result[field] is not None for field in (
            "logical_cpus", "memory_total_bytes", "uptime_seconds",
        )
    )
    return result
