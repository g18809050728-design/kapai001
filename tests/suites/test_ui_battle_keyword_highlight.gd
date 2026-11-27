extends RefCounted

var _failures: Array[String] = []
var _checks := 0


func run() -> Array[String]:
	var glossary := "专注：支付卡牌费用的资源。\n状态完成量：由任务状态产生的完成量。\n完成量：减少当前任务阶段。\n"
	var terms := UiContentText.glossary_terms(glossary)
	_check(terms.size() == 3, "parses three distinct glossary terms")
	_check(terms.has("专注") and terms.has("状态完成量") and terms.has("完成量"), "keeps every displayed term")
	_check(UiContentText.glossary_terms("专注:半角冒号") == ["专注"], "accepts a half-width colon")
	_check(UiContentText.glossary_terms("专注：a\n专注：b").size() == 1, "deduplicates repeated terms")
	_check(UiContentText.glossary_terms("没有冒号").is_empty(), "ignores lines without a term separator")

	var text := "作业 · 专注 1\n对所选任务造成6点状态完成量；随后获得专注"
	var segments := UiContentText.highlight_segments(text, terms)
	_check(_joined(segments) == text, "highlighting preserves the exact plain text")
	var highlighted := _highlighted(segments)
	_check(highlighted.has("专注") and highlighted.has("状态完成量"), "highlights terms that occur in the text")
	_check(not highlighted.has("完成量"), "longest overlapping term wins instead of its substring")
	_check(highlighted.count("专注") == 2, "highlights every occurrence of a repeated term")

	var overlap := UiContentText.highlight_segments("状态完成量", ["完成量", "状态完成量"])
	_check(_highlighted(overlap) == ["状态完成量"], "overlapping matches do not nest short terms")

	var plain := UiContentText.highlight_segments("放松 3", [])
	_check(_joined(plain) == "放松 3" and _highlighted(plain).is_empty(), "no terms leaves plain text untouched")

	var bracket := UiContentText.highlight_segments("说明[专注]", ["专注"])
	_check(_joined(bracket) == "说明[专注]" and _highlighted(bracket) == ["专注"], "user brackets survive segment rendering")

	var glossary_segments := UiContentText.glossary_segments("专注：支付专注\n状态完成量：由状态产生", ["专注", "支付", "状态完成量"])
	_check(_joined(glossary_segments) == "专注：支付专注\n状态完成量：由状态产生", "glossary plain text stays exact")
	_check(_highlighted(glossary_segments) == ["专注", "状态完成量"], "glossary highlights only term names, not meanings")

	print("BATTLE_KEYWORD_HIGHLIGHT_CHECKS=", JSON.stringify({"checks": _checks, "failures": _failures}))
	return _failures


func _joined(segments: Array) -> String:
	var parts: Array[String] = []
	for segment in segments:
		parts.append(str(segment.get("text", "")))
	return "".join(parts)


func _highlighted(segments: Array) -> Array[String]:
	var result: Array[String] = []
	for segment in segments:
		if bool(segment.get("highlighted", false)):
			result.append(str(segment.get("text", "")))
	return result


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append("battle keyword highlight: " + message)
