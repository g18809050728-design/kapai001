extends SceneTree

const OUT := "res://artifacts/verification/non-character-vfx-20261114"
const KINDS := ["work_light", "work_heavy", "pressure_hit", "guard_gain", "guard_absorb", "guard_break", "heal", "resource_gain", "resource_spend", "status_attach", "status_decay", "status_remove", "phase", "partner"]
const COLORS := ["e9c77b", "f6c96b", "ec967e", "91c7e8", "91c7e8", "91c7e8", "98d7b3", "d2c3f0", "e0b784", "adcad2", "adcad2", "adcad2", "e6c58d", "99cbb2"]


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1400,640)
	var records: Array = []
	for background in ["20313d","f1eadc"]:
		var stage := Control.new()
		stage.theme = UiStyle.make_theme()
		root.add_child(stage)
		var backdrop := ColorRect.new()
		backdrop.color = Color(background)
		backdrop.size = Vector2(root.size)
		stage.add_child(backdrop)
		var effects: Array[BattleSemanticEffectView] = []
		for index in KINDS.size():
			var column := index % 7
			var row := index / 7
			var effect := BattleSemanticEffectView.new()
			effect.kind = KINDS[index]
			effect.ink = Color(COLORS[index])
			effect.position = Vector2(column*200+26,row*300+44)
			effect.size = Vector2(148,148)
			stage.add_child(effect)
			effects.append(effect)
			var label := Label.new()
			label.text = KINDS[index]
			label.position = Vector2(column*200+8,row*300+204)
			label.add_theme_font_size_override("font_size",17)
			label.add_theme_color_override("font_color",Color("dce4e4") if background == "20313d" else Color("344653"))
			stage.add_child(label)
		for sample in [.12,.32,.52,.76]:
			for effect in effects:
				effect.progress = sample
			await process_frame
			await RenderingServer.frame_post_draw
			var file := "native-%s-%02d.png" % [background,roundi(sample*100)]
			var error := root.get_texture().get_image().save_png(OUT.path_join(file))
			if error != OK:
				push_error("Native VFX capture failed: " + file)
				quit(1)
				return
			records.append({"file":file,"progress":sample,"background":background,"kinds":KINDS})
		stage.free()
	var report := FileAccess.open(OUT.path_join("native-captures.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify(records,"\t"))
	report.close()
	print("NATIVE_VFX_RESOURCE_CAPTURE=passed images=",records.size())
	quit(0)
