extends SceneTree
##
## 验收测试入口（无头）—— **运行时自动发现套件**。
##
## 运行： godot --headless --path . --script res://tests/run_tests.gd
## 退出码：0 = 全部通过；1 = 有失败（含套件加载失败）；3 = 看门狗兜底（理论上不该出现）。
##
## 登记规则（本文件不再需要任何人来改）：
##   · 把 `tests/suites/test_*.gd`（`extends RefCounted` + `func run(h)`）放进目录即会被自动跑；
##   · `tests/suites/audits/**` 永不自动跑——刻意红的审查探针只能用自己的显式入口跑；
##   · 某个套件解析失败时只记一条失败并继续跑其余套件：局部失败不坍塌成全树失败；
##   · 无论任何路径（含 `_initialize` 被打断）最终都会 `quit()`，不会挂住进程（见 `_process` 看门狗）。
##   · 开跑前打印一行 `[ENV] HEAD=<短哈希> dirty=<n|unknown>`：每份输出自带出处；dirty>0/unknown 时
##     醒目提示「本结果不代表该提交」（今天三次「拿工作区状态解读提交结论」的教训）。
##

const Harness := preload("res://tests/harness.gd")

const SUITES_DIR := "res://tests/suites"
const SUITE_PREFIX := "test_"
const SUITE_SUFFIX := ".gd"

var _finished := false


func _initialize() -> void:
	print("=== 交大四年：DDL战争 · 验收测试（自动发现）===")
	_print_env_line()
	var harness := Harness.new()
	var paths := _discover()
	print("发现 %d 个套件：%s" % [paths.size(), "，".join(_basenames(paths))])
	if paths.is_empty():
		harness.check("至少发现一个套件", false, "目录 %s 下没有 %s*%s" % [SUITES_DIR, SUITE_PREFIX, SUITE_SUFFIX])
	for path in paths:
		_run_suite(harness, path)
	_finish(harness)


## 枚举 tests/suites 顶层（不含子目录）的 test_*.gd，按路径排序。
## `.gd.uid` 被 ends_with(".gd") 自然排除；子目录（如 audits/）不进入。
# ── 环境行：让每份输出自带「在哪个提交上红」──────────────────

## [ENV] HEAD=<短哈希> dirty=<n|unknown>；dirty>0 或 unknown 时给出醒目提示。
func _print_env_line() -> void:
	var head := _head_short()
	var dirty := _dirty_summary()
	var warning := ""
	if dirty == "unknown":
		warning = "  ⚠ 无法确认工作区是否干净：本结果不代表该提交"
	elif dirty != "0":
		warning = "  ⚠ 工作区有未提交改动：本结果不代表该提交（HEAD=%s）" % head
	print("[ENV] HEAD=%s dirty=%s%s" % [head, dirty, warning])


func _project_dir() -> String:
	return ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")


## `.git` 可能是目录（普通仓库），也可能是文件（worktree / submodule：内容是 "gitdir: <path>"）。
func _git_dir() -> String:
	var base := _project_dir() + "/.git"
	if DirAccess.dir_exists_absolute(base):
		return base
	if FileAccess.file_exists(base):
		var text := FileAccess.get_file_as_string(base).strip_edges()
		if text.begins_with("gitdir:"):
			var target := text.substr(7).strip_edges().replace("\\", "/")
			if not target.is_absolute_path():
				target = base.get_base_dir().path_join(target)
			return target.simplify_path()
	return ""


## 只用 git plumbing 文件解析 HEAD：ref 文件缺失时查 packed-refs；detached 时 HEAD 本身就是哈希。
func _head_short() -> String:
	var git := _git_dir()
	if git.is_empty():
		return "unknown"
	var head_path := git + "/HEAD"
	if not FileAccess.file_exists(head_path):
		return "unknown"
	var head := FileAccess.get_file_as_string(head_path).strip_edges()
	var sha := ""
	if head.begins_with("ref: "):
		var ref := head.substr(5).strip_edges()
		var ref_file := git + "/" + ref
		if FileAccess.file_exists(ref_file):
			sha = FileAccess.get_file_as_string(ref_file).strip_edges()
		else:
			sha = _packed_ref_sha(git, ref)
	else:
		sha = head
	if sha.length() >= 7:
		return sha.substr(0, 7)
	return sha if not sha.is_empty() else "unknown"


func _packed_ref_sha(git_dir: String, ref: String) -> String:
	var packed := git_dir + "/packed-refs"
	if not FileAccess.file_exists(packed):
		return ""
	for raw_line in FileAccess.get_file_as_string(packed).split("\n"):
		var line := String(raw_line).strip_edges()
		if line.is_empty() or line.begins_with("#") or line.begins_with("^"):
			continue
		var parts := line.split(" ", false)
		if parts.size() >= 2 and String(parts[1]) == ref:
			return String(parts[0])
	return ""


## dirty 计数：`git status --porcelain` 的行数（含未跟踪文件）；拿不到就明确写 unknown。
func _dirty_summary() -> String:
	var output := []
	var code := OS.execute("git", ["-C", _project_dir(), "status", "--porcelain"], output, true)
	if code != 0 or output.is_empty():
		return "unknown"
	var count := 0
	for raw_line in String(output[0]).split("\n"):
		if not String(raw_line).strip_edges().is_empty():
			count += 1
	return str(count)


func _discover() -> PackedStringArray:
	var paths := PackedStringArray()
	var dir := DirAccess.open(SUITES_DIR)
	if dir == null:
		push_error("[run_tests] 打不开套件目录：%s" % SUITES_DIR)
		return paths
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.begins_with(SUITE_PREFIX) and entry.ends_with(SUITE_SUFFIX):
			paths.append(SUITES_DIR + "/" + entry)
		entry = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths


## 显式解析套件源码：坏套件在这里只拿到 null，不会把调用方打断。
## （实测：直接 `load()` 一个解析失败的脚本会让 Godot 打断**当前函数**，
##   于是「记一条失败再继续」的分支根本执行不到——这是坍塌测试暴露出来的坑。）
func _load_suite(path: String):
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	var script := GDScript.new()
	script.source_code = text
	if script.reload() != OK:
		return null
	return script


## 一个套件跑不动（load 失败 / 没实现 run(h)）只记一条失败，其余套件照跑。
func _run_suite(harness, path: String) -> void:
	var before_passed: int = harness.passed
	var before_failed: int = harness.failed
	var suite_script = _load_suite(path)
	if suite_script == null:
		harness.begin("套件加载 · %s" % path.get_file())
		harness.check("套件可加载：" + path.get_file(), false, "解析/编译失败，其余套件继续跑")
		print("── %s：加载失败，已跳过（其余套件继续）──" % path.get_file())
		return
	var suite = (suite_script as GDScript).new()
	if suite == null:
		harness.begin("套件加载 · %s" % path.get_file())
		harness.check("套件可实例化：" + path.get_file(), false, "new() 返回 null")
		return
	if not suite.has_method("run"):
		harness.begin("套件加载 · %s" % path.get_file())
		harness.check("套件实现 run(h)：" + path.get_file(), false, "需要 extends RefCounted + func run(h)")
		return
	suite.run(harness)
	print("── %s：通过 %d，失败 %d ──" % [
		path.get_file(),
		harness.passed - before_passed,
		harness.failed - before_failed,
	])


func _basenames(paths: PackedStringArray) -> PackedStringArray:
	var names := PackedStringArray()
	for path in paths:
		names.append(path.get_file())
	return names


## 唯一收尾出口：任何跑法最后都从这里 quit()。
func _finish(harness) -> void:
	_finished = true
	_print_env_line()
	var failed: int = harness.report("规则与内容层")
	print("提示：新增套件只需把 test_*.gd 放进 tests/suites/；tests/suites/audits/** 不会自动跑。")
	quit(1 if failed > 0 else 0)


## 看门狗：套件里的运行期错误把 _initialize 打断时，也要退出而不是空转到超时。
func _process(_delta: float) -> bool:
	if not _finished:
		print("WATCHDOG: 主套件没有正常收尾（_initialize 被打断），强制退出（exit 3）")
		quit(3)
	return true