class_name CityMapWindow
extends UIWindow
## 城市地图（M）：道路、街区、所有地点（营业状态）、公交 / 地铁站、玩家位置与朝向、当前任务目标。
## 点击地点可以查看介绍；已开通打车时可以直接叫车过去。

var canvas: MapCanvas


func _init() -> void:
	super("新澜市地图", Vector2(1000, 700), false)
	window_id = "map"


func _ready() -> void:
	super()
	canvas = MapCanvas.new()
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.window = self
	body.add_child(canvas)
	var info := UIKit.label("点地点查看信息 · ● 你的位置 · ◆ 任务目标 · 黄 = 公交站 · 青 = 地铁站" + (" · 「车」= 我的车" if VehicleManager.has_car() else ""), 14, UIKit.DIM)
	body.add_child(info)


func show_location(id: String) -> void:
	var d := DataDB.location(id)
	var ln := GameManager.lookup("loc:" + id) as LocationNode
	var opts: Array = []
	if TransportManager.unlocked("taxi") and ln != null:
		var p := GameManager.player
		var dest := TransportManager._entry("taxi", id, DataDB.location_name(id), ln.front_position(), p.global_position if p != null else Vector3.ZERO)
		opts.append({"text": "打车过去（%s，约 %d 分钟）" % [Fmt.yuan(int(dest["cost"])), int(dest["minutes"])], "cb": func():
			var r := TransportManager.travel("taxi", dest)
			Events.say(String(r["text"]), "good" if bool(r["ok"]) else "warn")
			force_close()})
	opts.append({"text": "关闭", "cb": Callable()})
	var status := ln.hours_text() if ln != null else ""
	if ln != null:
		status += "（现在%s）" % ("营业中" if ln.is_open() else "已打烊")
	var w := ChoiceWindow.new(String(d.get("name", id)), "%s\n类别：%s\n%s" % [String(d.get("en", "")), String(d.get("map", "")), status], opts, Vector2(520, 340))
	Events.panel_requested.emit("_window", {"window": w})
