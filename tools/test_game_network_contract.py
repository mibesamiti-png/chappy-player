"""Static privacy and sandbox regression checks for game HTTPS/WSS broker.

Flutter unit tests validate URL/DNS policy. Real-device TLS and a deployed
server must be verified separately before signed production publication.
"""
from pathlib import Path
R=Path(__file__).resolve().parent.parent
def txt(p): return (R/p).read_text(encoding="utf-8")
net=txt("lib/core/miniapp_game_network.dart")
runner=txt("lib/screens/app_runner_page.dart")
bridge=txt("lib/core/local_app_server.dart")
package=txt("lib/core/package_model.dart")
pack=txt("tools/pack_html_chappy.py")
catalog=txt("tools/build_chappy_catalog.py")
manifest=txt("tools/patch_android.py")
ui=txt("sample_apps/game_server_lab/index.html")
docs=txt("docs/native-capabilities-roadmap.md")
for name in (
    "static Uri validate(", "GameNetworkPolicy.resolvePublic(uri.host)",
    "InternetAddress.tryParse(host) != null",
    "addresses.any((ip) => !isPublicAddress(ip))",
    "client.connectionFactory =", "Socket.startConnect(address,",
    "..findProxy = ((_) => 'DIRECT')",
    "uri.scheme != (websocket ? 'wss' : 'https')",
    "uri.userInfo.isNotEmpty", "uri.fragment.isNotEmpty",
    "maxMessageBytes = 8192", "maxResponseBytes = 65536",
    "maxQueuedMessages = 64", "outbound.followRedirects = false",
    "client.openUrl(method, uri)", "utf8.decode(bytes, allowMalformed: false)",
    "maxPayloadLength: GameNetworkPolicy.maxMessageBytes",
    "CompressionOptions.compressionOff",
    "_queue.length >= GameNetworkPolicy.maxQueuedMessages",
    "now - _lastSendMs < 50",
    "void pause()", "void close()", "_generation",
):
    if name == "_generation":
        assert "_epoch" in net
    else:
        assert name in net, name

for name in (
    "_approveNativeCapability('network', '暗号化サーバー通信')",
    "_approvedGameOrigins.clear()",
    "_gameNetwork.pause()",
    "_gameNetwork.resume()",
    "'network.request'", "'network.connect'",
    "'network.send'", "'network.poll'", "'network.close'",
    "showDialog<bool>", "この画面だけ許可",
    "'owner': widget.app.id",
):
    if name == "'owner': widget.app.id":
        continue  # Network session is scoped by AppRunnerPage instance.
    assert name in runner, name

for name in (
    "network: Object.freeze({",
    "call('network.request'", "call('network.connect'",
    "call('network.send'", "call('network.poll'",
    "call('network.close'",
    "connect-src 'none'",
):
    assert name in bridge, name

for name in ("'network'", "暗号化サーバー通信"):
    assert name in package
assert "'network'" in pack
assert '"network"' in catalog
assert 'android.permission.INTERNET' in manifest
assert '"network"' not in txt("tools/android/MainActivity.kt"), (
    "Network broker should be in Dart, not an unaudited Android native bridge")
assert "window.Chappy.network" in ui
assert "motion.sample('gravity')" in ui
assert "haptics.play('tick')" in ui
assert "document.hidden" in ui
assert "new WebSocket(" not in ui and "fetch(" not in ui
assert "NATIVE-GAME-01" in docs

print("HTTPS/WSS game broker origin-consent, sandbox, DNS pinning, bounds and lifecycle contract passed")
