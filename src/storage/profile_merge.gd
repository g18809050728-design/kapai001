class_name ProfileMerge
extends RefCounted
##
## Profile 与 RunSummary 的幂等合并（《数据库与实体关系设计》§8「结局写入Profile」）。
##
## 契约：
##   · 同一 run_id 只记一份摘要（summaries_by_run_id），重复合并不会重复计数。
##   · completed_runs 直接由去重摘要数量导出，不做增量累加。
##   · unlocked_ids / seen_content_ids 取并集并排序，保证同内容得到同 checksum。
##   · career_progress 按轨取较大值；tutorial_flags 只置 true。
##   · 只做纯数据合并，不碰磁盘；三步提交的文件顺序由 SaveStore.commit_pending_profile 负责。
##

const GameConstants := preload("res://src/common/game_constants.gd")
const Result := preload("res://src/common/result.gd")

const KEY_UNLOCKED := "unlocked_ids"
const KEY_SEEN := "seen_content_ids"
const KEY_TUTORIAL := "tutorial_flags"
const KEY_SUMMARIES := "summaries_by_run_id"
const KEY_COMPLETED := "completed_runs"
const KEY_CAREER := "career_progress"


static func empty_profile() -> Dictionary:
        return {
                KEY_UNLOCKED: [],
                KEY_SEEN: [],
                KEY_TUTORIAL: {},
                KEY_SUMMARIES: {},
                KEY_CAREER: {},
                KEY_COMPLETED: 0,
        }


static func is_merged(profile: Dictionary, run_id: String) -> bool:
        if typeof(profile) != TYPE_DICTIONARY or run_id.is_empty():
                return false
        var summaries: Variant = profile.get(KEY_SUMMARIES)
        if typeof(summaries) != TYPE_DICTIONARY:
                return false
        return (summaries as Dictionary).has(run_id)


## Result<Dictionary>：profile + summary -> 新 profile（不修改入参）。
static func merge(profile: Dictionary, summary: Dictionary) -> Dictionary:
        if typeof(profile) != TYPE_DICTIONARY or typeof(summary) != TYPE_DICTIONARY:
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.profile.bad_input", {})
        var run_id := String(summary.get("run_id", ""))
        if run_id.is_empty():
                return Result.fail(GameConstants.ERROR_INVALID_ARGUMENT, "error.profile.missing_run_id", {})
        var merged := empty_profile()
        merged[KEY_UNLOCKED] = _string_array(profile.get(KEY_UNLOCKED))
        merged[KEY_SEEN] = _string_array(profile.get(KEY_SEEN))
        merged[KEY_TUTORIAL] = _truthy_dict(profile.get(KEY_TUTORIAL))
        merged[KEY_SUMMARIES] = _dict_copy(profile.get(KEY_SUMMARIES))
        merged[KEY_CAREER] = _dict_copy(profile.get(KEY_CAREER))
        _merge_summary(merged, summary)
        merged[KEY_COMPLETED] = (merged[KEY_SUMMARIES] as Dictionary).size()
        return Result.ok(merged)


static func _merge_summary(merged: Dictionary, summary: Dictionary) -> void:
        var run_id := String(summary.get("run_id", ""))
        var summaries: Dictionary = merged[KEY_SUMMARIES]
        if not summaries.has(run_id):
                summaries[run_id] = summary.duplicate(true)
        _union_strings(merged[KEY_UNLOCKED], summary.get(KEY_UNLOCKED))
        _union_strings(merged[KEY_SEEN], summary.get(KEY_SEEN))
        _union_truthy(merged[KEY_TUTORIAL], summary.get(KEY_TUTORIAL))
        _merge_career(merged[KEY_CAREER], summary.get(KEY_CAREER))


static func _union_strings(target: Array, raw: Variant) -> void:
        if typeof(raw) != TYPE_ARRAY:
                return
        var seen := {}
        for item in target:
                seen[String(item)] = true
        for item in (raw as Array):
                var text := String(item)
                if text.is_empty() or seen.has(text):
                        continue
                seen[text] = true
                target.append(text)
        target.sort()


static func _union_truthy(target: Dictionary, raw: Variant) -> void:
        if typeof(raw) != TYPE_DICTIONARY:
                return
        for key in (raw as Dictionary):
                if bool((raw as Dictionary)[key]):
                        target[String(key)] = true


static func _merge_career(target: Dictionary, raw: Variant) -> void:
        if typeof(raw) != TYPE_DICTIONARY:
                return
        for key in (raw as Dictionary):
                var track := String(key)
                var value := int((raw as Dictionary)[key])
                if not target.has(track) or value > int(target[track]):
                        target[track] = value


static func _string_array(raw: Variant) -> Array:
        var result := []
        if typeof(raw) != TYPE_ARRAY:
                return result
        for item in (raw as Array):
                var text := String(item)
                if not text.is_empty() and not result.has(text):
                        result.append(text)
        result.sort()
        return result


static func _truthy_dict(raw: Variant) -> Dictionary:
        var result := {}
        if typeof(raw) != TYPE_DICTIONARY:
                return result
        for key in (raw as Dictionary):
                if bool((raw as Dictionary)[key]):
                        result[String(key)] = true
        return result


static func _dict_copy(raw: Variant) -> Dictionary:
        if typeof(raw) == TYPE_DICTIONARY:
                return (raw as Dictionary).duplicate(true)
        return {}