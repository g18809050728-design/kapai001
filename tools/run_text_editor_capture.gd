extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var capture = load("res://tools/capture_text_editor.gd").new()
	var exit_code: int = await capture.run(self)
	capture = null
	quit(exit_code)
