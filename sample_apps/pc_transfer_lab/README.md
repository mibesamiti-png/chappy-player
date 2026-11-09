# PC Transfer Lab — Debug mini-app source (R5A)

This is a manual QA guide/checklist, NOT a file/PC control interface.
No `Chappy.files`, `Chappy.network`, unrestricted WebView network,
socket, privileged app bridge, or native PC capability is exposed.

The **actual file receiver** is the trusted Chappy Player host screen:
Network Lab → PC pairing with a QR-v3 `file=1` invite. The PC owner uses
`Start-ChappyFileOnceV3.cmd`; a fresh mutual signing ceremony and separate
PC SEND + Android file approval are required.

Package this private debug mini-app with the existing packer:

```sh
python3 tools/pack_html_chappy.py --source sample_apps/pc_transfer_lab \
  --id local.chappy.pc_transfer_lab --name "PC Transfer Lab" \
  --version 0.1.0 --output /tmp/pc-transfer-lab.chappy
```

The packer generates manifest.json with `permissions: []`.
Do not add a manifest.json into this source directory. This package is
**NOT** automatically published to public Chappy Apps or signed APK releases.
