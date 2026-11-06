"""Network Lab MVP guards: trusted foreground NSD and no open LAN bridge.

These checks supplement Flutter tests and the Android Kotlin/Gradle build;
they cannot prove service discovery works on a physical Wi-Fi network.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


native = read("tools/android/NativeNetworkDiscovery.kt")
host = read("tools/android/MainActivity.kt")
manifest = read("tools/patch_android.py")
dart = read("lib/core/lan_discovery_client.dart")
screen = read("lib/screens/network_lab_page.dart")
home = read("lib/main.dart")
webview = read("lib/core/local_app_server.dart")
test = read("test/network_lab_page_widget_test.dart")

for token in (
    "NsdManager.DiscoveryListener",
    "nsd.discoverServices(",
    "nsd.stopServiceDiscovery(",
    "nsd.resolveService(",
    'MAX_SCAN_MS = 15000L',
    'MAX_SERVICES = 24',
    'setOf("_http._tcp.", "_workstation._tcp.", "_ipp._tcp.")',
    'private var foreground = false',
    'if (!foreground)',
    'Build.VERSION.SDK_INT >= 37',
    'activity.applicationInfo.targetSdkVersion >= 37',
    'hasLocalNetwork()',
    'NetworkCapabilities.TRANSPORT_WIFI',
    'NetworkCapabilities.TRANSPORT_ETHERNET',
    'handler.postDelayed(task, MAX_SCAN_MS)',
    'stopInternal(clearResults = true)',
    'multicastLock',
    'if (clearResults)',
):
    assert token in native, token

assert 'Socket(' not in native and 'HttpClient' not in native
assert 'Datagram' not in native
assert 'ACCESS_LOCAL_NETWORK' not in manifest, (
    "Never add broad Android 17 LAN permission as part of the narrow MVP")
for token in (
    '"dev.chappy.player/network_lab"',
    'networkDiscovery.onPause()',
    'networkDiscovery.onDestroy()',
    'networkDiscovery.start(kind)',
    'if (!micActivityVisible)',
):
    assert token in host, token
for token in (
    "'android.permission.ACCESS_NETWORK_STATE'",
    "'android.permission.CHANGE_WIFI_MULTICAST_STATE'",
    "'NativeNetworkDiscovery.kt'",
):
    assert token in manifest, token
for token in (
    "LanDiscoverySnapshot",
    "supportedTypes.contains(serviceType)",
    "'start'",
    "'snapshot'",
    "'stop'",
):
    assert token in dart, token
for token in (
    "showDialog<bool>",
    "'15秒間だけ探す'",
    "WidgetsBindingObserver",
    "_cancelScan(clearResults: true)",
    "unawaited(widget.client.stop())",
    "Timer.periodic(",
    "Network Lab",
):
    assert token in screen, token
assert "const NetworkLabPage()" in home
assert "network_lab" not in webview, (
    "Untrusted mini-apps must not receive any direct LAN or NSD bridge")
assert "expect(calls, isEmpty)" in test
assert "find.byKey(const Key('netlab_stop'))" in test

print("Network Lab foreground consent, scope, timeout, lifecycle and UI guards passed")
