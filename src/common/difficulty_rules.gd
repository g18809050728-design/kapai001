class_name DifficultyRules
extends RefCounted


static func scale_pressure(amount: int, difficulty: String, rules: Dictionary) -> int:
	var percent := int(rules.get("difficulty_overrides", {}).get(difficulty, {}).get("pressure_percent", 100))
	return ceili(maxi(0, amount) * percent / 100.0)


static func description(settings: Dictionary) -> String:
	return "开局精力 %d · DDL %+d · 意图压力 %d%%" % [int(settings.get("starting_vitality", 72)), int(settings.get("ddl_offset", 0)), int(settings.get("pressure_percent", 100))]
