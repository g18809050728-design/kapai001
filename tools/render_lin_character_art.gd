extends SceneTree

func _initialize() -> void:
	call_deferred("_render")


func _render() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 1400)
	viewport.world_2d = World2D.new()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var rig := NativeActorRig.new()
	viewport.add_child(rig)
	if not rig.configure(CharacterArt.rig_path("P01")) or int(rig.specification.version) != 12:
		quit(1)
		return
	rig.fit(Vector2(1024, 1380))
	rig.set_motion(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var head := rig.parts.head as Sprite2D
	var bounds: Rect2 = head.global_transform * head.get_rect()
	var side := mini(1024, ceili(maxf(bounds.size.x, bounds.size.y) * 1.5))
	var origin := bounds.get_center() - Vector2.ONE * side * .5 + Vector2(0, bounds.size.y * .1)
	var crop := Rect2i(Vector2i(clampi(roundi(origin.x), 0, 1024-side), clampi(roundi(origin.y), 0, 1400-side)),Vector2i.ONE*side)
	var error := image.save_png(CharacterArt.texture_path("P01"))
	var portrait := image.get_region(crop)
	portrait.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	var portrait_error := portrait.save_png(CharacterArt.texture_path("P01", true))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/characters/source.json"))
	for index in manifest.characters.size():
		if manifest.characters[index].character == "P01":
			manifest.characters[index] = {"character":"P01", "version":12, "rig":CharacterArt.rig_path("P01"),
				"neutral":CharacterArt.texture_path("P01"), "portrait":CharacterArt.texture_path("P01",true),
				"portrait_crop":[crop.position.x,crop.position.y,crop.size.x,crop.size.y],
				"neutral_error":error,"portrait_error":portrait_error}
	manifest.source = "selected neutral native rigs, rendered in Godot; P01 V12 refined from same-source AI artwork"
	manifest.p01_renderer = "res://tools/render_lin_character_art.gd"
	var file := FileAccess.open("res://assets/art/characters/source.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest,"\t"))
	file.close()
	viewport.free()
	print("LIN_STATIC_ART_RENDERED=", error == OK and portrait_error == OK)
	quit(0 if error == OK and portrait_error == OK else 1)
