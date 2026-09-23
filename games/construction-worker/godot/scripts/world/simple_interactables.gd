class_name SimpleInteractable
extends Interactable
## 通用的「按 E 触发一件事」交互物：商店柜台、床铺、饮水点、提示牌。
## kind:
##   "shop"   打开商店（target = shop id）
##   "bed"    打开睡觉菜单
##   "water"  免费凉茶桶：水分 +25，有冷却时间
##   "sign"   只显示一段文字

@export var kind := "shop"
@export var target := ""
@export var prompt := ""
@export var message := ""

## 凉茶桶下次可用的时间（从游戏开始算的总分钟）
var _water_ready_at := -1.0


func _ready() -> void:
	if get_child_count() == 0:
		set_sphere_shape(1.6, Vector3(0, 1.0, 0))


func _abs_minutes() -> float:
	return float(TimeSystem.day) * TimeSystem.MINUTES_PER_DAY + TimeSystem.minutes


func get_actions(_player: Node) -> Array:
	match kind:
		"shop":
			return [Interactable.action("interact", prompt)]
		"bed":
			if TimeSystem.can_sleep():
				return [Interactable.action("interact", "睡觉（进入第二天）")]
			return [Interactable.action("interact", "上床（小睡 / 睡到明天）")]
		"water":
			var wait := _water_ready_at - _abs_minutes()
			if wait > 0.0:
				return [Interactable.action("interact", "凉茶桶见底了，约 %d 分钟后续上" % ceili(wait), false)]
			return [Interactable.action("interact", "喝凉茶（免费 · 水分 +25）")]
		_:
			return [Interactable.action("interact", prompt)]


func perform(action_key: String, _player: Node) -> void:
	if action_key != "interact":
		return
	match kind:
		"shop":
			Events.shop_requested.emit(target)
		"bed":
			Events.bed_requested.emit()
		"water":
			if PlayerStats.thirst >= 97.0:
				Events.say("现在不渴", "info")
				return
			PlayerStats.change_thirst(25.0)
			PlayerStats.change_stamina(3.0)
			_water_ready_at = _abs_minutes() + 40.0
			Events.say("咕咚咕咚……凉茶真解渴！水分 +25", "good")
			Events.objective_changed.emit()
		_:
			if message != "":
				Events.say(message, "info")
