extends RefCounted
##
## harness 自检：断言收集器本身不能撒谎。
##
## 背景（t22）：有人把 bool 当 check() 的第 3 个 detail 参数传，静态类型让**调用处**抛
## `Invalid type in function check ... Cannot convert argument 3 from bool to String`，
## 那条断言既不算通过也不算失败——静默漏测（全量总数因此少 1）。
## 本套件证明：防御之后，任何类型的 detail 都会被正常计数。
##
## 注意：这里**只放会通过的断言**。为了验失败分支而制造一条真失败，会在主套件日志里
## 留下 [FAIL] 行，污染别人的失败计数与 grep——那本身就是一种假信号。
##

func run(h) -> void:
    h.begin("harness 自检：detail 任意类型都必须被计数")
    # 1) bool 当 detail：就是 t22 的原始症状，修前这里抛错、断言不计数
    var passed_before: int = h.passed
    var failed_before: int = h.failed
    h.check("bool 当 detail 也必须被计数", true, true)
    h.eq("bool detail 的断言确实进了通过计数", h.passed - passed_before, 1)
    # 2) 其它非字符串 detail 同样不能抛错
    var before2: int = h.passed
    h.check("数组当 detail 不抛错", true, [1, 2, 3])
    h.check("null 当 detail 不抛错", true, null)
    h.check("整数当 detail 不抛错", true, 7)
    h.check("字典当 detail 不抛错", true, {"a": 1})
    h.eq("四种非字符串 detail 都被计数", h.passed - before2, 4)
    h.eq("这些通过断言不让 failed 增加（增量比较，不受其它套件影响）", h.failed - failed_before, 0)


    # 3) 转换规则本身。失败分支与通过分支共用同一个 _detail_text（在计数之前调用），
    #    所以这几条等于把失败分支的类型敏感部分也覆盖了。
    h.eq("_detail_text(true)", h._detail_text(true), "true")
    h.eq("_detail_text(false)", h._detail_text(false), "false")
    h.eq("_detail_text(null)", h._detail_text(null), "")
    h.eq("_detail_text(7)", h._detail_text(7), "7")
    h.eq("_detail_text(String) 原样返回", h._detail_text("原样"), "原样")
    h.eq("_detail_text(数组) 转成字符串", h._detail_text([1, 2]), "[1, 2]")