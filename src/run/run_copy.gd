class_name RunCopy
extends RefCounted
##
## 局流程实体深拷贝（《数据库与实体关系设计》§3「所有副本必须深拷贝可变子集合」）。
##
## 为什么不用 Array/Dictionary 的 duplicate(true)：Godot 的深拷贝只递归容器与基础类型，
## 数组里的 RefCounted 子实体仍按引用共享，工作副本会写穿到原状态（违反「失败保留原状态」）。
## 这里对实现了 copy_for_write() 的对象逐个调用，其余容器递归复制，基础类型直接返回。
##

## 深拷贝任意值。只认识 Dictionary / Array / copy_for_write() 三类可变结构。
static func value(source: Variant) -> Variant:
	if source == null:
		return null
	if source is Object:
		if source.has_method("copy_for_write"):
			return source.copy_for_write()
		return source
	if typeof(source) == TYPE_DICTIONARY:
		return dictionary(source)
	if typeof(source) == TYPE_ARRAY:
		return array(source)
	return source


static func dictionary(source: Dictionary) -> Dictionary:
	var copied := {}
	for key in source.keys():
		copied[key] = value(source[key])
	return copied


static func array(source: Array) -> Array:
	var copied := []
	for item in source:
		copied.append(value(item))
	return copied