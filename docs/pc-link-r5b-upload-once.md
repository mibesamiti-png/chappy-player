# PC Link R5B — single Android → Windows file upload preview

**Source/CI preview, not physical 2-device Android↔Windows QA.** Full QR-v3 mutual signed device proof and QR certificate-pinned TLS remain required. R5B adds a NEW independently scoped permission `pc.file.upload`, not reusing R5A `pc.file.receive` or R4C `pc.status.read`.

1. PC owner starts `Start-ChappyUploadOnceV3.cmd` or explicit `--start --pair --qr --identity-pair --receive-file-once`; enters **absolute NEW PC destination filename** before a listener opens. No remote path or directory listing; existing files are never overwritten.
2. Android scans `upload=1` QR-v3, validates selected LAN endpoint, TLS SHA-256 pin, PC key and two-way P-256 signatures. Identity success alone is not upload permission.
3. Android owner selects **one** local file through trusted native host picker (1–4 MiB; basename must match PC destination). PC asks for extra **RECEIVE** for the exact filename and size. Windows sends a new scope-separated challenge, Android verifies PC signature and asks a **second Android consent**; then KeyStore signs a new upload-scoped challenge.
4. A random one-time ticket permits strictly sequential 16 KiB base64 chunks under original pinned TLS/QR, at most 240 seconds after identity confirmation. Windows verifies size and SHA-256 before writing via temp file + no-clobber hardlink to the PC-selected destination, with temp cleanup even on failure.
5. Wrong signature, scope confusion, duplicate chunk, replayed ticket, extra JSON keys, expired QR, missing permissions, symlinks, path traversal and destination collisions fail closed. No background service, arbitrary PC files, overwrites, shell or persistent pairing. If target filesystem cannot perform safe hardlink creation, upload fails rather than overwriting.

Android implementation: `lib/core/pc_file_upload.dart`, `companion_identity_exchange.dart`, `companion_qr_invitation.dart`, `companion_pairing_page.dart`. Windows: `examples/windows_companion/file_upload_once.py`, `companion.py`, `pairing_server.py`. Tests: `tools/test_pc_file_upload.py`, `tools/test_pc_upload_boundary.py`, `test/pc_file_upload_test.dart`, QR parser tests.

The private Debug PC Transfer Lab includes R5A/R5B manual QA checkboxes but **cannot itself transfer** anything, and is not published to the public Chappy Apps catalog. No official signed Stable APK is updated. Real-device QR/KeyStore/Firewall, target filesystem, cancellation and app background tests remain mandatory before a user-visible release.
