class_name DriveHud
extends Control
## 开车时屏幕下方中间的仪表：车名、车速（km/h）、本次里程与预计油费、操作提示。

## 普通 HUD（它隐藏时仪表也隐藏：剧情、菜单、结局）
var hud: Control
var _panel: PanelContainer
var _name: Label
var _speed: Label
var _trip: Label
var _keys: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.full_rect(self)
	_panel = UIKit.panel(Color(0.02, 0.02, 0.05, 0.62), 8, 10)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var v := UIKit.vbox(0)
	_panel.add_child(v)
	var row := UIKit.hbox(10)
	v.add_child(row)
	_speed = UIKit.label("0", 34, UIKit.CYAN)
	row.add_child(_speed)
	var col := UIKit.vbox(0)
	row.add_child(col)
	col.add_child(UIKit.label("km/h", 13, UIKit.DIM))
	_name = UIKit.label("", 15, UIKit.TEXT)
	col.add_child(_name)
	_trip = UIKit.label("", 13, UIKit.DIM)
	v.add_child(_trip)
	_keys = UIKit.label("W/S 油门·刹车  A/D 转向  空格 手刹  E 下车", 12, UIKit.DIM)
	v.add_child(_keys)
	visible = false


func _process(_delta: float) -> void:
	var car := VehicleManager.active_node()
	visible = car != null and GameManager.playing and (hud == null or hud.visible)
	if not visible:
		return
	_speed.text = "%d" % int(round(absf(car.speed) * 3.6))
	_name.text = String(car.spec.get("name", "")) + ("  · 倒车" if car.speed < -0.5 else "")
	var km := VehicleManager.trip_m / 1000.0
	_trip.text = "本次 %.1f 公里 · 油费约 %s" % [km, Fmt.yuan(ceil(km * float(car.spec.get("fuel_per_km", 1.0))))]
	_keys.visible = not GameManager.touch_mode
	var s := _panel.get_combined_minimum_size()
	_panel.position = Vector2((size.x - s.x) * 0.5, size.y - s.y - (150.0 if GameManager.touch_mode else 96.0))
