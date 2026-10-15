class_name ProfileMerge
extends RefCounted

const FIELDS := [
	"unlocked_ids", "seen_content_ids", "tutorial_flags", "summaries_by_run_id", "completed_runs"
]
const SUMMARY_FIELDS := [
	"run_id",
	"result",
	"reason",
	"ending_id",
	"character_id",
	"difficulty",
	"manifest_id",
	"term",
	"statistics",
	"unlocked_ids",
	"seen_content_ids"
]


static func default_profile() -> Dictionary:
	return {
		"unlocked_ids": [],
		"seen_content_ids": [],
		"tutorial_flags": {},
		"summaries_by_run_id": {},
		"completed_runs": 0
	}


static func validate(profile: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	for field in FIELDS:
		if not profile.has(field):
			issues.append("profile.%s is required" % field)
	for field in profile:
		if not FIELDS.has(field):
			issues.append("profile.%s is unknown" % str(field))
	for field in ["unlocked_ids", "seen_content_ids"]:
		_validate_ids(profile.get(field), "profile." + field, issues)
	var flags: Variant = profile.get("tutorial_flags")
	if not flags is Dictionary:
		issues.append("profile.tutorial_flags must be an object")
	else:
		for key in flags:
			if not key is String or key.is_empty() or not flags[key] is bool:
				issues.append(
					"profile.tutorial_flags requires nonempty string keys and boolean values"
				)
	var summaries: Variant = profile.get("summaries_by_run_id")
	if not summaries is Dictionary:
		issues.append("profile.summaries_by_run_id must be an object")
	else:
		for id in summaries:
			if not id is String or id.is_empty() or not summaries[id] is Dictionary:
				issues.append(
					"profile.summaries_by_run_id requires run ID keys and summary objects"
				)
				continue
			_validate_summary(summaries[id], "profile.summaries_by_run_id." + id, issues)
			if summaries[id].get("run_id") != id:
				issues.append("profile summary run_id must match its key")
	if not profile.get("completed_runs") is int or int(profile.get("completed_runs", -1)) < 0:
		issues.append("profile.completed_runs must be a nonnegative integer")
	elif summaries is Dictionary and profile.completed_runs != summaries.size():
		issues.append("profile.completed_runs must equal unique summary count")
	return issues


static func merge(profile: Dictionary, summary: RunSummary) -> GameResult:
	var issues := validate(profile)
	if summary == null:
		issues.append("summary must be finalized")
	if not issues.is_empty():
		return _corrupt(issues)
	var encoded := summary.to_dictionary()
	_validate_summary(encoded, "summary", issues)
	if not issues.is_empty():
		return _corrupt(issues)
	var work := profile.duplicate(true)
	if work.summaries_by_run_id.has(summary.run_id):
		if (
			SnapshotCodec.canonical_json(work.summaries_by_run_id[summary.run_id])
			!= SnapshotCodec.canonical_json(encoded)
		):
			return _corrupt(PackedStringArray(["run_id already has a different finalized summary"]))
	else:
		work.summaries_by_run_id[summary.run_id] = encoded.duplicate(true)
	work.unlocked_ids = _union_ids(work.unlocked_ids, summary.unlocked_ids)
	work.seen_content_ids = _union_ids(work.seen_content_ids, summary.seen_content_ids)
	work.completed_runs = work.summaries_by_run_id.size()
	return GameResult.success(work)


static func _validate_summary(summary: Dictionary, path: String, issues: PackedStringArray) -> void:
	for field in SUMMARY_FIELDS:
		if not summary.has(field):
			issues.append("%s.%s is required" % [path, field])
	for field in summary:
		if not SUMMARY_FIELDS.has(field):
			issues.append("%s.%s is unknown" % [path, str(field)])
	for field in ["run_id", "reason", "character_id", "difficulty", "manifest_id"]:
		if not summary.get(field) is String or str(summary.get(field, "")).is_empty():
			issues.append("%s.%s must be a nonempty string" % [path, field])
	if not summary.get("result") in ["won", "lost", "abandoned"]:
		issues.append(path + ".result must be finalized")
	if not summary.get("ending_id") is String:
		issues.append(path + ".ending_id must be a string")
	if not summary.get("term") is int or int(summary.get("term", 0)) < 1:
		issues.append(path + ".term must be a positive integer")
	if not summary.get("statistics") is Dictionary:
		issues.append(path + ".statistics must be an object")
	for field in ["unlocked_ids", "seen_content_ids"]:
		_validate_ids(summary.get(field), path + "." + field, issues)


static func _validate_ids(value: Variant, path: String, issues: PackedStringArray) -> void:
	if not value is Array:
		issues.append(path + " must be an array")
		return
	var seen := {}
	for id in value:
		if not id is String or str(id).is_empty() or seen.has(id):
			issues.append(path + " must contain unique nonempty strings")
		else:
			seen[id] = true


static func _union_ids(first: Array, second: Array) -> Array[String]:
	var result: Array[String] = []
	for id in first + second:
		if not result.has(id):
			result.append(id)
	result.sort()
	return result


static func _corrupt(issues: PackedStringArray) -> GameResult:
	return GameResult.failure(
		ApiError.new(GameConstants.ERROR_SAVE_CORRUPT, "profile.invalid", {"issues": Array(issues)})
	)
