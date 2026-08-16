class_name ExperimentProtocol
extends Resource
## 离线行为分析协议。阈值写入 results/analysis_manifest.json，不单独成表。

const ANALYSIS_VERSION: String = "2.2.0"

@export_range(0.0, 1.0, 0.01) var activity_threshold: float = 0.20
@export_range(-1.0, 1.0, 0.01) var conflict_cosine_threshold: float = -0.50
@export var sustained_start_ms: float = 100.0
@export var force_smoothing_ms: float = 100.0
@export var cross_correlation_max_lag_ms: float = 1000.0
@export var cross_correlation_min_active_ms: float = 500.0

@export var perturbation_baseline_ms: float = 200.0
@export var compensation_projection_threshold: float = 0.12
@export var compensation_sustain_ms: float = 100.0
@export var compensation_error_check_ms: float = 400.0
@export_range(0.0, 1.0, 0.01) var compensation_error_drop_ratio: float = 0.05
@export var compensation_min_error: float = 2.0

@export var recovery_sustain_ms: float = 500.0
@export var recovery_mad_multiplier: float = 3.0
@export var recovery_error_floor: float = 3.0
@export var recovery_speed_floor: float = 8.0
@export var recovery_angular_speed_floor: float = 0.15

@export var overshoot_hysteresis: float = 2.0
@export var minimum_effective_sample_hz: float = 55.0
@export_range(0.0, 100.0, 0.1) var maximum_frame_drop_pct: float = 5.0
@export_range(0.2, 1.0, 0.01) var review_fraction: float = 0.20
@export var review_window_before_ms: float = 2000.0
@export var review_window_after_ms: float = 2000.0
@export var manual_onset_tolerance_ms: float = 100.0

func metadata() -> Dictionary:
	return {
		"analysis_version": ANALYSIS_VERSION,
		"activity_threshold": activity_threshold,
		"conflict_cosine_threshold": conflict_cosine_threshold,
		"sustained_start_ms": sustained_start_ms,
		"force_smoothing_ms": force_smoothing_ms,
		"cross_correlation_max_lag_ms": cross_correlation_max_lag_ms,
		"cross_correlation_min_active_ms": cross_correlation_min_active_ms,
		"perturbation_baseline_ms": perturbation_baseline_ms,
		"compensation_projection_threshold": compensation_projection_threshold,
		"compensation_sustain_ms": compensation_sustain_ms,
		"compensation_error_check_ms": compensation_error_check_ms,
		"compensation_error_drop_ratio": compensation_error_drop_ratio,
		"compensation_min_error": compensation_min_error,
		"recovery_sustain_ms": recovery_sustain_ms,
		"recovery_mad_multiplier": recovery_mad_multiplier,
		"recovery_error_floor": recovery_error_floor,
		"recovery_speed_floor": recovery_speed_floor,
		"recovery_angular_speed_floor": recovery_angular_speed_floor,
		"overshoot_hysteresis": overshoot_hysteresis,
		"minimum_effective_sample_hz": minimum_effective_sample_hz,
		"maximum_frame_drop_pct": maximum_frame_drop_pct,
		"review_fraction": review_fraction,
		"review_window_before_ms": review_window_before_ms,
		"review_window_after_ms": review_window_after_ms,
		"manual_onset_tolerance_ms": manual_onset_tolerance_ms,
	}
