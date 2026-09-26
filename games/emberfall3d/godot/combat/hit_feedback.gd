class_name HitFeedback
extends RefCounted
## 命中反馈（GDD.md 第 4.3 节）：局部命中停顿（只冻结命中双方，不改全局时间）、屏幕震动、伤害数字。
## 闪白与击退由受击方自己处理（take_hit）。

static var numbers_enabled := true   # 设置：关闭伤害数字（无障碍）

const COLORS := {
	"physical": Color(0.96, 0.93, 0.87),
	"fire": Color(1.0, 0.6, 0.25),
	"cold": Color(0.6, 0.85, 1.0),
	"poison": Color(0.56, 0.81, 0.23),
	"void": Color(0.69, 0.42, 1.0),
}
const CRIT_COLOR := Color(1.0, 0.82, 0.29)


static func hitstop_s(result: Dictionary, heavy := false) -> float:
	var ms: Dictionary = Balance.fb().hitstop_ms
	var v: float = ms.crit if result.crit else (ms.heavy if heavy else ms.normal)
	return v / 1000.0


static func apply(attacker: Node, target: Node, result: Dictionary, camera: IsoCamera, heavy := false) -> void:
	var stop := hitstop_s(result, heavy)
	if "hitstop_t" in attacker:
		attacker.hitstop_t = maxf(attacker.hitstop_t, stop)
	if "hitstop_t" in target:
		target.hitstop_t = maxf(target.hitstop_t, stop)
	if camera:
		var sh: Dictionary = Balance.fb().shake
		camera.add_trauma(sh.crit if result.crit else (sh.heavy if heavy else sh.normal))
	if numbers_enabled and target is Node3D:
		spawn_number(target, result)


static func spawn_number(target: Node3D, result: Dictionary) -> Label3D:
	var l := Label3D.new()
	l.text = str(result.amount) + ("!" if result.crit else "")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0012
	l.font_size = 56 if result.crit else 40
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.modulate = CRIT_COLOR if result.crit else COLORS.get(result.type, COLORS.physical)
	l.render_priority = 10
	target.get_parent().add_child(l)
	l.global_position = target.global_position + Vector3(randf_range(-0.3, 0.3), 2.2, randf_range(-0.3, 0.3))
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position:y", l.global_position.y + 1.1, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.45)
	if result.crit:
		l.scale = Vector3.ONE * 1.6
		tw.tween_property(l, "scale", Vector3.ONE, 0.18)
	tw.chain().tween_callback(l.queue_free)
	return l
