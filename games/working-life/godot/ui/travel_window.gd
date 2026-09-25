class_name TravelWindow
extends UIWindow
## 公交 / 地铁 / 出租车：选择目的地，付车费、消耗时间，直接到达。

var mode := "bus"


func _init(p_mode: String) -> void:
	mode = p_mode
	super("出行 · %s" % String(TransportManager.mode(p_mode).get("name", "")), Vector2(640, 580))
	window_id = "travel"


func _ready() -> void:
	super()
	var p := GameManager.player
	var from: Vector3 = p.global_position if p != null else Vector3.ZERO
	if not TransportManager.unlocked(mode):
		add_text(String(TransportManager.mode(mode).get("unlock_text", "尚未开通")), 17, UIKit.WARN)
		return
	var m := TransportManager.mode(mode)
	if mode == "taxi":
		add_text("起步价 %s，每 100 米 %s%s。雨天路上更慢。" % [Fmt.yuan(int(m.get("fare", 14))), Fmt.yuan(float(m.get("per_100m", 2.5))), "（新款手机 9 折）" if PlayerManager.owned.has("phone_pro") else ""], 15, UIKit.DIM)
	else:
		add_text("票价 %s，全程一票。" % Fmt.yuan(int(m.get("fare", 2))), 15, UIKit.DIM)
	for d in TransportManager.destinations(mode, from):
		var h := UIKit.hbox(8)
		body.add_child(h)
		var l := UIKit.label("%s  %d 米 · 约 %d 分钟" % [String(d["name"]), int(d["dist"]), int(d["minutes"])], 16, UIKit.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var b := UIKit.small_button("%s 出发" % Fmt.yuan(int(d["cost"])), _go.bind(d))
		b.disabled = bool(d["near"])
		h.add_child(b)


func _go(d: Dictionary) -> void:
	var r := TransportManager.travel(mode, d)
	Events.say(String(r["text"]), "good" if bool(r["ok"]) else "warn")
	if bool(r["ok"]):
		force_close()
