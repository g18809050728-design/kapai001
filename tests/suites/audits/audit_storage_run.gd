extends SceneTree
##
## ⚠️ 写文件纪律（团队约定，2026-10）：除 git 之外的一切写操作一律用**绝对路径**。
## PowerShell 的 [System.IO.File]::Write* / Set-Content 走「进程工作目录」，不跟 `cd`；
## 在快照目录里做实验时若用相对路径，改动会悄悄落回共享工作树（快照隔离失效且无报错）。
## 本套件自身只写 user://（存档夹具），绝不写仓库文件。
## 断言 detail 一律传 String（str(...) / % 格式化）：GDScript 在调用点抛错会**中断整个函数**，
## 后面的断言会静默失联。harness 已加 Variant 兜底；自查手法：静态断言站点数 vs 运行时计数。
##
## 独立审查入口（verifier，t6）：只跑 src/storage + src/run 的审查套件，不并入 run_tests.gd 基线。
## 刻意红的偏差探针留在 audits/ 子目录，主套件永远不会自动跑到它。
##
## 运行： godot --headless --path . --script res://tests/suites/audits/audit_storage_run.gd
## 退出码：0 = 全部审查断言通过；1 = 存在偏差探针变红（审查结论，见会话 findings）。
##

const Harness := preload("res://tests/harness.gd")
const AuditSuite := preload("res://tests/suites/audits/test_storage_run_audit.gd")


func _initialize() -> void:
    print("=== 独立审查：存档与局流程逐条核对（src/storage + src/run）===")
    var harness := Harness.new()
    var suite = AuditSuite.new()
    suite.run(harness)
    var failed: int = harness.report("独立审查 · 存档与局流程")
    print("提示：标 [偏差探针] 的断言变红 = 实现缺该落点，属审查结论而不是回归。")
    quit(1 if failed > 0 else 0)
