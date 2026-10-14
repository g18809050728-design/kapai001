extends RefCounted
##
## 冷检出守卫：禁止「对自身 class_name 直接 .new()」。
##
## 背景（t18）：干净检出（没有生成的 .godot/global_script_class_cache.cfg）时，GDScript 解析
## 不到尚未注册的全局类名。文件里对**自身** class_name 直接 `.new()` 会报 `Identifier not found: X`，
## 该文件整体编译失败；preload 它的脚本拿到空 GDScript，运行期再炸成一大片红
## （实测 e92f0bd 冷检出：403 通过 / 125 失败）。
##
## 项目既有约定是 `load("res://…").new()`（7 处先例），本套件把它钉成不变量。
## 只做源码扫描、不依赖 class cache，所以它在冷检出下自己也能跑。
##
## 注意本守卫比 `--check-only` 强的地方：编译器在一个文件里遇到第一个错误就停下，
## 所以「逐文件冷扫」只能看到每个文件的第一处；本守卫逐行扫，能一次报全（实际就抓到了第二处）。
##

const SRC_DIR := "res://src"
const MIN_SCANNED := 30


func run(h) -> void:
    h.begin("冷检出守卫：禁止对自身 class_name 直接 .new()")
    var paths := _gd_files(SRC_DIR)
    h.check("扫描到足够多的 src 脚本", paths.size() >= MIN_SCANNED, "扫描 %d 个 .gd" % paths.size())
    var offenders := PackedStringArray()
    var with_class := 0
    for path in paths:
        var text := FileAccess.get_file_as_string(path)
        if text.is_empty():
            continue
        var own_class := _class_name_of(text)
        if own_class.is_empty():
            continue
        with_class += 1
        var hit := _first_self_new_line(text, own_class)
        if hit > 0:
            offenders.append("%s:%d 用了 %s.new()，请改成 load(\"res://…\").new()" % [path, hit, own_class])
    h.check("扫到了带 class_name 的脚本", with_class > 10, "含 class_name 的文件 %d 个" % with_class)
    _self_tests(h)
    h.problems("没有脚本对自身 class_name 直接 .new()", offenders)


## 守卫自己的自检：防止「永远绿」的摆设。
func _self_tests(h) -> void:
    h.eq("自检：裸 Self.new() 必须被认出", _first_self_new_line("var copy := BattleState.new()", "BattleState"), 1)
    h.eq("自检：项目既有写法 load(...).new() 必须放行", _first_self_new_line("var copy: BattleState = load(\"res://src/battle/battle_state.gd\").new()", "BattleState"), 0)
    h.eq("自检：前缀同名类不能误报（PlayerBattleState）", _first_self_new_line("var p := PlayerBattleState.new()", "BattleState"), 0)
    h.eq("自检：注释与 class_name 行不算违规", _first_self_new_line("## 不要写 BattleState.new()", "BattleState"), 0)
    h.eq("自检：能读出文件自己的 class_name", _class_name_of("class_name Foo\nextends RefCounted"), "Foo")
    h.eq("自检：无 class_name 的文件不适用", _class_name_of("extends RefCounted"), "")


static func _gd_files(dir_path: String) -> PackedStringArray:
    var out := PackedStringArray()
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return out
    dir.list_dir_begin()
    var entry := dir.get_next()
    while entry != "":
        if not entry.begins_with("."):
            var full := dir_path.path_join(entry)
            if dir.current_is_dir():
                out.append_array(_gd_files(full))
            elif entry.ends_with(".gd"):
                out.append(full)
        entry = dir.get_next()
    dir.list_dir_end()
    return out


## 文件自己声明的 class_name；没有则返回空串（无 class_name 的文件不适用本不变式）。
static func _class_name_of(text: String) -> String:
    for line in text.split("\n"):
        var body := line.strip_edges()
        if body.begins_with("class_name "):
            return body.substr("class_name ".length()).strip_edges().split(" ")[0]
    return ""


## 第一处「自身类名 .new(」的行号（1 起）；带词边界判定，所以 PlayerBattleState.new() 不算。
## 正确写法 load("res://…").new() 里根本不出现 <类名>.new(，因此天然放行。
static func _first_self_new_line(text: String, own_class: String) -> int:
    var needle := own_class + ".new("
    var lines := text.split("\n")
    for index in range(lines.size()):
        var line := lines[index]
        var body := line.strip_edges()
        if body.begins_with("#") or body.begins_with("class_name "):
            continue
        var at := line.find(needle)
        while at >= 0:
            if at == 0 or not _is_ident_char(line.substr(at - 1, 1)):
                return index + 1
            at = line.find(needle, at + 1)
    return 0


## GDScript 标识符字符（ASCII 足够：类名只会是 ASCII 字母数字下划线）。
static func _is_ident_char(ch: String) -> bool:
    if ch.length() != 1:
        return false
    var code := ch.unicode_at(0)
    var is_digit: bool = code >= 48 and code <= 57
    var is_upper: bool = code >= 65 and code <= 90
    var is_lower: bool = code >= 97 and code <= 122
    return is_digit or is_upper or is_lower or ch == "_"