class_name ProfileView
extends RefCounted

var available: bool = false
var unlocked_characters: Array[String] = []
var unlocked_endings: Array[String] = []
var completed_run_ids: Array[String] = []
var autosave: bool = true
var unlocked_ids: Array[String] = []
var seen_content_ids: Array[String] = []
var tutorial_flags: Dictionary = {}
var error: ApiError
var settings_error: ApiError
