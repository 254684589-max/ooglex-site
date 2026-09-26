class_name SkillBar
extends HBoxContainer
## 电脑版技能栏（P4）：屏幕下方中间四格，显示按键、技能名、法力消耗、冷却与解锁等级；点格子也能放（自动瞄准）。
## 手机版不用它，改用攻击键旁边的四个圆形按钮（scenes/main.gd）。

var hero: Player
var slots := {}
const IDS := ["fireball", "whirl", "nova", "blink"]


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in IDS.size():
		var id: String = IDS[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(118, 58)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func(): hero.cast_skill(id))
		add_child(b)
		slots[id] = b


func refresh() -> void:
	if hero == null:
		return
	for i in IDS.size():
		var id: String = IDS[i]
		var r := Player.skill_rule(id)
		var b: Button = slots[id]
		var cd: float = hero.skill_cd.get(id, 0.0)
		var locked: bool = hero.progress.sheet.lvl < int(r.lvl)
		var line2 := "%d 级解锁" % int(r.lvl) if locked else ("冷却 %.1f 秒" % cd if cd > 0.0 else "法力 %d" % int(r.mp))
		b.text = "%d · %s\n%s" % [i + 1, r.name, line2]
		b.disabled = locked or cd > 0.0 or hero.mp < float(r.mp)
		b.tooltip_text = String(r.desc)
