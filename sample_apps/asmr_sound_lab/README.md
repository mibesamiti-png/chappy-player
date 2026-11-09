# ASMR Sound Lab — Chappy Player mini-app source

This directory holds the **editable source** of the existing `local.chappy.asmr` Chappy Player mini-app.

## Origin and deployment boundary

- Baseline: **ASMR Sound Lab 1.4.0**, recovered unchanged from the public Stable `.chappy` payload on 2026-11-09.
- Published package: [chappy-apps/stable/asmr-sound-lab.chappy](https://github.com/mibesamiti-png/chappy-apps/blob/main/stable/asmr-sound-lab.chappy).
- Published catalog SHA-256 (of the ZIP): `89c09a9c7c61c7e9bb6912516eb1b0bbc5303c0f5d212ab07ca10419f4ba545f`; package 130,390 bytes; extracted `index.html` 129,990 UTF-8 bytes.
- This source import **does not release or replace** the Stable package, installed APK, or any saved app data. The package is already public; do not add personal audio, device logs, keys, or private samples.

## Build a Chappy mini-app package (not a standalone HTML release)

From the `chappy-player` repository root:

```sh
python3 tools/pack_html_chappy.py \
  --source sample_apps/asmr_sound_lab \
  --id local.chappy.asmr \
  --name "ASMR Sound Lab" \
  --version 1.4.4 \
  --output /tmp/asmr-skin-preview-v1.4.4.chappy
python3 tools/test_chappy_package_tools.py
```

The packager adds a `manifest.json` with `entry: index.html`, `permissions: []` and the same ID. It may produce different ZIP bytes because archive timestamps/manifest encoding differ; the embedded source is preserved. **Do not publish a rebuilt package as the existing Stable 1.4.0 version.** For a change, bump the version, verify it, publish to a reviewed Debug channel first, test on an actual Android device, then separately approve Stable promotion. Do not publish an APK for a mini-app-only edit.

## v1.4.4 candidate — independent head/face surface contact (not published)

- **ASMR-SURF-01:** independent low-level, filtered-white-noise surface friction path for skin, separate from the preexisting bone/head internal vibration and ear-canal exclusive contact. Head/cheek/scalp sound differs by anatomical zone hardness presets.
- **ASMR-SURF-02:** short, soft first-touch noise impulse; touching without movement produces a brief event, then near-silence, while rubbing is proportional to pointer speed. Existing bone transient and contact hysteresis remain untouched.
- **ASMR-SURF-03:** dedicated 0–100% slider (“頭・顔表面の触感”) defaults to 65%, with zero disabling the new surface sound. Surface route is filtered through external ear occlusion, with L/R zone-dependent weighting. No external sample downloads.
- **ASMR-QA:** pure-function checks cover no touch/stationary/air contact, material mode, cheek vs. forehead, L/R weighting, non-finite inputs, routing separation and max gain. Quick CI produces an **unpublished v1.4.4 .chappy + standalone HTML** preview.
- **Settings:** keep app ID `local.chappy.asmr` and existing `preset-v14` key. Old presets without `skinSurface` use the 65% default. Audio quality and Android WebView headphone behavior still require real device testing.

## v1.4.3 candidate — bounded two-layer seal rumble (not published)

- **ASMR-RUMBLE-01:** keep the earlier airy filtered-white-noise ear layer, and add a separately filtered, lower-frequency brown-noise layer (48 Hz high-pass, 180 Hz low-pass). Both are generated offline and routed to their own ear only.
- The new low layer fades in **only as that ear closes**; it remains silent in the open-ear state even if the source is close to the head. Both gains start at zero, and remain bounded by pure `bodyRumbleTargets()`: airy <= 0.26, deep <= 0.125. Body-noise OFF forces both to zero.
- Attack and release use independent smoothed Web Audio gain targets. Existing limiter/soft clipper, ear-exclusive routing, saved `preset-v14`, A/B input behavior, and head/face vibration remain unchanged.
- `node tools/test_asmr_sound_lab.js` checks the open/closed, OFF, monotonic, nonfinite-control, route-guard and gain-limit cases. Quick CI produces the **unpublished 1.4.3 `.chappy` preview** for manual device listening checks.
- This is an **acoustic approximation** for headphones, not literal bone-conduction stimulation. A numeric gain limit cannot guarantee safe subjective loudness; start at low Android system volume. Android WebView/real headphone QA is pending.

## v1.4.2 candidate — contact-edge hysteresis (not published)

- **ASMR-CONTACT-01**: a Schmitt-style contact-event latch replaces a single threshold for ear-tip taps, gel touch/peel events, and bone/face taps. A new touch must pass the stronger engagement threshold; small boundary drift won't retrigger until contact strength drops below the lower release threshold.
- Ear/gel: engage at **0.20**, release below **0.07**. Head/face vibration: engage at **0.28**, release below **0.09**. Values act only on **discrete transients**; continuous contact gain, sealing EQ, stereo routing and oscillator waveform remain unchanged.
- Existing `lastTap` anti-burst timing and independent A/B latches remain intact; turning off an input or disabling bone effects still suppresses events.
- `node tools/test_asmr_sound_lab.js` now checks boundary drift, first-contact, release, invalid input and source wiring. CI builds an **unpublished v1.4.2 `.chappy` artifact**.
- Never overwrite public Stable v1.4.0 or republish v1.4.1 with different bytes. Device-specific tactile/audio tests remain pending.

## v1.4.1 candidate — ear-entry transition (not published)

- Replace the linear exterior/interior amplitude crossover with a **power-preserving trigonometric crossfade** after the smoothstep ear-entry distance curve. This reduces the perceived dip around the virtual ear entrance while preserving zero external routing at full insertion.
- The same envelope is applied to external head-spatial audio, preserved-stereo source routing, and internal sample entry. Existing exclusive contact-ear routing and limiter remain unchanged.
- `node tools/test_asmr_sound_lab.js` checks endpoints, continuity, equal-power invariance and the corresponding audio-path connections. The packager smoke test invokes it in both regular and Quick CI.
- Quick CI creates **asmr-sound-lab-v1.4.1-preview.chappy** as an **unpublished** artifact for manual Chappy Player installation. It is not an APK, public catalog update or Stable release.
- No new user permissions, private samples, or destructive settings migration. The existing `preset-v14` storage key is preserved across the minor patch.
- **Pending:** headphones/Android WebView listening comparison (volume balance, phone touch response and ear isolation); CI cannot determine perceived realism or device-specific audio bugs.

## Existing implementation / verification boundary

- Implemented in this baseline: eight synthesised sound types, independently movable A/B sources, dual touch, head and ear geometry, contact vs. self-producing sounds, depth-related seal/bass effects, bone/tissue-inspired contact route, audio samples, presets, and Chappy storage integration.
- **Partially modeled:** head diffraction/HRTF approximation, perceptual loudness normalization, binaural sample routing, realistic surface/water physics, and performance limits.
- **Not included:** measured HRTF convolution; bundled third-party CC0 recordings; WAV/FLAC export.
- **Device verification pending:** Android WebView stereo spatial quality, two-finger response, audio clicks and safe peak level on different headphones, sample import/export, settings persistence after force-close.

Feature IDs remain from the earlier ASMR spec: `BONE-01..06`, `SPAT-06`, `SAMPLE-04..05`, `QA-02/04`. “Implemented” describes the source, **not** verified Android listening quality.

## Next mini-app iteration

1. **ASMR-QA-01:** test actual Chappy Player WebView audio start/stop, two-source stereo, two pointers, settings persistence, and return-from-background; record results without private logs.
2. **ASMR-AUD-01:** measure clipping and clicks for boosted internal bass/seal while keeping output level safe.
3. **ASMR-SPAT-01:** improve ear-entry transition, bone-contact mix, and head/face touch event hysteresis; compare with effects toggled.
4. **ASMR-SAMPLE-01:** test approved locally selected sound files before considering any redistributed CC0 sample set.

Keep this directory as the source of truth for future mini-app edits; the Chappy Player host and PC Link workstreams are separate.
