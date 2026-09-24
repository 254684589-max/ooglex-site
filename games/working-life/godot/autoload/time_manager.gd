extends Node
## 时间系统（自动加载名：TimeManager）。
## 游戏内一天 = 现实约 22 分钟。日历：2088 年 3 月 1 日（周一）开始，每月按 30 天计。
## 支持暂停 / 正常 / 2 倍速，睡觉与上班用 advance() 快进（逐小时发出信号，保证各系统按顺序结算）。

signal minute_passed(minutes: float)
signal hour_changed(hour: int)
signal day_changed(day: int)
signal time_advanced(minutes: float, activity: String)

const REAL_MINUTES_PER_DAY := 22.0
const START_YEAR := 2088
const START_MONTH := 3
const DAYS_PER_MONTH := 30
const WEEKDAYS := ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

## 从第 1 天 00:00 起经过的游戏分钟
var total_minutes := 0.0
var day := 1
## 0 = 暂停，1 = 正常，2 = 两倍
var speed := 1
var _last_hour := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func reset(start_hour := 13.0) -> void:
	total_minutes = start_hour * 60.0
	day = 1
	_last_hour = hour()
	speed = int(SettingsManager.get_v("time_speed", 1))
	if speed <= 0:
		speed = 1


func minutes_per_second() -> float:
	return 1440.0 / (REAL_MINUTES_PER_DAY * 60.0)


func running() -> bool:
	return GameManager.playing and not GameManager.is_modal() and not GameManager.in_minigame and speed > 0


func _process(delta: float) -> void:
	if not running():
		return
	var m := delta * minutes_per_second() * float(speed)
	_step(m, "idle")
	minute_passed.emit(m)


func minute_of_day() -> float:
	return fmod(total_minutes, 1440.0)


func hour() -> int:
	return int(minute_of_day() / 60.0)


func hour_f() -> float:
	return minute_of_day() / 60.0


func weekday() -> int:
	return (day - 1) % 7


func weekday_name(d := -1) -> String:
	if d < 0:
		d = day
	return WEEKDAYS[(d - 1) % 7]


func is_weekend(d := -1) -> bool:
	if d < 0:
		d = day
	return (d - 1) % 7 >= 5


func month_index(d := -1) -> int:
	if d < 0:
		d = day
	return int((d - 1) / DAYS_PER_MONTH)


func day_of_month(d := -1) -> int:
	if d < 0:
		d = day
	return (d - 1) % DAYS_PER_MONTH + 1


func year() -> int:
	return START_YEAR + int((START_MONTH - 1 + month_index()) / 12)


func month() -> int:
	return (START_MONTH - 1 + month_index()) % 12 + 1


func date_text() -> String:
	return "%d年%d月%d日" % [year(), month(), day_of_month()]


func month_key(d := -1) -> String:
	if d < 0:
		d = day
	var mi := month_index(d)
	return "%d-%02d" % [START_YEAR + int((START_MONTH - 1 + mi) / 12), (START_MONTH - 1 + mi) % 12 + 1]


func clock_text() -> String:
	return Fmt.clock(minute_of_day())


## 白天程度 0..1（用于灯光）
func daylight() -> float:
	var h := hour_f()
	if h < 5.0 or h > 20.0:
		return 0.0
	if h < 7.0:
		return (h - 5.0) / 2.0
	if h > 18.0:
		return (20.0 - h) / 2.0
	return 1.0


## 以当前时间为基准，到某个钟点还要多少分钟（跨天）
func minutes_until(target_hour: float) -> float:
	var now := minute_of_day()
	var t := target_hour * 60.0
	var d := t - now
	if d <= 0.0:
		d += 1440.0
	return d


## 快进（睡觉、上班、上课、乘车）。逐小时推进，保证 hour_changed / day_changed 顺序发出。
func advance(minutes: float, activity := "idle") -> void:
	var left := maxf(0.0, minutes)
	while left > 0.001:
		var to_next_hour := 60.0 - fmod(total_minutes, 60.0)
		var step := minf(left, to_next_hour + 0.001)
		_step(step, activity)
		left -= step
	minute_passed.emit(minutes)


func _step(m: float, activity: String) -> void:
	var before_day := int(total_minutes / 1440.0)
	total_minutes += m
	var after_day := int(total_minutes / 1440.0)
	time_advanced.emit(m, activity)
	if after_day != before_day:
		day = after_day + 1
		day_changed.emit(day)
	var h := hour()
	if h != _last_hour:
		_last_hour = h
		hour_changed.emit(h)


func set_time(target_day: int, minute: float) -> void:
	total_minutes = (target_day - 1) * 1440.0 + minute
	day = target_day
	_last_hour = hour()


func to_dict() -> Dictionary:
	return {"total_minutes": total_minutes, "day": day, "speed": speed}


func from_dict(d: Dictionary) -> void:
	total_minutes = float(d.get("total_minutes", 13 * 60.0))
	day = int(d.get("day", 1))
	speed = maxi(1, int(d.get("speed", 1)))
	_last_hour = hour()
