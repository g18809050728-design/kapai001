extends RefCounted
##
## 无头测试断言收集器（仅测试使用，不进入游戏运行路径）。
## 用法：测试套件实现 run(h)，用 h.eq / h.check / h.problems 断言，由 tests/run_tests.gd 汇总。
##
## t22：check() 的第 3 参（detail）改成 Variant 并在内部转字符串。
## 起因：有人把 bool 当 detail 传，静态类型在**调用处**就抛
## `Invalid type in function check ... Cannot convert argument 3 from bool to String`，
## 于是那条断言既不算通过也不算失败——静默漏测。防御之后，任何类型的 detail 都会被计数。
##

var passed: int = 0
var failed: int = 0
var failures: PackedStringArray = PackedStringArray()

var _section: String = ""


func begin(title: String) -> void:
	_section = title
	print("\n── %s ──" % title)


func check(label: String, condition: bool, detail: Variant = "") -> void:
	var text := _detail_text(detail)
	if condition:
		passed += 1
		print("  [PASS] %s" % label)
	else:
		failed += 1
		var line := "%s / %s" % [_section, label]
		if text != "":
			line += "   → " + text
		failures.append(line)
		print("  [FAIL] %s   %s" % [label, text])


## detail 允许任何类型：转成字符串兜底，绝不让调用处抛错导致断言漏计数。
func _detail_text(detail: Variant) -> String:
	if detail == null:
		return ""
	if detail is String:
		return detail
	return str(detail)


func eq(label: String, got: Variant, want: Variant) -> void:
	check(label, got == want, "got=%s want=%s" % [str(got), str(want)])


## 断言一个 PackedStringArray 问题清单为空，失败时打印每条问题。
func problems(label: String, items: PackedStringArray) -> void:
	check(label, items.is_empty(), " → ".join(items))


func report(title: String) -> int:
	print("")
	print("=".repeat(64))
	print("%s：通过 %d，失败 %d" % [title, passed, failed])
	for line in failures:
		print("  [FAILED] %s" % line)
	print("=".repeat(64))
	return failed