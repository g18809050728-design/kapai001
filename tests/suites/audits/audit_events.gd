extends SceneTree
##
## ⚠️ 写文件纪律（团队约定，2026-10）：除 git 之外的一切写操作一律用**绝对路径**。
## PowerShell 的 [System.IO.File]::Write* / Set-Content 走「进程工作目录」，不跟 `cd`；
## 在快照目录里做实验时若用相对路径，改动会悄悄落回共享工作树（快照隔离失效且无报错）。
## 本套件自身只写 user://（存档夹具），绝不写仓库文件。
## 断言 detail 一律传 String（str(...) / % 格式化）：GDScript 在调用点抛错会**中断整个函数**，
## 后面的断言会静默失联。harness 已加 Variant 兜底；自查手法：静态断言站点数 vs 运行时计数。
##
## E01～E04 事件节点端到端验收入口（verifier，为 t11 落地 event 组准备）。
## 刻意不登记进主套件；events 未启用时只跑「阻塞前提」断言（前置落地会翻红提醒）。
##
## 运行： godot --headless --path . --quit-after 3000 --script res://tests/suites/audits/audit_events.gd
##

const Harness := preload("res://tests/harness.gd")


func _initialize() -> void:
    print("=== 端到端验收：E01～E04（事件节点）===")
    var suite_script = load("res://tests/suites/audits/test_events_e2e.gd")
    if suite_script == null:
        print("审查套件编译失败：见上方 SCRIPT ERROR")
        quit(1)
        return
    var harness := Harness.new()
    var suite = suite_script.new()
    suite.run(harness)
    var failed: int = harness.report("端到端验收 · 事件")
    print("提示：[待内容] = 前置未落地（前置落地时这条会翻红并启动实探针）。")
    quit(1 if failed > 0 else 0)
