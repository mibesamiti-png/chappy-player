"""Configure Flutter Android *release* signing from GitHub Actions secrets.

Nothing is written to the repository: generated files are ignored and
exist only on the CI runner. Never print the keystore or passphrases.
"""
import base64
import os
from pathlib import Path

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
