extends Node
## 天气（自动加载名：WeatherManager）：晴 / 阴 / 雨，每隔几个小时随机变化。
## 天气影响：路上行人数量、交通耗时、户外工作、部分随机事件。画面效果由 WeatherFX 负责。

signal weather_changed(weather: String)

const NAMES := {"sunny": "晴", "cloudy": "阴", "rain": "雨"}
const ICONS := {"sunny": "☀", "cloudy": "☁", "rain": "☂"}

var weather := "cloudy"
## 下一次允许变天的总分钟数
var _next_change := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	TimeManager.hour_changed.connect(_on_hour)


func reset() -> void:
	weather = "cloudy"
	_next_change = TimeManager.total_minutes + 240.0


func display_name() -> String:
	return NAMES.get(weather, weather)


func icon() -> String:
	return ICONS.get(weather, "")


func set_weather(w: String) -> void:
	if not NAMES.has(w) or w == weather:
		return
	weather = w
	weather_changed.emit(w)


func is_raining() -> bool:
	return weather == "rain"


## 户外工作 / 通勤的效率系数
func outdoor_factor() -> float:
	return 0.85 if weather == "rain" else 1.0


## 路上行人密度系数
func crowd_factor() -> float:
	match weather:
		"rain":
			return 0.35
		"cloudy":
			return 0.85
	return 1.0


func _on_hour(_h: int) -> void:
	if TimeManager.total_minutes < _next_change:
		return
	_next_change = TimeManager.total_minutes + _rng.randf_range(180.0, 420.0)
	var r := _rng.randf()
	var w := "sunny"
	# 霓虹都市多阴雨
	if r < 0.32:
		w = "rain"
	elif r < 0.66:
		w = "cloudy"
	set_weather(w)


func to_dict() -> Dictionary:
	return {"weather": weather, "next": _next_change}


func from_dict(d: Dictionary) -> void:
	weather = String(d.get("weather", "cloudy"))
	_next_change = float(d.get("next", 0.0))
	weather_changed.emit(weather)
