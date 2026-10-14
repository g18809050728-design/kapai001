extends SceneTree
##
## ⚠️ 写文件纪律（团队约定，2026-10）：除 git 之外的一切写操作一律用**绝对路径**。
## PowerShell 的 [System.IO.File]::Write* / Set-Content 走「进程工作目录」，不跟 `cd`；
## 在快照目录里做实验时若用相对路径，改动会悄悄落回共享工作树（快照隔离失效且无报错）。
## 本套件自身只写 user://（存档夹具），绝不写仓库文件。
## 断言 detail 一律传 String（str(...) / % 格式化）：GDScript 在调用点抛错会**中断整个函数**，
## 后面的断言会静默失联。harness 已加 Variant 兜底；自查手法：静态断言站点数 vs 运行时计数。
##
## 独立审查入口（verifier）：只跑审查套件，不并入 tests/run_tests.gd 的验收基线。
##
## 运行： godot --headless --path . --script res://tests/suites/audits/audit_battle_rules.gd
## 退出码：0 = 全部审查断言通过；1 = 存在偏差探针变红（审查结论，见会话 findings）。
##

const Harness := preload("res://tests/harness.gd")


func _initialize() -> void:
    var suite_script = load("res://tests/suites/audits/test_battle_audit.gd")
    if suite_script == null:
        print("[审查入口] 套件无法加载：test_battle_audit.gd")
        quit(1)
        return
    print("=== 独立审查：战斗规则逐条核对（src/battle）===")
    var harness := Harness.new()
    var suite = (suite_script as GDScript).new()
    suite.run(harness)
    var failed: int = harness.report("独立审查 · 战斗规则")
    print("提示：标 [偏差探针] 的断言变红 = 实现层缺该规则落点，属审查结论而不是回归。")
    quit(1 if failed > 0 else 0)
