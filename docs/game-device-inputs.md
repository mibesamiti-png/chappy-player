# GAME-INPUT-01 — Motion + haptics input groundwork

Status: source candidate; CI and Android device QA required. No production release or Stable catalog change.

The Chappy Player host already implemented `Chappy.motion.sample(type)` with a maximum caller rate of **10 Hz**, foreground-only registration, 1.5 second timeout, and unregister on app background; `Chappy.haptics.play(effect)` already supported `tick/click/heavy` with at least 120 ms between vibrations.

This update adds:
- `Chappy.motion.available()`: after declaring `motion` permission and approving the first-use prompt, report true/false presence of accelerometer, gyroscope, magnetometer, **gravity**, and **linearAcceleration** sensors.
- `Chappy.motion.sample('gravity' | 'linearAcceleration')`: optional three-axis single measurements. Gravity is useful for tilt steering; linear acceleration helps detect movement without constant gravity.
- `Chappy.haptics.available()`: after declaring `haptics` and approving its first-use prompt, check whether the phone's vibrator motor is usable.
- **Chappy Device Lab 0.2.0 (CI test package only)**: manual hardware check, sample readings for all five sensors, and a moving ball driven by gravity at ~5 Hz. The tilt demo stops when the page is hidden. No sensor data is logged or transmitted.

Important limits: these are **single-shot sensor samples**, not a high-frequency realtime feed; 5 Hz is for a simple demo and not guaranteed on hardware. No background motion recording, location, GPS, unrestricted vibrations or PC/game-server network access. Availability and response timing vary by phone. Rate limits still apply.

Testing includes `tools/test_native_miniapp_capabilities.py`, `tools/test_device_lab.js`, `tools/test_bootstrap.js`, Flutter analyze/test and Kotlin/Gradle Debug APK. On-device QA still needed for five sensors' presence/values, foreground/background stop, 10 Hz limit, vibration/no-vibrator fallback, accessibility effects and power usage.

Next priority: create separate, permission-gated HTTPS/WSS game-server transport, with per-origin user confirmation, TLS, bounded messages and a clear shutdown on leaving the mini-app. Issue #42.
