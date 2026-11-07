"""Configure only the dedicated Debug variant using a persistent DEBUG key.

Never use CHAPPY_KEYSTORE_B64 from production, and never run on PR builds.
Secrets are materialized only in generated (ignored) Android runner files.
"""
import base64
import hashlib
import os
from pathlib import Path
import re
import subprocess

ROOT = Path("android")
APP = ROOT / "app"
GRADLE = APP / "build.gradle.kts"
PROPERTY_FILE = ROOT / "debug-key.properties"
KEYSTORE = APP / "chappy-debug.jks"
required = ["CHAPPY_DEBUG_KEYSTORE_B64", "CHAPPY_DEBUG_STORE_PASSWORD",
            "CHAPPY_DEBUG_KEY_PASSWORD", "CHAPPY_DEBUG_KEY_ALIAS"]
missing = [key for key in required if not os.environ.get(key)]
if missing:
    raise SystemExit("Missing dedicated Debug signing secrets: " + ", ".join(missing))
if not GRADLE.is_file():
    raise SystemExit("Generated Kotlin Gradle Android runner not found")
pinned = os.environ.get("CHAPPY_DEBUG_CERT_SHA256", "").strip().lower()
if not re.fullmatch(r"[0-9a-f]{64}", pinned):
    raise SystemExit("Pin CHAPPY_DEBUG_CERT_SHA256 to the dedicated Debug certificate")
try:
    data = base64.b64decode(os.environ["CHAPPY_DEBUG_KEYSTORE_B64"].strip(), validate=True)
except ValueError as exc:
    raise SystemExit("Dedicated Debug keystore is not valid base64") from exc
if not 100 <= len(data) <= 1024 * 1024:
    raise SystemExit("Dedicated Debug keystore has unexpected size")
KEYSTORE.write_bytes(data)
cert = subprocess.run([
    "keytool", "-exportcert", "-keystore", str(KEYSTORE),
    "-alias", os.environ["CHAPPY_DEBUG_KEY_ALIAS"],
    "-storepass:env", "CHAPPY_DEBUG_STORE_PASSWORD",
], capture_output=True)
if cert.returncode != 0 or not cert.stdout:
    raise SystemExit("Cannot extract certificate from dedicated Debug keystore")
if hashlib.sha256(cert.stdout).hexdigest() != pinned:
    raise SystemExit("Dedicated Debug signing certificate does not match pinned digest")

def prop(value: str) -> str:
    if "\n" in value or "\r" in value:
        raise SystemExit("Invalid multiline signing secret")
    return (value.replace("\\", "\\\\").replace("=", "\\=")
            .replace(":", "\\:").replace("#", "\\#").replace("!", "\\!"))

PROPERTY_FILE.write_text(
    "storePassword=" + prop(os.environ["CHAPPY_DEBUG_STORE_PASSWORD"]) + "\n" +
    "keyPassword=" + prop(os.environ["CHAPPY_DEBUG_KEY_PASSWORD"]) + "\n" +
    "keyAlias=" + prop(os.environ["CHAPPY_DEBUG_KEY_ALIAS"]) + "\n" +
    "storeFile=chappy-debug.jks\n",
    encoding="utf-8",
)

source = GRADLE.read_text(encoding="utf-8")
if "chappyDebugKeystore" in source:
    raise SystemExit("Debug signing already configured")
if source.count("android {") != 1 or source.count("    buildTypes {") != 1:
    raise SystemExit("Unknown Gradle project layout")
if 'applicationIdSuffix = ".debug"' not in source:
    raise SystemExit("Refusing to sign a non-isolated Debug package")
source = "import java.io.FileInputStream\nimport java.util.Properties\n\n" + source
source = source.replace(
    "android {",
    """val chappyDebugKeystore = Properties()
val chappyDebugPropsFile = rootProject.file("debug-key.properties")
chappyDebugKeystore.load(FileInputStream(chappyDebugPropsFile))

android {""", 1)
source = source.replace(
    "    buildTypes {",
    """    signingConfigs {
        getByName("debug") {
            keyAlias = chappyDebugKeystore.getProperty("keyAlias")
            keyPassword = chappyDebugKeystore.getProperty("keyPassword")
            storeFile = chappyDebugKeystore.getProperty("storeFile")?.let { file(it) }
            storePassword = chappyDebugKeystore.getProperty("storePassword")
        }
    }
    buildTypes {""", 1)
GRADLE.write_text(source, encoding="utf-8")
print("Dedicated pinned Debug signing configured for isolated Debug package")
