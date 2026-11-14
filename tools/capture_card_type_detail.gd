extends SceneTree

const OUT := "res://artifacts/verification/map-card-feedback-20261114/card-detail-final"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var catalog := ContentDB.new("res://data/four_year")
	if not catalog.load("campus_four_year").ok:
		quit(1)
		return
	var ids := ["R3-C-01","R3-C-02","R3-C-03","R3-C-08","R3-C-06"]
	var models: Array[Dictionary] = []
	for id in ids:
		models.append(CardDisplayModel.from_card(catalog.get_definition("card",id).data))
	# The current production pool has no burden definition. This last face is
	# a presentation fixture exercising the preserved torn-page fallback only.
	var burden := CardDisplayModel.from_card({"type":"burden","cost":"—","effects":[]})
	burden["name"] = "负担示例"
	burden["summary"] = "类型角标渲染样本"
	models.append(burden)
	var rows: Array = []
	for dimensions in [Vector2i(1280,800),Vector2i(960,600)]:
		root.size = dimensions
		var stage := Control.new()
		stage.theme = UiStyle.make_theme()
		root.add_child(stage)
		var background := ColorRect.new()
		background.color = Color("142932")
		background.size = Vector2(dimensions)
		stage.add_child(background)
		var heading := Label.new()
		heading.text = "保留六种类型图形 · 大牌 / 小牌共用真实费用"
		heading.position = Vector2(28,12)
		heading.add_theme_font_size_override("font_size",22)
		heading.add_theme_color_override("font_color",Color("f0dfbb"))
		stage.add_child(heading)
		var width := minf(minf(250,(dimensions.x-80)/3.0),(dimensions.y-84)*.5*168/244)
		for index in models.size():
			var face := CardFaceView.new()
			face.configure(models[index])
			face.position = Vector2(32+(index%3)*(dimensions.x-40)/3.0,52+(index/3)*(dimensions.y-52)/2.0)
			face.size = Vector2(width,width*244/168)
			stage.add_child(face)
			if face.position.y+face.size.y > dimensions.y-4:
				face.size *= (dimensions.y-face.position.y-8)/face.size.y
			rows.append({"size":str(dimensions),"category":models[index].category,"cost":models[index].cost,"fixture":index==5})
		for frame in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(OUT.path_join("six-types-%d.png" % dimensions.x))
		if error != OK:
			push_error("Card detail capture failed")
			quit(1)
			return
		stage.free()
	var file := FileAccess.open(OUT.path_join("capture.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"\t"))
	quit(0)
