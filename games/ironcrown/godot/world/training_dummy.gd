class_name TrainingDummy
extends StaticBody3D
## 木桩假人（路线图 2.4）：练剑用。挨打不会坏，会晃、会闪一下、头上冒伤害数字，旁边的木牌记下命中次数和最高一击。
## 物理层：1「世界」（挡路、挡交互射线）+ 4「可受击」（Melee 的命中查询只看这一层）。
## 被打时先等命中停顿（info.stop）结束再晃：命中停顿是局部的，只冻结挥剑的人和被打的东西（TECH.md 4.3）。

const HEIGHT := 1.75
const RADIUS := 0.3
const SPRING := 60.0
const DAMP := 7.0
const NUMBER_TIME := 0.9
const NUMBER_RISE := 0.4
const NUMBER_Y := 1.35            # 从草袋胸口冒出来，不压住头顶的名字

var display_name := "木桩假人"
var hits := 0
var best := 0
var total := 0
var last := {}
var pivot: Node3D
var sack_mat: StandardMaterial3D
var stats_label: Label3D
var tilt := Vector2.ZERO          # 绕 x / z 的倾角（弧度）
var tilt_vel := Vector2.ZERO
var stop_left := 0.0
var pending := Vector2.ZERO       # 命中停顿结束后要加上的晃动
var flash := 0.0
var numbers: Array = []           # [Label3D, 剩余时间]


func _ready() -> void:
	add_to_group("damageable")
	collision_layer = 1 | 8
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS
	cyl.height = HEIGHT
	cs.shape = cyl
	cs.position.y = HEIGHT * 0.5
	add_child(cs)
	pivot = Node3D.new()
	pivot.name = "Pivot"
	add_child(pivot)
	var kit := MeshKit.new()
	kit.cylinder("timber", Vector3(0, 0, 0), Vector3(0, 1.75, 0), 0.07, 0.06, 8)            # 立柱
	kit.box("timber", Vector3(0, 1.22, 0), Vector3(1.0, 0.08, 0.08))                      # 横臂
	kit.box("timber", Vector3(0, 0.04, 0), Vector3(0.7, 0.08, 0.16), Basis(Vector3.UP, 0.4))   # 底座十字
	kit.box("timber", Vector3(0, 0.04, 0), Vector3(0.7, 0.08, 0.16), Basis(Vector3.UP, 0.4 + PI / 2))
	kit.cylinder("sack", Vector3(0, 0.75, 0), Vector3(0, 1.38, 0), 0.24, 0.21, 8)          # 草袋身子
	kit.cylinder("sack", Vector3(0, 1.45, 0), Vector3(0, 1.7, 0), 0.13, 0.11, 8)           # 头
	kit.cylinder("rope", Vector3(0, 1.02, 0), Vector3(0, 1.07, 0), 0.245, 0.245, 8)        # 腰间一道绳
	sack_mat = StandardMaterial3D.new()
	sack_mat.albedo_color = Color("8a7448")
	sack_mat.roughness = 0.95
	sack_mat.vertex_color_use_as_albedo = true
	sack_mat.emission_enabled = true
	sack_mat.emission = Color("ffd9a0")
	sack_mat.emission_energy_multiplier = 0.0
	var rope := StandardMaterial3D.new()
	rope.albedo_color = Color("4a3a28")
	rope.vertex_color_use_as_albedo = true
	pivot.add_child(kit.build({"timber": Look.mat("timber"), "sack": sack_mat, "rope": rope}))
	Blocks.label(self, display_name, Vector3(0, 2.12, 0), 28, 0.0022)
	stats_label = Blocks.label(self, "", Vector3(0, 2.0, 0), 22, 0.0022)
	stats_label.modulate = Color("c8bca0")
	_update_stats()


## Melee 命中时调用：info = {damage, kind, dir, stop, weapon}
func take_hit(info: Dictionary) -> void:
	var dmg := int(info.get("damage", 0))
	hits += 1
	total += dmg
	best = maxi(best, dmg)
	last = info
	stop_left = float(info.get("stop", 0.0))
	var d: Vector3 = global_transform.basis.inverse() * (info.get("dir", Vector3.FORWARD) as Vector3)
	var strength := 2.2 if info.get("kind") == "heavy" else 1.2
	pending = Vector2(d.z, -d.x).normalized() * strength      # 往被打的方向倒：绕 x 轴前后、绕 z 轴左右
	flash = 1.0
	_spawn_number(dmg, info.get("kind") == "heavy")
	_update_stats()


func _spawn_number(dmg: int, heavy: bool) -> void:
	var l := Blocks.label(self, ("重击 −%d" if heavy else "−%d") % dmg, Vector3(randf_range(-0.2, 0.2), NUMBER_Y, 0), 36 if heavy else 30, 0.0026)
	l.modulate = Color("ffcf6a") if heavy else Color("f2e6c8")
	l.no_depth_test = true
	l.render_priority = 1
	numbers.append([l, NUMBER_TIME])


func _update_stats() -> void:
	stats_label.text = "命中 %d 次 · 最高 %d" % [hits, best] if hits > 0 else "左键（手机点「攻」）出剑"


func _process(delta: float) -> void:
	for n in numbers.duplicate():
		var l: Label3D = n[0]
		n[1] -= delta
		var k: float = 1.0 - n[1] / NUMBER_TIME
		l.position.y = NUMBER_Y + NUMBER_RISE * k
		l.modulate.a = clampf(n[1] / (NUMBER_TIME * 0.4), 0.0, 1.0)
		if n[1] <= 0.0:
			numbers.erase(n)
			l.queue_free()
	if stop_left > 0.0:
		stop_left -= delta
		return
	if pending != Vector2.ZERO:
		tilt_vel += pending
		pending = Vector2.ZERO
	if flash > 0.0:
		flash = maxf(flash - delta * 6.0, 0.0)
		sack_mat.emission_energy_multiplier = flash * 0.9
	tilt_vel += (-tilt * SPRING - tilt_vel * DAMP) * delta
	tilt += tilt_vel * delta
	tilt = tilt.limit_length(0.35)
	pivot.rotation = Vector3(tilt.x, 0.0, tilt.y)
