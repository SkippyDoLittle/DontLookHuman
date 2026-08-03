class_name ScoreManager
extends RefCounted

const DEFAULT_LIGHTNING_TIME: float = 20.0
const DEFAULT_GREAT_TIME: float = 35.0
const DEFAULT_NICE_TIME: float = 50.0

static func default_thresholds() -> Array[float]:
	return [DEFAULT_LIGHTNING_TIME, DEFAULT_GREAT_TIME, DEFAULT_NICE_TIME]

func calculate(
	success: bool,
	time_limit: float,
	time_remaining: float,
	items_total: int,
	items_remaining: int,
	grade_thresholds: Array[float] = []
) -> Dictionary:
	var used := maxf(time_limit - time_remaining, 0.0)
	var score: int = 0
	var tier: String = ""
	var thresholds := grade_thresholds if grade_thresholds.size() == 3 else default_thresholds()
	var lightning_time: float = thresholds[0]
	var great_time: float = maxf(thresholds[1], lightning_time)
	var nice_time: float = maxf(thresholds[2], great_time)

	if success:
		if used <= lightning_time:
			score = 1000
			tier = "★★★  Lightning fast!"
		elif used <= great_time:
			score = 750
			tier = "★★  Great escape!"
		elif used <= nice_time:
			score = 500
			tier = "★  Nice work!"
		else:
			score = 250
			tier = "Completed"

	return {
		"score": score,
		"tier": tier,
		"minutes": int(used / 60.0),
		"seconds": int(used) % 60,
		"collected": maxi(items_total - items_remaining, 0),
		"total": items_total,
	}
