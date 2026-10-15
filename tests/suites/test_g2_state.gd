extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	var run := (
		RunState
		. new(
			{
				"run_id": "run_test_001",
				"character_id": "P01",
				"ruleset_id": "campus_v1",
				"manifest_id": "campus_mvp",
				"vitality": 72,
				"max_vitality": 72,
				"cards": [{"card_id": "card_000001", "definition_id": "K01"}],
			}
		)
	)
	_check(
		run.next_instance_id("card") == "card_000001",
		"run generates deterministic instance ids",
		failures
	)
	_check(
		run.next_instance_id("relic") == "relic_000002",
		"instance ids share one monotonic sequence",
		failures
	)
	var copied_run := run.copy()
	copied_run.cards[0].definition_id = "K60"
	_check(run.cards[0].definition_id == "K01", "run copies nested card state", failures)
	var battle := (
		BattleState
		. new(
			{
				"battle_id": "battle_test_001",
				"phase": "player_action",
				"round_index": 1,
				"player": {"vitality": 72},
				"tasks": [{"definition_id": "N01", "work_remaining": 24}],
				"zones": {"draw": ["card_000001"]},
			}
		)
	)
	var copied_battle := battle.copy()
	copied_battle.tasks[0].work_remaining = 0
	copied_battle.zones.draw.clear()
	_check(battle.tasks[0].work_remaining == 24, "battle copies nested task state", failures)
	_check(battle.zones.draw == ["card_000001"], "battle copies nested zone state", failures)
	return failures


func _check(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(label)
