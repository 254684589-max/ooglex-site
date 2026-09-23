extends Node
## 时间系统（自动加载名：TimeSystem）。
## 一整天 24 小时 ≈ 现实 18 分钟。醒着的时候时间最多走到次日凌晨 2 点，
## 到点会累得睡着（强制结算）。天数只在睡觉后增加。

signal clock_ticked(day: int, minutes: float)
signal hour_changed(hour: int)
signal phase_changed(phase: String)
signal day_started(day: int)
signal pass_out()

const MINUTES_PER_DAY := 1440.0
## 现实多少秒走完一整天（18 分钟）
const REAL_SECONDS_PER_DAY := 1080.0
const WAKE_MINUTE := 6 * 60
## 最晚熬到次日 02:00
const PASS_OUT_MINUTE := MINUTES_PER_DAY + 2 * 60

var day := 1
var minutes: float = WAKE_MINUTE
var running := false
## 调试 / 测试用的时间倍速
var speed_multiplier := 1.0

var _last_minute := -1
var _last_hour := -1
var _phase := ""
var _passed_out := false


func reset() -> void:
	day = 1
	minutes = WAKE_MINUTE
	_passed_out = false
	_sync_signals(true)


func minutes_per_second() -> float:
	return MINUTES_PER_DAY / REAL_SECONDS_PER_DAY


func _process(delta: float) -> void:
	if not running or GameState.is_modal() or get_tree().paused:
		return
	advance(delta * minutes_per_second() * speed_multiplier)


func advance(game_minutes: float) -> void:
	minutes = minf(minutes + game_minutes, PASS_OUT_MINUTE)
	_sync_signals(false)
	if minutes >= PASS_OUT_MINUTE and not _passed_out:
		_passed_out = true
		pass_out.emit()


## 睡觉：进入第二天。
func sleep_until_morning(wake_minute: int = WAKE_MINUTE) -> void:
	day += 1
	minutes = wake_minute
	_passed_out = false
	_sync_signals(true)
	day_started.emit(day)


func set_time(day_value: int, minute_value: float) -> void:
	day = day_value
	minutes = clampf(minute_value, 0.0, PASS_OUT_MINUTE)
	_passed_out = minutes >= PASS_OUT_MINUTE
	_sync_signals(true)


## 当天内的分钟数（0~1439），跨过午夜后回到 0 开始
func minute_of_day() -> float:
	return fmod(minutes, MINUTES_PER_DAY)


func hour() -> int:
	return int(minute_of_day() / 60.0)


## 已经过了午夜还没睡
func is_after_midnight() -> bool:
	return minutes >= MINUTES_PER_DAY


func phase() -> String:
	var h := hour()
	if h < 5:
		return "凌晨"
	if h < 8:
		return "早晨"
	if h < 17:
		return "白天"
	if h < 19:
		return "傍晚"
	return "夜晚"


## 工地干活时间 06:00 ~ 18:00
func is_work_hours() -> bool:
	if is_after_midnight():
		return false
	var h := hour()
	return h >= 6 and h < 18


## 18:00 之后可以正常睡觉进入第二天
func can_sleep() -> bool:
	return is_after_midnight() or hour() >= 18 or hour() < 5


func clock_text() -> String:
	var m := int(minute_of_day())
	return "%02d:%02d" % [int(m / 60.0), m % 60]


## 0 = 深夜，1 = 正午，用于天空与光照
func daylight() -> float:
	var h := minute_of_day() / 60.0
	# 4:30 天亮，6:15 全亮，17:45 开始变暗，19:40 全黑
	if h < 4.5 or h >= 19.66:
		return 0.0
	if h < 6.25:
		return smoothstep(4.5, 6.25, h)
	if h < 17.75:
		return 1.0
	return 1.0 - smoothstep(17.75, 19.66, h)


func _sync_signals(force: bool) -> void:
	var m := int(minutes)
	if force or m != _last_minute:
		_last_minute = m
		clock_ticked.emit(day, minutes)
	var h := hour()
	if force or h != _last_hour:
		_last_hour = h
		hour_changed.emit(h)
		Events.objective_changed.emit()
	var p := phase()
	if force or p != _phase:
		_phase = p
		phase_changed.emit(p)


func to_dict() -> Dictionary:
	return {"day": day, "minutes": minutes}


func from_dict(d: Dictionary) -> void:
	set_time(int(d.get("day", 1)), float(d.get("minutes", WAKE_MINUTE)))
