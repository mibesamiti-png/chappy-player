"""NETLAB-06A offline PCAP inspection security and limits preflight.
This is not packet sniffing, TLS decryption or live monitoring.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parse = (ROOT / "lib/core/pcap_inspector.dart").read_text()
ui = (ROOT / "lib/screens/traffic_inspection_page.dart").read_text()
network = (ROOT / "lib/screens/network_lab_page.dart").read_text()
webview = (ROOT / "lib/core/local_app_server.dart").read_text()
host = (ROOT / "tools/android/MainActivity.kt").read_text()

for term in (
    "maxFileBytes = 2 * 1024 * 1024",
    "maxPacketCount = 2500", "maxVisible = 160",
    "includePlaintextBody=false", "PCAPNG", "Ethernet/Raw IPv4",
    "DNS問い合わせ", "TLS暗号化", "TCP/443",
    "平文HTTP", "_sni(", "_dns(", "_preview(",
    "password|token|secret",
):
    assert term in parse, term

for term in (
    "FilePicker.platform.pickFiles", "withData: true",
    "maxFileBytes", "CheckboxListTile", "_ownerApproved",
    "showDialog<bool>", "traffic_inspect_approve",
    "_showPlaintext", "didChangeAppLifecycleState", "_inspection = null",
    "他端末への侵入はしません", "HTTPS/QUIC",
    "RAM" if False else "結果を消去",
):
    assert term in ui, term

assert "netlab_traffic_inspection" in network
assert "TrafficInspectionPage()" in network

# Deny all active capture, UI-induced interception, persistence and JS bridge.
for text in (parse, ui):
    for token in (
        "VpnService", "HttpClient", "Socket.connect", "DatagramSocket",
        "RawDatagramSocket", "tcpdump", "tshark", "Process.run",
        "SharedPreferences", "File.write", "MethodChannel",
        "package:webview_flutter", "HttpServer",
    ):
        assert token not in text, token
assert "PcapInspector" not in host
assert "PcapInspector" not in webview
assert "trafficInspect" not in webview
print("NETLAB-06A offline-only owner-supplied PCAP analysis boundary OK")
