"""Offline smoke tests for packaging HTML and generating a public catalog."""
import hashlib
import json
from pathlib import Path
import tempfile
import zipfile

from build_chappy_catalog import build_catalog
from pack_html_chappy import package_html

with tempfile.TemporaryDirectory(prefix="chappy_html_tools_") as temp:
    root = Path(temp)
    html = root / "asmr-html"
    html.mkdir()
    (html / "index.html").write_text(
        '<!doctype html><html><script src="app.js"></script></html>',
        encoding="utf-8",
    )
    (html / "app.js").write_text("console.log('ASMR demo');", encoding="utf-8")
    (html / "assets").mkdir()
    (html / "assets" / "style.css").write_text("body {margin:0}", encoding="utf-8")
    public = root / "chappy-apps"
    stable = public / "stable"
    stable.mkdir(parents=True)
    package = stable / "asmr-sound-lab.chappy"
    package_html(html, package, "local.chappy.asmr", "ASMR Sound Lab", "0.1.0")
    with zipfile.ZipFile(package) as archive:
        manifest = json.loads(archive.read("manifest.json"))
        assert manifest["id"] == "local.chappy.asmr"
        assert "index.html" in archive.namelist()
        assert "app.js" in archive.namelist()
        assert "assets/style.css" in archive.namelist()

    catalog = json.loads(build_catalog(public))
    assert len(catalog["entries"]) == 1
    record = catalog["entries"][0]
    assert record["version"] == "0.1.0"
    assert record["channel"] == "stable"
    assert record["sha256"] == hashlib.sha256(package.read_bytes()).hexdigest()
    assert record["sizeBytes"] == package.stat().st_size
    assert record["url"].endswith("/stable/asmr-sound-lab.chappy")

    media_package = stable / "media-probe.chappy"
    package_html(html, media_package, "local.chappy.media", "Media Probe", "0.1.0",
                 ["camera", "microphone"])
    with zipfile.ZipFile(media_package) as archive:
        assert json.loads(archive.read("manifest.json"))["permissions"] == ["camera", "microphone"]
    catalog = json.loads(build_catalog(public))
    assert len(catalog["entries"]) == 2
    device_package = stable / "motion-haptic-test.chappy"
    package_html(html, device_package, "local.chappy.device_lab", "Device Lab",
                 "0.1.0", ["motion", "haptics"])
    with zipfile.ZipFile(device_package) as archive:
        assert json.loads(archive.read("manifest.json"))["permissions"] == [
            "motion", "haptics"]

    file_package = stable / "file-lab.chappy"
    file_source = Path(__file__).resolve().parent.parent / "sample_apps/file_lab"
    package_html(file_source, file_package, "local.chappy.file_lab",
                 "Chappy File Lab", "0.1.0", ["files"])
    with zipfile.ZipFile(file_package) as archive:
        assert json.loads(archive.read("manifest.json"))["permissions"] == ["files"]
        assert b"files.pickText()" in archive.read("index.html")
    assert len(json.loads(build_catalog(public))["entries"]) == 4

    try:
        package_html(html, public / "invalid.chappy", "local.chappy.invalid", "Invalid", "0.1.0",
                     ["location"])
    except ValueError:
        pass
    else:
        raise AssertionError("Unsupported native permission was allowed")

    # Package the real media test mini-app; never activate devices in CI.
    real_html = Path(__file__).resolve().parent.parent / "sample_apps/media_probe"
    media_demo = root / "media-probe.chappy"
    package_html(real_html, media_demo, "local.chappy.media_probe",
                 "Chappy Media Lab", "0.1.3", ["camera", "microphone"])
    with zipfile.ZipFile(media_demo) as archive:
        demo_manifest = json.loads(archive.read("manifest.json"))
        assert demo_manifest["permissions"] == ["camera", "microphone"]
        source = archive.read("index.html")
        assert b"getUserMedia" in source
        assert b"id=\"advancedAudio\"" in source
        assert b"audio: true" in source
        assert b"NotReadableError" in source
        assert demo_manifest["version"] == "0.1.3"
        assert b'id="cameraResolution"' in source
        assert b'id="nativeMicOn"' in source
        assert b'Chappy.microphone.start()' in source
        assert b'Chappy.microphone.levels()' in source
        assert b'Chappy.microphone.stop()' in source

    debug = public / "debug"
    debug.mkdir()
    debug_package = debug / "asmr-test.chappy"
    package_html(html, debug_package, "local.chappy.asmr",
                 "ASMR Sound Lab", "0.2.0")
    catalog = json.loads(build_catalog(public))
    assert {item["channel"] for item in catalog["entries"]} == {
        "stable", "debug",
    }

    try:
        package_html(html, package, "local.chappy.asmr",
                     "ASMR Sound Lab", "0.1.0")
    except ValueError:
        pass
    else:
        raise AssertionError("Overwriting package was allowed")

print("HTML-to-Chappy + Stable/Debug catalog generator smoke tests passed")
