extends SceneTree
##
## ⚠️ 写文件纪律（团队约定，2026-10）：除 git 之外的一切写操作一律用**绝对路径**。
## PowerShell 的 [System.IO.File]::Write* / Set-Content 走「进程工作目录」，不跟 `cd`；
## 在快照目录里做实验时若用相对路径，改动会悄悄落回共享工作树（快照隔离失效且无报错）。
## 本套件自身只写 user://（存档夹具），绝不写仓库文件。
## 断言 detail 一律传 String（str(...) / % 格式化）：GDScript 在调用点抛错会**中断整个函数**，
## 后面的断言会静默失联。harness 已加 Variant 兜底；自查手法：静态断言站点数 vs 运行时计数。
##
## T01～T20 端到端验收入口（verifier，为 t7/v3 准备）：把《统一设计文档》§12.2 的 20 条用例
## 逐条跑一遍，输出逐条结论。刻意不登记进主套件；前置未落地的条目会打 [待内容]。
##
## 运行： godot --headless --path . --script res://tests/suites/audits/audit_t01_t20.gd
## 退出码：0 = 全部断言通过；1 = 有 [偏差探针] 变红或前置阻塞断言翻红。
##

const Harness := preload("res://tests/harness.gd")
## 用 load() 而不是 preload()：套件编译失败时 load() 返回 null，入口能立刻退出（preload 失败会让整个入口编译失败、SceneTree 不 quit() 而挂住）。


func _initialize() -> void:
    print("=== 端到端验收：T01～T20（《统一设计文档》§12.2）===")
    var harness := Harness.new()
    var suite_script = load("res://tests/suites/audits/test_t01_t20_e2e.gd")
    if suite_script == null:
        print("审查套件编译失败：见上方 SCRIPT ERROR")
        quit(1)
        return
    var suite = suite_script.new()
    suite.run(harness)
    var failed: int = harness.report("端到端验收 · T01～T20")
    print("提示：[待内容] = 该用例前置定义还没落地；[偏差探针] 变红 = 实现缺该规则落点。")
    quit(1 if failed > 0 else 0)
