class_name Ids
extends RefCounted
##
## 运行实例 ID 生成（《数据库与实体关系设计》§3 标识与通用约束）。
##
## 契约：
##   · 定义 ID 沿用策划编号（K01 / P01 / N01 / B01 …），运行实例 ID 是
##     run_id + 单调序号构成的**不透明字符串**，不使用对象地址。
##   · ID 生成**不消费任何随机流**——否则存档读档会改变随机序列。
##   · next_instance_seq 随快照保存，读档后继续递增；已删除实例的 ID 不复用。
##

## 新局 ID：由开局种子派生，保证「同种子 + 同操作」得到同一个 run_id。
static func run_id_from_seed(seed_value: int) -> String:
	return "R" + _hex16(seed_value)


## 运行实例 ID：run_id + 单调序号。
static func instance_id(run_id: String, sequence: int) -> String:
	return "%s#%d" % [run_id, sequence]


## 64 位整数的十六进制表示（负数走补码，不丢高位）。
static func _hex16(value: int) -> String:
	var remaining := value
	var text := ""
	for _i in range(16):
		text = "%X" % (remaining & 0xF) + text
		remaining = remaining >> 4
	return text
