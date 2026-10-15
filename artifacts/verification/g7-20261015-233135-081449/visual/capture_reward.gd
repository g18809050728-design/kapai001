extends SceneTree

const OUTPUT := "res://artifacts/verification/g7-20261015-233135-081449/visual"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1280, 800)
	var catalog := ContentDB.new()
	if not catalog.load("campus_mvp").ok:
		quit(1)
		return
	var service := RunService.new(catalog)
	var result := service.create(StartRunRequest.new("P01", &"normal", "campus_mvp", "42"))
	if not result.ok:
		quit(1)
		return
	var state: RunState = result.data.state
	state.pending_reward = RewardOffer.new({
		"offer_id": "visual_feedback",
		"source_node_id": "visual_feedback_node",
		"items": [{
			"item_id": "cards", "kind": "card", "status": "pending",
			"candidates": ["K05", "K43", "K51"], "skippable": true
		}]
	})
	var page := UiFlowPage.new()
	page.screen = "reward"
	page.theme = UiStyle.make_theme()
	root.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.render(service.make_view(state))
	for frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	var code := screenshot.save_png(OUTPUT.path_join("reward-details.png"))
	var record := {
		"controlled_reward_display": true,
		"production_manifest": "campus_mvp",
		"candidates": ["K05", "K43", "K51"],
		"size": [screenshot.get_width(), screenshot.get_height()],
		"save_error": code,
		"player_save_accessed": false
	}
	var file := FileAccess.open(OUTPUT.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(record, "\t"))
	file.close()
	print("G7_REWARD_VISUAL " + JSON.stringify(record))
	page.free()
	quit(0 if code == OK else 1)
