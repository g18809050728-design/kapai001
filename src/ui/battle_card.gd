class_name BattleCard
extends Button

const FACE_SIZE := Vector2(168, 244)
var card_data: Dictionary = {}
var selected: bool = false
var highlighted: bool = false
var home_position := Vector2.ZERO
var home_rotation: float = 0.0
var home_scale: float = 1.0
var home_order: int = 0
var shortcut_index: int = 0
var accent := Color("739d95")


func configure(data: Dictionary, is_selected: bool = false, face_size: Vector2 = FACE_SIZE) -> void:
	card_data = data.duplicate(true)
	selected = is_selected
	size = face_size
	custom_minimum_size = face_size
	pivot_offset = face_size * 0.5
	text = UiStyle.label(str(data.get("definition_id", "")))
	var face: Dictionary = data.get("face", data.get("effective_card", {}))
	var kind := str(face.get("type", face.get("card_type", "work")))
	accent = (
		{
			"strategy": Color("6989a1"),
			"cooperation": Color("7c9d74"),
			"scene": Color("b49765"),
			"burden": Color("a26767")
		}
		. get(kind, Color("739d95"))
	)
	queue_redraw()


func _draw() -> void:
	CardFaceView.paint(self, Rect2(Vector2.ZERO, size), CardDisplayModel.from_card(card_data), selected or highlighted, disabled, shortcut_index, true)


func contains_global(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(
		get_global_transform_with_canvas().affine_inverse() * point
	)


func contains_home(point: Vector2) -> bool:
	var local: Vector2 = get_parent().get_global_transform_with_canvas().affine_inverse() * point
	var transform := Transform2D(home_rotation, Vector2.ONE * home_scale, 0.0, home_position + pivot_offset)
	return Rect2(-pivot_offset, size).has_point(transform.affine_inverse() * local)
