class_name ActionPreview
extends RefCounted

var revision: int = -1
var can_submit: bool = false
var required_selections: Array[Dictionary] = []
var costs: Dictionary = {}
var known_effects: Array[Dictionary] = []
var unknown_effects: Array[Dictionary] = []
var effective_card: Dictionary = {}
var blocking_errors: Array[ApiError] = []
