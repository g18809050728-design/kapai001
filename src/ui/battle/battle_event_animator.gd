class_name BattleEventAnimator
extends Node
##
## 事件动画队列：唯一职责是按时间把事件「播」出来（供界面闪动与播报）。
##
## 硬约束：本类不持有、不读取、不修改任何规则状态。
## 关闭动画（animation_enabled=false）或提高 speed_scale 只改变播放节奏，
## 理论上不可能改变任何结算结果——因为结算完全不经过这里。
##

signal event_played(event: Dictionary)
signal drained()

var animation_enabled := true
var speed_scale := 1.0
var base_delay := 0.22

var _queue: Array = []
var _timer := 0.0
var _played := 0


func _process(delta: float) -> void:
    advance(delta)


## 推进一帧。测试直接调用，避免依赖真实帧循环。
func advance(delta: float) -> void:
    if not animation_enabled:
        drain_now()
        return
    if _queue.is_empty():
        return
    _timer -= delta * maxf(0.05, speed_scale)
    while _timer <= 0.0 and not _queue.is_empty():
        _timer += base_delay
        _emit_next()
    if _queue.is_empty():
        _timer = 0.0
        drained.emit()


func enqueue(events: Array) -> void:
    for raw in events:
        if typeof(raw) == TYPE_DICTIONARY:
            _queue.append(raw)
    if not animation_enabled:
        drain_now()


## 立刻播完剩余事件（关闭动画或测试用）。
func drain_now() -> void:
    if _queue.is_empty():
        return
    while not _queue.is_empty():
        _emit_next()
    _timer = 0.0
    drained.emit()


func set_animation_enabled(value: bool) -> void:
    animation_enabled = value
    if not value:
        drain_now()


func toggle_enabled() -> bool:
    set_animation_enabled(not animation_enabled)
    return animation_enabled


func clear() -> void:
    _queue.clear()
    _timer = 0.0


func pending_count() -> int:
    return _queue.size()


func played_count() -> int:
    return _played


func _emit_next() -> void:
    var event: Dictionary = _queue.pop_front()
    _played += 1
    event_played.emit(event)