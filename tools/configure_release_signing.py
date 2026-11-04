"""Configure Flutter Android *release* signing from GitHub Actions secrets.

Nothing is written to the repository: generated files are ignored and
exist only on the CI runner. Never print the keystore or passphrases.
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
KEY_FILE = ROOT / "key.properties"
KEYSTORE = APP / "chappy-release.jks"

required = [
    "CHAPPY_KEYSTORE_B64",
    "CHAPPY_STORE_PASSWORD",
    "CHAPPY_KEY_PASSWORD",
    "CHAPPY_KEY_ALIAS",
]
missing = [key for key in required if not os.environ.get(key)]
if missing:
    raise SystemExit("Release signing secrets are not configured: " + ", ".join(missing))
if not GRADLE.exists():
    raise SystemExit("Missing generated Android Kotlin Gradle file")

# Java .properties escape sequence handling; prohibit embedded line breaks.
def props(value):
    if "\n" in value or "\r" in value:
        raise SystemExit("Signing secret includes unsupported line breaks")
    return value.replace("\\", "\\\\").replace("=", "\\=").replace(":", "\\:").replace("#", "\\#").replace("!", "\\!")

try:
    keystore_bytes = base64.b64decode(
        os.environ["CHAPPY_KEYSTORE_B64"].strip(), validate=True
    )
except ValueError as exc:
    raise SystemExit("CHAPPY_KEYSTORE_B64 is not valid base64") from exc
if len(keystore_bytes) < 100 or len(keystore_bytes) > 1024 * 1024:
    raise SystemExit("Unexpected keystore size")
APP.mkdir(parents=True, exist_ok=True)
KEYSTORE.write_bytes(keystore_bytes)
# Fingerprint the DER certificate from the exact CI keystore before compiling.
# keytool reads its password from the environment, never command-line arguments.
pinned_cert = os.environ.get("CHAPPY_RELEASE_CERT_SHA256", "").strip().lower()
if not re.fullmatch(r"[0-9a-f]{64}", pinned_cert):
    raise SystemExit("Missing or invalid CHAPPY_RELEASE_CERT_SHA256 variable")
cert = subprocess.run(
    [
        "keytool", "-exportcert", "-keystore", str(KEYSTORE),
        "-alias", os.environ["CHAPPY_KEY_ALIAS"],
        "-storepass:env", "CHAPPY_STORE_PASSWORD",
    ],
    capture_output=True,
)
if cert.returncode != 0 or not cert.stdout:
    raise SystemExit(
        "Cannot read signing certificate from uploaded keystore. "
        "Check CHAPPY_KEYSTORE_B64, CHAPPY_STORE_PASSWORD, and CHAPPY_KEY_ALIAS."
    )
actual_cert = hashlib.sha256(cert.stdout).hexdigest()
if actual_cert != pinned_cert:
    raise SystemExit(
        "Keystore certificate SHA-256 does not match GitHub Actions variable. "
        f"Keystore certificate SHA-256: {actual_cert.upper()}; "
        f"pinned CHAPPY_RELEASE_CERT_SHA256: {pinned_cert.upper()}. "
        "Correct the variable or uploaded keystore; do not disable this check."
    )
print("Uploaded keystore certificate matches pinned SHA-256")
KEY_FILE.write_text(
    "storePassword=" + props(os.environ["CHAPPY_STORE_PASSWORD"]) + "\n"
    "keyPassword=" + props(os.environ["CHAPPY_KEY_PASSWORD"]) + "\n"
    "keyAlias=" + props(os.environ["CHAPPY_KEY_ALIAS"]) + "\n"
    "storeFile=chappy-release.jks\n",
    encoding="utf-8",
)

source = GRADLE.read_text(encoding="utf-8")
if "chappyRelease" in source:
    raise SystemExit("Gradle release signing has already been configured")
debug_signing = 'signingConfig = signingConfigs.getByName("debug")'
if debug_signing not in source:
    raise SystemExit("Cannot locate Flutter's debug release signing placeholder")
if "    buildTypes {" not in source or "android {" not in source:
    raise SystemExit("Unexpected Flutter build.gradle.kts structure")

source = "import java.io.FileInputStream\nimport java.util.Properties\n\n" + source
source = source.replace(
    "android {",
    """val chappyKeystore = Properties()
val chappyKeystoreFile = rootProject.file("key.properties")
if (chappyKeystoreFile.exists()) {
    chappyKeystore.load(FileInputStream(chappyKeystoreFile))
}

android {""",
    1,
)
source = source.replace(
    "    buildTypes {",
    """    signingConfigs {
        create("chappyRelease") {
            keyAlias = chappyKeystore.getProperty("keyAlias")
            keyPassword = chappyKeystore.getProperty("keyPassword")
            storeFile = chappyKeystore.getProperty("storeFile")?.let { file(it) }
            storePassword = chappyKeystore.getProperty("storePassword")
        }
    }
    buildTypes {""",
    1,
)
source = source.replace(
    debug_signing,
    'signingConfig = signingConfigs.getByName("chappyRelease")',
    1,
)
GRADLE.write_text(source, encoding="utf-8")
print("Release signing configured using CI secrets (secret values redacted)")
