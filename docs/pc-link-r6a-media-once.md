# PC Link R6A — One-time media key (Debug preview)

Status: source/CI candidate. Physical Windows and Android two-device test has not been performed.

Windows owner explicitly starts Start-ChappyMediaOnceV3.cmd after creating a PC identity. This creates a short-lived QR-v3 media=1 invite, with a pinned TLS certificate and normal P-256 mutual identity proof (PC YES). Identity success alone grants no media operation.

Android foreground owner selects exactly one of volume_up, volume_down, toggle_mute, play_pause. Windows asks separately for CONTROL while showing the exact command. A fresh PC proof binds command and nonce with SHA-256 of the bytes CHAPPY-PC-MEDIA-CONTROL-V1 + NUL + command + NUL + raw nonce bytes, independently of identity, status and file scopes.

Android verifies PC signature and TLS pin, then displays another foreground consent; only after approval does Android KeyStore sign a new command-bound PC nonce. Windows verifies the phone proof, device identity and expiry, irrevocably consumes the grant and issues exactly one fixed Windows multimedia virtual key. No arbitrary key, mouse, shell, files, auto-connect or privileged mini-app JavaScript.

Limits: one operation per fresh QR, maximum 90 seconds after PC approval and never past QR expiration. If the HTTP response is lost after a toggle, the operation may already have occurred; DO NOT retry a consumed QR. Windows multimedia key routing depends on physical OS/audio focus; source/CI tests with mock executor are not physical QA.

Merge gates: exact PR HEAD Quick CI Flutter analyze/unit and JS isolation; Windows Preview CI real P-256 checks with injected mock key action, EXE and opt-in launcher artifact. Android Debug hardware, pairing, firewall, media key results and foreground/background tests still required. No signed Stable APK or public mini-app catalog change.

Next: R6B real-device tests and usability, then any broader input-control proposal must use a new explicit scope and separate approval.
