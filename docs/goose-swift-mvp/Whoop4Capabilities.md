# WHOOP 4.0 — what we can track client-side, and the feature roadmap

Research output (multi-agent capability study, cross-checked against openwhoop
and the live whoof-core code). The question: with only a WHOOP 4.0 and no access
to WHOOP's servers, what can the app compute on-device?

## What the band actually gives us over BLE
- **Per-second history**: heart rate (bpm), RR intervals (beat-to-beat ms),
  activity marker.
- **High-rate IMU**: tri-axial accelerometer + gyroscope (~100 Hz), big-endian.
- **Raw DSP sensor block** (V12/V24 packets): PPG green/red-IR, SpO2 red/IR,
  skin-temp, respiratory, signal-quality, skin-contact, ambient — all **raw ADC**.

## The hard boundary
Calibrated **SpO2 %**, **skin temperature °C**, and the **raw respiratory ADC**
are processed on WHOOP's servers; the band emits only uncalibrated counts and
there is no published client-side conversion. We do NOT fabricate these.

Everything else is derivable from RR intervals + IMU. The big realization:
**respiratory rate is recoverable on-device from RR-interval RSA**, so we are not
blocked on the raw respiratory ADC.

## Built this cycle (Rust core, unit-tested)
- [x] **RSA respiratory rate** (`respiratory_rsa.rs::goose_respiratory_rate_v0`) —
  4 Hz tachogram + band-limit + cycle count. Keystone: gives Gen4 a respiratory
  source. Tests recover 12 & 15 rpm from synthetic signals.
- [x] **Poincare HRV** SD1 / SD2 / ratio (`metrics.rs::goose_hrv_v0`).
- [x] **Frequency-domain HRV** VLF/LF/HF, LF/HF ratio, normalized units
  (`respiratory_rsa.rs::goose_hrv_frequency_v0`) — autonomic balance.
- [x] **Activity classifier** rest/walk/run (`step_motion_estimator.rs::classify_activity`).
- [x] (earlier) Gen4 decode: HR, RR, IMU motion; RMSSD/SDNN/pNN50; strain; stress;
  energy; step-count + cadence; step motion estimate fallback.

## Roadmap — remaining build list (prioritized)
Pure formulas are done; the items below are mostly **pipeline integration** (wire
a formula over the right window into the daily rollup) + **UI surfacing**, which
need real synced band data to validate end-to-end.

1. **Recovery Score v0 Gen4 unblock** (P1) — feed RSA respiratory + baseline into
   `goose_recovery_v0`; neutralize the absent skin-temp component
   (`temperature_component_unavailable_gen4`). The formula already accepts these
   inputs; this is recovery_rollup.rs wiring. The single highest-value unblock.
2. **Respiratory baseline + deviation** (P2) — trailing-7-night mean of nightly
   RSA rpm (mirror the sleep/HRV baseline pattern).
3. **Signal-quality / skin-contact gating** (P2) — use Gen4 `skin_contact` +
   `signal_quality` to exclude off-wrist windows from HR/HRV/respiratory.
4. **Sleep-stage feature extractor** (P3) — per-30s motion+HR+HRV+RSA vector →
   deep/REM/light minutes (currently consumed but never derived on-device).
5. **Min/Mean HR per window** (P3) — extend `aggregate_metric_window`.
6. **Sleep movement / disturbance index** (P5).
7. **Sedentary vs active minutes** (P6); **distance/stride** (P7) from classifier.
8. **HRV triangular index / TINN** (P6); **accel-derived respiratory** cross-check (P8).

## Wiring + UI (per feature, after formulas)
metric_features.rs feature report → store daily rollup → bridge method → SwiftUI
metric row/card. The design system (HealthHero/HealthInfoRow/card surface) already
renders any metric row, so new metrics surface with a row + a snapshot field.
