class_name ScoreManager
extends RefCounted

const LIGHTNING_TIME: float = 20.0
const GREAT_TIME: float = 35.0
const NICE_TIME: float = 50.0

func calculate(
	success: bool,
	time_limit: float,
	time_remaining: float,
	items_total: int,
	items_remaining: int
) -> Dictionary:
	var used := maxf(time_limit - time_remaining, 0.0)
	var score: int = 0
	var tier: String = ""

	if success:
		if used <= LIGHTNING_TIME:
			score = 1000
			tier = "★★★  Lightning fast!"
		elif used <= GREAT_TIME:
			score = 750
			tier = "★★  Great escape!"
		elif used <= NICE_TIME:
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
