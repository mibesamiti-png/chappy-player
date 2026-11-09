"""NETLAB-05C: one-shot foreground Wi-Fi router candidate recognition.

Static safety gate supplements, but does not replace, Flutter and Android CI
or physical Wi-Fi/router testing.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


native = source("tools/android/NativeRouterIdentity.kt")
activity = source("tools/android/MainActivity.kt")
dart = source("lib/core/router_identity_client.dart")
ui = source("lib/screens/router_auto_identify_page.dart")
lab = source("lib/screens/network_lab_page.dart")
patch = source("tools/patch_android.py")
webview = source("lib/core/local_app_server.dart")
manifest = patch

for needle in (
    "cm.activeNetwork", "getNetworkCapabilities(network)",
    "TRANSPORT_WIFI", "TRANSPORT_VPN", "TRANSPORT_CELLULAR",
    "getLinkProperties(network)", "route.isDefaultRoute",
    "isPrivateIpv4(candidate)", "generation == session",
    "MAX_SSDP_REPLY = 2048", "MAX_XML_BYTES = 16384",
    "MAX_WAIT_MS = 2400L", "MAX_RESPONSES = 8",
    "239.255.255.250:1900", "ST: upnp:rootdevice",
    'if (packet.address != gateway) continue',
    'url.protocol != "http" || url.host != gateway',
    'connection.instanceFollowRedirects = false',
    'connection.connectTimeout = 1200',
    'connection.readTimeout = 1200',
    'network.openConnection(url, Proxy.NO_PROXY)',
    '"evidence" to if (hint == null) "gateway_only" else "upnp_self_report"',
):
    assert needle in native, needle

for needle in (
    "routerIdentity = NativeRouterIdentity(this)",
    "routerIdentity.onResume()", "routerIdentity.onPause()",
    "routerIdentity.onDestroy()", '"routerIdentityProbe" ->',
    "routerProbeBusy.compareAndSet(false, true)",
    "networkDiscovery.trafficPairingAllowed()", "Thread {",
    "if (!micActivityVisible", "routerIdentity.probe()",
):
    assert needle in activity, needle

for needle in (
    "RouterIdentitySnapshot.fromWire",
    "isPrivateIpv4", "'gateway_only'", "'upnp_self_report'",
    "invokeMapMethod<String, dynamic>('routerIdentityProbe')",
):
    assert needle in dart, needle

for needle in (
    "WidgetsBindingObserver", "showDialog<bool>",
    "今回だけ識別する", "_ownerApproved", "_foreground",
    "_generation++", "didChangeAppLifecycleState",
    "UPnP", "自己申告", "型番",
):
    assert needle in ui, needle

assert "netlab_router_identify" in lab
assert "RouterAutoIdentifyPage()" in lab
assert "'NativeRouterIdentity.kt'" in patch
assert "ACCESS_LOCAL_NETWORK" not in manifest
for file in (activity, native, dart, ui):
    assert "SharedPreferences" not in file
assert "routerIdentityProbe" not in webview
assert "NativeRouterIdentity" not in webview

for forbidden in (
    "URLClassLoader", "ProcessBuilder", "Runtime.getRuntime",
    "setRequestMethod(\"POST\")", "authorization", "Authorization",
    "password", "Cookie", "MulticastSocket", "HttpsURLConnection",
):
    assert forbidden not in native, forbidden

print("NETLAB-05C router identity candidate scope, consent and Android host isolation passed")
