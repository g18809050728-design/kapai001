extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_check(GameConstants.GODOT_VERSION == "4.7.2.stable", "engine version is pinned", failures)
	_check(GameConstants.SCREEN_MENU == &"menu", "menu screen constant is stable", failures)
	_check(
		GameConstants.ACTION_CHOOSE_EVENT == &"choose_event",
		"event command ID matches the interface contract",
		failures
	)
	_check(
		GameConstants.ACTION_TAKE_REST == &"take_rest",
		"rest command ID matches the interface contract",
		failures
	)

	var error := ApiError.new(
		GameConstants.ERROR_STALE_STATE, "error.command.stale", {"revision": 2}
	)
	var error_data := error.to_dictionary()
	_check(error_data["code"] == "STALE_STATE", "errors serialize stable code values", failures)
	_check(error_data["details"]["revision"] == 2, "errors retain diagnostic details", failures)
	var source_details := {"nested": {"value": 1}}
	var copied_error := ApiError.new(
		GameConstants.ERROR_INVALID_ARGUMENT, "error.input.invalid", source_details
	)
	source_details["nested"]["value"] = 9
	_check(copied_error.details["nested"]["value"] == 1, "error details are copied", failures)

	var failure_result := GameResult.failure(error)
	_check(
		not failure_result.ok and failure_result.error == error,
		"failure result carries an error",
		failures
	)
	var success_result := GameResult.success("ready")
	_check(
		success_result.ok and success_result.data == "ready",
		"success result carries data",
		failures
	)

	var context := CommandContext.new("run_001", 7)
	_check(
		context.run_id == "run_001" and context.expected_revision == 7,
		"command context stores run and revision",
		failures
	)
	var request := StartRunRequest.new("P01", &"normal", "campus_mvp", "42")
	_check(
		request.seed == "42" and request.difficulty == &"normal",
		"start request preserves string seed",
		failures
	)
	var action := GameAction.new(GameConstants.ACTION_PLAY_CARD, {"card_instance_id": "card_001"})
	_check(action.type == &"play_card", "game action carries stable operation name", failures)
	_check(action.payload["card_instance_id"] == "card_001", "game action copies payload", failures)
	var source_payload := {"nested": {"value": 1}}
	var copied_action := GameAction.new(GameConstants.ACTION_PLAY_CARD, source_payload)
	source_payload["nested"]["value"] = 9
	_check(
		copied_action.payload["nested"]["value"] == 1, "action payloads are deep-copied", failures
	)
	var choice := ChoiceRequest.new(
		"choice_001",
		&"discard",
		[ChoiceOption.new("card_001", "card.test", {"cost": 1})],
		0,
		1,
		"choice.discard.prompt",
		"battle_card_001",
		1
	)
	_check(
		choice.candidates[0].label_key == "card.test",
		"choices expose typed option labels",
		failures
	)
	_check(
		choice.prompt_key == "choice.discard.prompt",
		"choice prompt field matches the interface contract",
		failures
	)

	var view := SessionView.new()
	_check(
		view.screen == GameConstants.SCREEN_MENU and view.revision == 0,
		"new session view starts at menu revision zero",
		failures
	)
	view.event_log = [{"data": {"value": 1}}]
	var copied_view := view.copy()
	copied_view.event_log[0]["data"]["value"] = 9
	_check(view.event_log[0]["data"]["value"] == 1, "session views are deep-copied", failures)
	var action_result := ActionResult.new(view)
	_check(
		not action_result.accepted and action_result.stable,
		"action result has explicit safe defaults",
		failures
	)
	_check(
		action_result.view.screen == GameConstants.SCREEN_MENU,
		"action result exposes a view",
		failures
	)

	var session := GameSession.new()
	_check(
		session.get_view().screen == GameConstants.SCREEN_MENU,
		"session returns its initial menu view",
		failures
	)
	var external_view := session.get_view()
	external_view.screen = GameConstants.SCREEN_SUMMARY
	_check(
		session.get_view().screen == GameConstants.SCREEN_MENU,
		"callers cannot mutate session state through views",
		failures
	)
	var unavailable := session.submit(CommandContext.new(), GameAction.new())
	_check(not unavailable.accepted, "commands without a current run fail closed", failures)
	_check(
		unavailable.error.code == GameConstants.ERROR_RUN_NOT_FOUND,
		"missing runs report a stable code",
		failures
	)
	session.free()
	return failures


func _check(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(label)
