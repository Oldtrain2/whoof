//! Respiratory rate from RR-interval respiratory sinus arrhythmia (RSA).
//!
//! A WHOOP 4.0 emits RR intervals but no calibrated respiratory value (that is
//! computed server-side from raw ADC). Breathing rate is, however, recoverable
//! on-device: respiration modulates the heart rate, so the RR-interval tachogram
//! carries an oscillation at the breathing frequency (~0.1-0.5 Hz). We resample
//! the tachogram to a uniform grid, band-limit it to the respiratory band, and
//! count cycles.
//!
//! This is the keystone that lets the Gen4 recovery score include a respiratory
//! component without WHOOP's servers.

pub const GOOSE_RESPIRATORY_RSA_V0_ID: &str = "goose.respiratory.rsa.v0";
pub const GOOSE_RESPIRATORY_RSA_V0_VERSION: &str = "0.1.0";

const RESAMPLE_HZ: f64 = 4.0;
const MIN_WINDOW_SECONDS: f64 = 60.0;
const MIN_VALID_INTERVALS: usize = 30;
const MIN_RPM: f64 = 6.0;
const MAX_RPM: f64 = 40.0;
/// Detrend window ~8 s removes drift below ~0.12 Hz.
const DETREND_SECONDS: f64 = 8.0;
/// Smoothing window ~1.5 s attenuates content above ~0.5 Hz.
const SMOOTH_SECONDS: f64 = 1.5;

#[derive(Debug, Clone, PartialEq)]
pub struct RespiratoryRateRsaOutput {
    pub respiratory_rate_rpm: Option<f64>,
    pub window_seconds: f64,
    pub valid_interval_count: usize,
    pub resampled_sample_count: usize,
    pub cycle_count: usize,
    pub confidence: f64,
    pub quality_flags: Vec<String>,
}

/// Estimate respiratory rate (breaths per minute) from a window of RR intervals.
pub fn goose_respiratory_rate_v0(rr_intervals_ms: &[f64]) -> RespiratoryRateRsaOutput {
    let mut quality_flags = Vec::new();
    let valid: Vec<f64> = rr_intervals_ms
        .iter()
        .copied()
        .filter(|value| value.is_finite() && (300.0..=2000.0).contains(value))
        .collect();
    let window_seconds = valid.iter().sum::<f64>() / 1000.0;

    if valid.len() < MIN_VALID_INTERVALS || window_seconds < MIN_WINDOW_SECONDS {
        quality_flags.push("respiratory_rsa_window_too_short".to_string());
        return RespiratoryRateRsaOutput {
            respiratory_rate_rpm: None,
            window_seconds,
            valid_interval_count: valid.len(),
            resampled_sample_count: 0,
            cycle_count: 0,
            confidence: 0.0,
            quality_flags,
        };
    }

    let tachogram = resample_tachogram(&valid, RESAMPLE_HZ);
    let detrended = subtract_moving_mean(&tachogram, window_samples(DETREND_SECONDS));
    let smoothed = moving_mean(&detrended, window_samples(SMOOTH_SECONDS));
    let cycle_count = rising_zero_crossings(&smoothed);
    let duration_seconds = tachogram.len() as f64 / RESAMPLE_HZ;
    let rpm = if duration_seconds > 0.0 {
        cycle_count as f64 * 60.0 / duration_seconds
    } else {
        0.0
    };

    let mut respiratory_rate_rpm = Some(rpm);
    if !(MIN_RPM..=MAX_RPM).contains(&rpm) {
        quality_flags.push("respiratory_rate_out_of_physiologic_range".to_string());
        respiratory_rate_rpm = None;
    }

    // Confidence grows with window length and a plausible number of counted
    // cycles; a 5-minute clean window is treated as full confidence.
    let length_term = clamp01(window_seconds / 300.0) * 0.7;
    let cycle_term = if cycle_count >= 5 { 0.3 } else { 0.0 };
    let confidence = clamp01(length_term + cycle_term);

    RespiratoryRateRsaOutput {
        respiratory_rate_rpm,
        window_seconds,
        valid_interval_count: valid.len(),
        resampled_sample_count: tachogram.len(),
        cycle_count,
        confidence,
        quality_flags,
    }
}

/// Resample an RR series to a uniform grid at `fs_hz`. Each beat is placed at the
/// cumulative time of its interval; the tachogram value is the interpolated RR in
/// milliseconds.
pub fn resample_tachogram(rr_ms: &[f64], fs_hz: f64) -> Vec<f64> {
    if rr_ms.len() < 2 || fs_hz <= 0.0 {
        return Vec::new();
    }
    let mut times = Vec::with_capacity(rr_ms.len());
    let mut acc = 0.0;
    for &interval in rr_ms {
        acc += interval / 1000.0;
        times.push(acc);
    }
    let total_seconds = *times.last().unwrap_or(&0.0);
    let sample_count = (total_seconds * fs_hz).floor() as usize;
    let mut out = Vec::with_capacity(sample_count);
    let mut j = 0usize;
    for i in 0..sample_count {
        let t = i as f64 / fs_hz;
        while j + 1 < times.len() && times[j + 1] < t {
            j += 1;
        }
        let t0 = times[j];
        let v0 = rr_ms[j];
        let (t1, v1) = if j + 1 < times.len() {
            (times[j + 1], rr_ms[j + 1])
        } else {
            (t0, v0)
        };
        let value = if t1 > t0 {
            let frac = ((t - t0) / (t1 - t0)).clamp(0.0, 1.0);
            v0 + (v1 - v0) * frac
        } else {
            v0
        };
        out.push(value);
    }
    out
}

fn window_samples(seconds: f64) -> usize {
    ((seconds * RESAMPLE_HZ).round() as usize).max(1)
}

/// Subtract a centered moving mean (high-pass: removes slow drift).
fn subtract_moving_mean(values: &[f64], window: usize) -> Vec<f64> {
    let baseline = moving_mean(values, window);
    values
        .iter()
        .zip(baseline.iter())
        .map(|(value, base)| value - base)
        .collect()
}

/// Centered moving average of odd-ish window length.
fn moving_mean(values: &[f64], window: usize) -> Vec<f64> {
    if values.is_empty() || window <= 1 {
        return values.to_vec();
    }
    let half = window / 2;
    let mut out = Vec::with_capacity(values.len());
    for i in 0..values.len() {
        let lo = i.saturating_sub(half);
        let hi = (i + half + 1).min(values.len());
        let slice = &values[lo..hi];
        out.push(slice.iter().sum::<f64>() / slice.len() as f64);
    }
    out
}

/// Count rising zero crossings (one per respiratory cycle on a zero-mean signal).
fn rising_zero_crossings(values: &[f64]) -> usize {
    let mut count = 0usize;
    for pair in values.windows(2) {
        if pair[0] <= 0.0 && pair[1] > 0.0 {
            count += 1;
        }
    }
    count
}

fn clamp01(value: f64) -> f64 {
    value.clamp(0.0, 1.0)
}

pub const GOOSE_HRV_FREQUENCY_V0_ID: &str = "goose.hrv.frequency.v0";
pub const GOOSE_HRV_FREQUENCY_V0_VERSION: &str = "0.1.0";

// 60s admits LF/HF from a ~1 min RR window (coarser LF resolution than the
// classic 2 min, but a real computation). Without this, an elevated heart rate
// shrinks the fixed-count live RR buffer below 120s and the metric silently
// disappears.
const FREQ_MIN_WINDOW_SECONDS: f64 = 60.0;

/// Frequency-domain HRV: power in the VLF/LF/HF bands and the LF/HF ratio, an
/// index of autonomic (sympathetic vs parasympathetic) balance. Computed from
/// the same 4 Hz RR tachogram used for RSA respiratory rate.
#[derive(Debug, Clone, PartialEq)]
pub struct HrvFrequencyOutput {
    pub vlf_power_ms2: f64,
    pub lf_power_ms2: f64,
    pub hf_power_ms2: f64,
    pub total_power_ms2: f64,
    pub lf_hf_ratio: f64,
    pub lf_normalized: f64,
    pub hf_normalized: f64,
    pub window_seconds: f64,
    pub quality_flags: Vec<String>,
}

pub fn goose_hrv_frequency_v0(rr_intervals_ms: &[f64]) -> HrvFrequencyOutput {
    let mut quality_flags = Vec::new();
    let valid: Vec<f64> = rr_intervals_ms
        .iter()
        .copied()
        .filter(|value| value.is_finite() && (300.0..=2000.0).contains(value))
        .collect();
    let window_seconds = valid.iter().sum::<f64>() / 1000.0;

    let empty = HrvFrequencyOutput {
        vlf_power_ms2: 0.0,
        lf_power_ms2: 0.0,
        hf_power_ms2: 0.0,
        total_power_ms2: 0.0,
        lf_hf_ratio: 0.0,
        lf_normalized: 0.0,
        hf_normalized: 0.0,
        window_seconds,
        quality_flags: vec!["hrv_freq_window_too_short".to_string()],
    };
    if window_seconds < FREQ_MIN_WINDOW_SECONDS || valid.len() < MIN_VALID_INTERVALS {
        return empty;
    }

    let tachogram = resample_tachogram(&valid, RESAMPLE_HZ);
    let n = tachogram.len();
    if n < 16 {
        return empty;
    }
    let series_mean = tachogram.iter().sum::<f64>() / n as f64;

    // Hann-windowed, mean-detrended series + window power for PSD normalization.
    let mut windowed = Vec::with_capacity(n);
    let mut window_power = 0.0;
    for (i, &value) in tachogram.iter().enumerate() {
        let w = 0.5 - 0.5 * (std::f64::consts::TAU * i as f64 / (n as f64 - 1.0)).cos();
        windowed.push((value - series_mean) * w);
        window_power += w * w;
    }

    let df = RESAMPLE_HZ / n as f64;
    let half = n / 2;
    let (mut vlf, mut lf, mut hf) = (0.0, 0.0, 0.0);
    for k in 1..=half {
        let freq = k as f64 * df;
        if freq > 0.4 {
            break;
        }
        let mut re = 0.0;
        let mut im = 0.0;
        for (i, &x) in windowed.iter().enumerate() {
            let angle = -std::f64::consts::TAU * (k as f64) * (i as f64) / n as f64;
            re += x * angle.cos();
            im += x * angle.sin();
        }
        // One-sided PSD (ms^2/Hz), corrected for window power.
        let psd = (re * re + im * im) / (RESAMPLE_HZ * window_power) * 2.0;
        let band_power = psd * df;
        if (0.0033..0.04).contains(&freq) {
            vlf += band_power;
        } else if (0.04..0.15).contains(&freq) {
            lf += band_power;
        } else if (0.15..=0.4).contains(&freq) {
            hf += band_power;
        }
    }

    let total = vlf + lf + hf;
    let lf_hf_ratio = if hf > 0.0 { lf / hf } else { 0.0 };
    let lf_hf_sum = lf + hf;
    let lf_normalized = if lf_hf_sum > 0.0 { lf / lf_hf_sum } else { 0.0 };
    let hf_normalized = if lf_hf_sum > 0.0 { hf / lf_hf_sum } else { 0.0 };

    HrvFrequencyOutput {
        vlf_power_ms2: vlf,
        lf_power_ms2: lf,
        hf_power_ms2: hf,
        total_power_ms2: total,
        lf_hf_ratio,
        lf_normalized,
        hf_normalized,
        window_seconds,
        quality_flags,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Build RR intervals modulated by a known respiratory frequency.
    fn synthetic_rr(resp_hz: f64, seconds: f64, base_ms: f64, amplitude_ms: f64) -> Vec<f64> {
        let mut rr = Vec::new();
        let mut t = 0.0;
        while t < seconds {
            let interval = base_ms
                + amplitude_ms * (std::f64::consts::TAU * resp_hz * t).sin();
            rr.push(interval);
            t += interval / 1000.0;
        }
        rr
    }

    #[test]
    fn recovers_known_respiratory_rate_at_15_rpm() {
        // 0.25 Hz modulation = 15 breaths/min.
        let rr = synthetic_rr(0.25, 180.0, 900.0, 45.0);
        let out = goose_respiratory_rate_v0(&rr);
        let rpm = out.respiratory_rate_rpm.expect("rpm computed");
        assert!(
            (rpm - 15.0).abs() <= 2.5,
            "expected ~15 rpm, got {rpm} (cycles={}, window={}s)",
            out.cycle_count,
            out.window_seconds
        );
        assert!(out.confidence > 0.4);
        assert!(out.quality_flags.is_empty(), "{:?}", out.quality_flags);
    }

    #[test]
    fn recovers_known_respiratory_rate_at_12_rpm() {
        // 0.2 Hz modulation = 12 breaths/min.
        let rr = synthetic_rr(0.2, 240.0, 950.0, 40.0);
        let rpm = goose_respiratory_rate_v0(&rr)
            .respiratory_rate_rpm
            .expect("rpm computed");
        assert!((rpm - 12.0).abs() <= 2.5, "expected ~12 rpm, got {rpm}");
    }

    #[test]
    fn rejects_short_window() {
        let rr = vec![900.0; 10]; // far under 60s / 30 intervals
        let out = goose_respiratory_rate_v0(&rr);
        assert!(out.respiratory_rate_rpm.is_none());
        assert!(
            out.quality_flags
                .contains(&"respiratory_rsa_window_too_short".to_string())
        );
    }

    #[test]
    fn drops_implausible_intervals() {
        let mut rr = synthetic_rr(0.25, 120.0, 900.0, 40.0);
        rr.extend([50.0, 5000.0, f64::NAN]); // out-of-range get filtered
        let out = goose_respiratory_rate_v0(&rr);
        assert!(out.respiratory_rate_rpm.is_some());
        assert_eq!(out.valid_interval_count, rr.len() - 3);
    }

    #[test]
    fn frequency_hrv_is_hf_dominant_for_fast_oscillation() {
        // 0.25 Hz modulation falls in the HF band (0.15-0.4 Hz).
        let rr = synthetic_rr(0.25, 200.0, 900.0, 45.0);
        let out = goose_hrv_frequency_v0(&rr);
        assert!(out.quality_flags.is_empty(), "{:?}", out.quality_flags);
        assert!(
            out.hf_power_ms2 > out.lf_power_ms2,
            "expected HF>LF, hf={} lf={}",
            out.hf_power_ms2,
            out.lf_power_ms2
        );
        assert!(out.lf_hf_ratio < 1.0);
        assert!(out.hf_normalized > 0.5);
    }

    #[test]
    fn frequency_hrv_is_lf_dominant_for_slow_oscillation() {
        // 0.1 Hz modulation falls in the LF band (0.04-0.15 Hz).
        let rr = synthetic_rr(0.1, 240.0, 900.0, 45.0);
        let out = goose_hrv_frequency_v0(&rr);
        assert!(
            out.lf_power_ms2 > out.hf_power_ms2,
            "expected LF>HF, lf={} hf={}",
            out.lf_power_ms2,
            out.hf_power_ms2
        );
        assert!(out.lf_hf_ratio > 1.0);
    }

    #[test]
    fn frequency_hrv_rejects_short_window() {
        let rr = synthetic_rr(0.25, 40.0, 900.0, 40.0); // under 60s
        let out = goose_hrv_frequency_v0(&rr);
        assert!(out.quality_flags.contains(&"hrv_freq_window_too_short".to_string()));
        assert_eq!(out.total_power_ms2, 0.0);
    }

    #[test]
    fn frequency_hrv_accepts_medium_window_at_elevated_hr() {
        // ~90s of RR at an elevated heart rate (600ms ≈ 100 bpm) must still yield
        // LF/HF — the live RR buffer would otherwise fall under the old 120s gate.
        let rr = synthetic_rr(0.25, 90.0, 600.0, 25.0);
        let out = goose_hrv_frequency_v0(&rr);
        assert!(
            out.quality_flags.is_empty(),
            "expected available LF/HF, got {:?}",
            out.quality_flags
        );
        assert!(out.total_power_ms2 > 0.0);
    }
}
