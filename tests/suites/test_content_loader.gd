extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	var isolated_root := _copy_fixture()
	var isolated_db := ContentDB.new(isolated_root, true)
	var loaded := isolated_db.load("test_content_loader")
	_check(loaded.ok, "isolated test manifest loads only through opted-in loader", failures)
	if not loaded.ok:
		print(JSON.stringify(loaded.error.to_dictionary()))
		_remove_fixture(isolated_root)
		return failures
	var content_info: ContentInfo = loaded.data
	_check(content_info.id == "test_content_loader", "content info names the fixture", failures)
	_check(content_info.content_hash.length() == 64, "content hash is SHA-256", failures)
	print(
		"G2_TEST_MANIFEST_SHA256=",
		_sha256_file("%s/manifests/test_content_loader.json" % isolated_root)
	)
	print("G2_TEST_FIXTURE_SHA256=", _fixture_hash(isolated_root))
	var implicit_test_load := ContentDB.new(isolated_root).load("test_content_loader")
	_check(
		(
			not implicit_test_load.ok
			and implicit_test_load.error.code == GameConstants.ERROR_CONTENT_INVALID
		),
		"test manifests are rejected unless explicitly opted in",
		failures
	)
	_check(
		isolated_db.get_candidates({"kind": "card", "tags_all": ["test"]}) == ["test_card_001"],
		"candidate queries apply registered filters",
		failures
	)
	_check(
		(
			isolated_db.get_candidates({"kind": "card", "tags_all": "test"}).is_empty()
			and isolated_db.get_candidates({"kind": "card", "terms": "1"}).is_empty()
			and isolated_db.get_candidates({"kind": "card", "unknown": true}).is_empty()
		),
		"candidate queries reject unknown keys and invalid parameter types",
		failures
	)
	var card_result := isolated_db.get_definition("card", "test_card_001")
	_check(card_result.ok, "enabled fixture card is queryable", failures)
	if card_result.ok:
		card_result.data.upgrade.effects[0].amount = 999
		_check(
			isolated_db.get_definition("card", "test_card_001").data.upgrade.effects[0].amount == 2,
			"definition queries return deep copies",
			failures
		)
	var stable_hash := isolated_db.get_info().content_hash

	var production_db := ContentDB.new()
	var test_manifest_in_production := production_db.load("test_content_loader")
	_check(
		not test_manifest_in_production.ok,
		"production loader cannot load a test manifest",
		failures
	)
	var production_load := production_db.load("campus_mvp")
	_check(production_load.ok, "production package loads with enabled starter cards", failures)
	if production_load.ok:
		var ruleset_result := production_db.get_definition("ruleset", "campus_v1")
		_check(ruleset_result.ok, "production Ruleset is queryable", failures)
		if ruleset_result.ok:
			_check(
				(
					ruleset_result.data.run.common_starter_cards
					== ["K01", "K01", "K01", "K01", "K02", "K02", "K02", "K02", "K03", "K04"]
				),
				"production Ruleset keeps its independently configured starter deck",
				failures
			)
		for card_id in ["K01", "K02", "K03", "K04"]:
			var starter_card_result := production_db.get_definition("card", card_id)
			_check(
				starter_card_result.ok and not starter_card_result.data.upgrade.is_empty(),
				"production starter card %s and upgrade are queryable" % card_id,
				failures
			)

	var valid_card := _read_card(isolated_root)
	valid_card.vitality_cost = 4
	valid_card.upgrade.vitality_cost = 3
	_write_card(isolated_root, valid_card)
	var valid_vitality_upgrade := isolated_db.load("test_content_loader")
	_check(
		valid_vitality_upgrade.ok,
		"card upgrade accepts a non-negative vitality_cost patch",
		failures
	)
	if valid_vitality_upgrade.ok:
		stable_hash = isolated_db.get_info().content_hash
	var invalid_vitality_card := valid_card.duplicate(true)
	invalid_vitality_card.upgrade.vitality_cost = -1
	_write_card(isolated_root, invalid_vitality_card)
	_check(
		_not_published_failure(isolated_db, stable_hash),
		"card upgrade rejects a negative vitality_cost without replacing published content",
		failures
	)
	_write_card(isolated_root, valid_card)
	var invalid_card := valid_card.duplicate(true)
	invalid_card.upgrade.effects = [{"op": "unregistered", "amount": 1}]
	_write_card(isolated_root, invalid_card)
	_check(
		_not_published_failure(isolated_db, stable_hash),
		"unknown content op rejects the whole package without replacing published content",
		failures
	)
	invalid_card.upgrade.effects = [{"op": "summon_unit", "unit": "F_missing"}]
	_write_card(isolated_root, invalid_card)
	_check(
		_not_published_failure(isolated_db, stable_hash),
		"disabled references reject the whole package without replacing published content",
		failures
	)
	invalid_card = valid_card.duplicate(true)
	invalid_card.upgrade.target = "unregistered_target"
	_write_card(isolated_root, invalid_card)
	_check(
		_not_published_failure(isolated_db, stable_hash),
		"merged upgrade cards are validated against the complete card schema",
		failures
	)
	_write_json(
		"%s/definitions/cards.json" % isolated_root, [valid_card, valid_card.duplicate(true)]
	)
	_check(
		_not_published_failure(isolated_db, stable_hash),
		"duplicate definition ids reject the whole package",
		failures
	)
	_write_card(isolated_root, valid_card)
	var override_target := {
		"id": "N04",
		"name_key": "encounter.test.name",
		"kind": "normal",
		"members": [],
		"base_ddl": 1,
		"terms": [2, 3],
		"exam_flags": [],
	}
	_check(
		_test_override(isolated_db, isolated_root, override_target, [1], true, [1], stable_hash),
		"approved MVP override applies to a deep-copied enabled definition",
		failures
	)
	_check(
		_test_override(isolated_db, isolated_root, override_target, [9], false, [], stable_hash),
		"unapproved override values reject the package atomically",
		failures
	)
	_check(
		_test_override(
			isolated_db, isolated_root, override_target, [1], false, [], stable_hash, "other.v1"
		),
		"override scope version must match the manifest content version",
		failures
	)

	var valid_statuses: Array = _read_json("%s/definitions/statuses.json" % isolated_root)
	var statuses: Array = valid_statuses.duplicate(true)
	for status in statuses:
		if status.id == "inspiration":
			status.duration_policy = "battle"
	_write_json("%s/definitions/statuses.json" % isolated_root, statuses)
	_check(
		_not_published_failure(isolated_db, stable_hash),
		"status lifecycle must match its registered policy",
		failures
	)
	_write_json("%s/definitions/statuses.json" % isolated_root, valid_statuses)
	var valid_rulesets: Array = _read_json("%s/definitions/rulesets.json" % isolated_root)
	var rulesets: Array = valid_rulesets.duplicate(true)
	rulesets[0].statuses.inspiration.erase("completion_per_stack")
	_write_json("%s/definitions/rulesets.json" % isolated_root, rulesets)
	_check(
		_not_published_failure(isolated_db, stable_hash),
		"status coefficient groups require their exact schema",
		failures
	)
	_write_json("%s/definitions/rulesets.json" % isolated_root, valid_rulesets)
	var bad_event := {
		"id": "test_event_001",
		"name_key": "event.test.name",
		"terms": [1],
		"once_per_run": false,
		"options":
		[
			{"option_id": "buy", "label_key": "event.buy", "cost": {"money": true}, "effects": []},
			{"option_id": "leave", "label_key": "event.leave", "cost": {}, "effects": []},
		],
	}
	_check(
		_reject_definition(isolated_db, isolated_root, "event", bad_event, stable_hash),
		"event costs reject boolean values",
		failures
	)
	var bad_task := {
		"id": "test_task_001",
		"name_key": "task.test.name",
		"kind": "normal",
		"phases": [{"phase_key": "main", "work_max": 1, "intents": [{"index": 0}]}],
	}
	_check(
		_reject_definition(isolated_db, isolated_root, "task", bad_task, stable_hash),
		"task intents require their text key and registered fields",
		failures
	)
	var bad_unit := {
		"id": "test_unit_001",
		"name_key": "unit.test.name",
		"vitality": 1,
		"cooperation": 0,
		"guard": false,
		"support": {"kind": "relax"},
	}
	_check(
		_reject_definition(isolated_db, isolated_root, "unit", bad_unit, stable_hash),
		"unit support requires kind-specific fields",
		failures
	)
	var bad_scene := {
		"id": "test_scene_001",
		"name_key": "scene.test.name",
		"modifiers": {"unregistered": 1},
	}
	_check(
		_reject_definition(isolated_db, isolated_root, "scene", bad_scene, stable_hash),
		"scene modifiers reject unregistered keys",
		failures
	)
	var bad_relic := {
		"id": "test_relic_001",
		"name_key": "relic.test.name",
		"availability": "starter",
		"rarity": null,
		"tags": [],
		"hooks":
		[{"at": "round_start", "effects": [{"op": "gain_focus", "amount": 1}], "discount": 1}],
	}
	_check(
		_reject_definition(isolated_db, isolated_root, "relic", bad_relic, stable_hash),
		"hook keys are scoped to their registered timing point",
		failures
	)
	_remove_fixture(isolated_root)
	return failures


func _not_published_failure(content_db: ContentDB, stable_hash: String) -> bool:
	var result := content_db.load("test_content_loader")
	return not result.ok and content_db.get_info().content_hash == stable_hash


func _reject_definition(
	content_db: ContentDB, root: String, kind: String, definition: Dictionary, stable_hash: String
) -> bool:
	var manifest_path := "%s/manifests/test_content_loader.json" % root
	var manifest: Dictionary = _read_json(manifest_path)
	manifest.enabled[kind] = [definition.id]
	_write_json(manifest_path, manifest)
	var definitions_path := "%s/definitions/%s.json" % [root, ContentDB.FILE_NAMES[kind]]
	_write_json(definitions_path, [definition])
	var rejected := _not_published_failure(content_db, stable_hash)
	manifest.enabled[kind] = []
	_write_json(manifest_path, manifest)
	_write_json(definitions_path, [])
	return rejected


func _test_override(
	content_db: ContentDB,
	root: String,
	target: Dictionary,
	terms: Array[int],
	expects_success: bool,
	expected_terms: Array[int],
	stable_hash: String,
	override_scope: String = "campus_mvp.v1"
) -> bool:
	var manifest_path := "%s/manifests/test_content_loader.json" % root
	var manifest: Dictionary = _read_json(manifest_path)
	manifest.enabled.encounter = ["N04"]
	manifest.overrides = [
		{
			"kind": "encounter",
			"id": "N04",
			"scope_version": override_scope,
			"source": {"path": "docs/交大四年_DDL战争_项目计划书.md", "section": "§3.1"},
			"patch": {"terms": terms},
		}
	]
	_write_json(manifest_path, manifest)
	_write_json("%s/definitions/encounters.json" % root, [target])
	var result := content_db.load("test_content_loader")
	var valid := result.ok == expects_success
	if expects_success:
		if result.ok:
			var applied := content_db.get_definition("encounter", "N04")
			valid = valid and applied.ok and applied.data.terms == expected_terms
			if applied.ok:
				applied.data.terms.clear()
				valid = (
					valid
					and content_db.get_definition("encounter", "N04").data.terms == expected_terms
				)
	else:
		valid = valid and content_db.get_info().content_hash == stable_hash
	manifest.enabled.encounter = []
	manifest.overrides = []
	_write_json(manifest_path, manifest)
	_write_json("%s/definitions/encounters.json" % root, [])
	var restored := content_db.load("test_content_loader")
	return valid and restored.ok and content_db.get_info().content_hash == stable_hash


func _remove_fixture(root: String) -> void:
	for file_name in ContentDB.FILE_NAMES.values():
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path("%s/definitions/%s.json" % [root, file_name])
		)
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path("%s/manifests/test_content_loader.json" % root)
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/definitions" % root))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/manifests" % root))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root))


func _copy_fixture() -> String:
	var root := ProjectSettings.globalize_path(
		"res://.godot/g2_content_fixture_%d" % Time.get_ticks_usec()
	)
	var absolute_root := ProjectSettings.globalize_path(root)
	for directory in ["definitions", "manifests"]:
		DirAccess.make_dir_recursive_absolute("%s/%s" % [absolute_root, directory])
	for file_name in ContentDB.FILE_NAMES.values():
		_write_file(
			"%s/definitions/%s.json" % [root, file_name],
			FileAccess.get_file_as_string(
				"res://tests/fixtures/content_loader/definitions/%s.json" % file_name
			)
		)
	_write_file(
		"%s/manifests/test_content_loader.json" % root,
		FileAccess.get_file_as_string(
			"res://tests/fixtures/content_loader/manifests/test_content_loader.json"
		)
	)
	return root


func _read_card(root: String) -> Dictionary:
	var cards: Array = _read_json("%s/definitions/cards.json" % root)
	return cards[0].duplicate(true)


func _read_json(path: String) -> Variant:
	var parser := JSON.new()
	var source := FileAccess.get_file_as_string(path)
	assert(parser.parse(source) == OK, "could not parse fixture JSON %s" % path)
	return parser.data


func _write_card(root: String, card: Dictionary) -> void:
	_write_json("%s/definitions/cards.json" % root, [card])


func _write_json(path: String, value: Variant) -> void:
	_write_file(path, JSON.stringify(_normalize_numbers(value)))


func _normalize_numbers(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT and is_equal_approx(value, round(value)):
		return int(value)
	if typeof(value) == TYPE_DICTIONARY:
		var normalized := {}
		for key in value:
			normalized[key] = _normalize_numbers(value[key])
		return normalized
	if typeof(value) == TYPE_ARRAY:
		var normalized: Array = []
		for item in value:
			normalized.append(_normalize_numbers(item))
		return normalized
	return value


func _write_file(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "could not write test fixture %s" % path)
	file.store_string(value)


func _fixture_hash(root: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var files: Array[String] = ["manifests/test_content_loader.json"]
	for file_name in ContentDB.FILE_NAMES.values():
		files.append("definitions/%s.json" % file_name)
	files.sort()
	for relative_path in files:
		context.update(relative_path.to_utf8_buffer())
		context.update(PackedByteArray([0]))
		context.update(FileAccess.get_file_as_bytes("%s/%s" % [root, relative_path]))
	return context.finish().hex_encode()


func _sha256_file(path: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode()


func _check(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(label)
