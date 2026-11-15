extends SceneTree

## Reproducible static UI images from the exact selected in-game neutral rigs.
func _initialize() -> void:
	call_deferred("_render")


func _render() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 1400)
	viewport.world_2d = World2D.new()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var records := []
	for id: String in CharacterArt.RIGS:
		var rig := NativeActorRig.new()
		viewport.add_child(rig)
		if not rig.configure(CharacterArt.rig_path(id)):
			quit(1)
			return
		rig.fit(Vector2(1024, 1380))
		rig.set_motion(false)
		await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var head := rig.parts.head as Sprite2D
		var head_bounds: Rect2 = head.global_transform * head.get_rect()
		# Include the hair silhouette and collar; use the same transparent image.
		var side := mini(1024, ceili(maxf(head_bounds.size.x, head_bounds.size.y) * 1.5))
		var origin := head_bounds.get_center() - Vector2.ONE * side * .5 + Vector2(0, head_bounds.size.y * .1)
		var crop := Rect2i(Vector2i(clampi(roundi(origin.x), 0, 1024 - side), clampi(roundi(origin.y), 0, 1400 - side)), Vector2i.ONE * side)
		var output := CharacterArt.texture_path(id).get_base_dir()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
		var neutral_error := image.save_png(CharacterArt.texture_path(id))
		var portrait := image.get_region(crop)
		portrait.resize(256, 256, Image.INTERPOLATE_LANCZOS)
		var portrait_error := portrait.save_png(CharacterArt.texture_path(id, true))
		records.append({"character": id, "version": rig.specification.version, "rig": CharacterArt.rig_path(id),
			"neutral": CharacterArt.texture_path(id), "portrait": CharacterArt.texture_path(id, true),
			"portrait_crop": [crop.position.x, crop.position.y, crop.size.x, crop.size.y],
			"neutral_error": neutral_error, "portrait_error": portrait_error})
		rig.free()
		if neutral_error != OK or portrait_error != OK:
			quit(1)
			return
	viewport.free()
	var manifest := FileAccess.open("res://assets/art/characters/source.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"source": "selected neutral native rigs, rendered in Godot; no new AI artwork", "engine": Engine.get_version_info(), "characters": records}, "\t"))
	manifest.close()
	print("CHARACTER_ART_RENDERED=", records.size())
	quit(0)
