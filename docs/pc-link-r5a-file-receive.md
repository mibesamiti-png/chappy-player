# PC Link R5A — bounded one-file download

This is an intentionally limited security-oriented preview. Windows selects
one local file before starting an HTTPS listener. The status permission
(`pc.status.read`) cannot be used to read it. Full QR-v3 mutual proof and two
**new** operator/phone approvals are required for the separate
`pc.file.receive` scope.

Limits: **4 MiB / file**, **16 KiB chunks**, **240 seconds** and QR lifetime,
no retries, no resume, no concurrent transfers. Windows does not accept any
remote path, file picker request or arbitrary command. Each chunk uses a new
request on the existing pinned TLS endpoint. A random one-time ticket and a
strictly increasing byte offset prevent replay.

The user's explicitly selected file bytes are read into bounded memory before
opening the listener; the complete path is not sent. Android must verify SHA-256
before offering a native Save As dialog. A full rollback/resume and the reverse
Android-to-PC direction are R5B work, not part of this R5A preview.

Source paths: `examples/windows_companion/file_send_once.py`, `pairing_server.py`, `companion.py`, Android `lib/core/pc_file_receive.dart`, `companion_identity_exchange.dart`, `lib/screens/companion_pairing_page.dart`, and private `sample_apps/pc_transfer_lab/index.html` (manual QA guide, **not a privileged PC control mini-app**).

Physical Android↔Windows QA remains unperformed until tested; no signed Stable
release or public catalog publication. The 4MiB limit and no-resume behavior are
R5A-specific. Android→Windows owner-selected upload and larger streaming follow in R5B.
