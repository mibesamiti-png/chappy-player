# PC Control Lab — R6B private Debug manual QA

This is an offline manual checklist, NOT a PC control or file interface.
The trusted Android host Network Lab owns all PC Link QR-v3 identity, consent and limited media actions.
The Windows owner launches Start-ChappyMediaOnceV3.cmd and explicitly approves YES and CONTROL.
The Android owner must independently sign and approve exactly one of four fixed media keys.

Build as an unpublished local .chappy package:

~~~sh
python3 tools/pack_html_chappy.py --source sample_apps/pc_control_lab --id local.chappy.pc_control_lab --name "PC Control Lab" --version 0.1.0 --output build/pc-control-lab.chappy
~~~

The packer writes a manifest.json with permissions: []. Do not add a source manifest or publish this QA application.
Manual checkbox results are not saved; the copyable report contains only checklist IDs. It includes no QR secret, key, address or device identifiers.
R6B manual 13 cases are separate from NETLAB-03B physical 15 cases; all physical QA is NOT RUN until independently observed.