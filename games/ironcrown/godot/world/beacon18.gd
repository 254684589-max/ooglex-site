class_name Beacon18
extends RefCounted
## 熄掉的第十八烽（路线图 5.5a；STORY.md 5.8 支线「熄掉的第十八烽」）：第十九烽往西一百多米的山脊上，一座圆石塔。
## 比第十九烽小：没有木栅、没有营房，塔身外面一架木梯爬到塔顶；塔顶一圈矮垛口、一只冷了的铁火盆（黑炭、半盆雪）。
## 守塔的三个人已经长眠，站在塔脚的雪里，肩上落了雪，叫不醒（「长眠的守塔人」，只说一句）。
## 马蒂亚斯给你一捆柴、一罐火油（支线 ch2_beacon18）；背上塔顶，对着火盆「添柴点火」：火着了（`ch2_beacon18` = lit），塔顶一团火、火光、隔着雾也看得见的暖光晕。
## 爬梯子：Examine「爬上去 / 爬下去」直接把人放到塔顶 / 塔脚（不走区域切换）。

const H := 9.0                      # 塔身高（塔顶地面）
const R_BOT := 2.5
const R_TOP := 2.1
const MERLONS := 10
const DETAIL_FAR := 110.0
const LINES := {
	"sleeper": ["（他闭着眼，站在雪里，肩上落了一层雪。叫不醒。）", "（她的嘴唇冻得发紫，眼皮底下的眼珠一动不动。）", "（他手里还攥着一根没点着的火把。）"],
}
const SLEEPERS := [[Vector2(-3.4, 2.6), 0.15], [Vector2(-1.6, 4.1), -0.1], [Vector2(2.9, 3.5), 0.3]]   # 塔脚南边（本地，+Y 是南），面朝北


static func base_y() -> float:
	var c := HighlandLayout.BEACON18
	return Highland.height_at(c.x, c.y) - 0.05


static func lit() -> bool:
	return str(GameState.get_flag("ch2_beacon18", "")) == "lit"


static func build(parent: Node3D, reduced_motion := false) -> Node3D:
	var c := HighlandLayout.BEACON18
	var root := Node3D.new()
	root.name = "Beacon18"
	root.position = Vector3(c.x, base_y(), c.y)
	parent.add_child(root)
	_tower(root)
	_colliders(root)
	_climb(root)
	var brazier := Examine.make("第十八烽的火盆", "添柴点火", func(who: FpController) -> Dictionary: return _light(root, who, reduced_motion), Vector3(1.6, 1.4, 1.6))
	brazier.name = "Brazier18"
	brazier.position = Vector3(0, H, 0)
	brazier.verb_fn = func() -> String: return "看火" if lit() else "添柴点火"
	root.add_child(brazier)
	if lit():
		_fire(root, reduced_motion)
	return root


## 塔脚的三个长眠的守塔人（highland.gd people 时放）
static func people(parent: Node3D) -> void:
	var c := HighlandLayout.BEACON18
	for k in SLEEPERS.size():
		var q: Vector2 = c + (SLEEPERS[k][0] as Vector2)
		var n := Npc.make("长眠的守塔人", [LINES.sleeper[k]], Color("3e3a34"))
		n.name = "Npc_beacon18_%d" % k
		n.position = Vector3(q.x, Highland.height_at(q.x, q.y), q.y)
		n.rotation.y = float(SLEEPERS[k][1])
		n.far_end = DETAIL_FAR
		parent.add_child(n)


static func _tower(root: Node3D) -> void:
	var kit := MeshKit.new()
	kit.cylinder("stone", Vector3(0, -0.4, 0), Vector3(0, 0.6, 0), R_BOT + 0.35, R_BOT + 0.25, 14, 0.7)          # 基石
	kit.cylinder("stone", Vector3(0, 0.6, 0), Vector3(0, H - 0.2, 0), R_BOT, R_TOP, 14, 0.95)
	kit.cylinder("stone", Vector3(0, H - 0.2, 0), Vector3(0, H, 0), R_TOP + 0.2, R_TOP + 0.2, 14, 0.8)             # 塔顶一圈挑出来的石沿
	for k in MERLONS:                                                                                            # 垛口
		var a := TAU * k / MERLONS
		var p := Vector3(cos(a), 0, sin(a)) * (R_TOP + 0.05)
		kit.box("stone", p + Vector3(0, H + 0.45, 0), Vector3(0.7, 0.9, 0.38), Basis(Vector3.UP, -a + PI * 0.5), 0.9, 0.7)
	for k in 4:                                                                                                  # 几道窄窗缝
		var a := TAU * k / 4.0 + 0.6
		var p := Vector3(cos(a), 0, sin(a)) * (lerpf(R_BOT, R_TOP, 0.55) + 0.02)
		kit.box("slit", p + Vector3(0, H * 0.55, 0), Vector3(0.12, 0.7, 0.06), Basis(Vector3.UP, -a + PI * 0.5))
	kit.cylinder("iron", Vector3(0, H, 0), Vector3(0, H + 0.55, 0), 0.06, 0.06, 6)                               # 火盆：铁脚、铁盆，盆里黑炭和半盆雪
	kit.cylinder("iron", Vector3(0, H + 0.55, 0), Vector3(0, H + 1.05, 0), 0.45, 0.75, 10)
	kit.cylinder("char", Vector3(0, H + 0.95, 0), Vector3(0, H + 1.0, 0), 0.68, 0.68, 10)
	if not lit():
		kit.cylinder("snow", Vector3(0.1, H + 1.0, 0.05), Vector3(0.1, H + 1.08, 0.05), 0.5, 0.35, 10)
	var lad := Vector3(0, 0, R_BOT + 0.15)                                                                       # 南边一架木梯（斜靠着塔身）
	for sx in [-0.28, 0.28]:
		kit.cylinder("timber", lad + Vector3(sx, 0, 0.9), Vector3(sx, H + 0.5, R_TOP + 0.15), 0.045, 0.04, 5, 0.8)
	var n := int(H / 0.4)
	for k in range(1, n):
		var t := float(k) / n
		var a := (lad + Vector3(0, 0, 0.9)).lerp(Vector3(0, H + 0.5, R_TOP + 0.15), t)
		kit.box("timber", a, Vector3(0.6, 0.05, 0.06), Basis.IDENTITY, 0.75, 0.6)
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color("e8eef4")
	snow.roughness = 0.9
	snow.vertex_color_use_as_albedo = true
	var char_m := StandardMaterial3D.new()
	char_m.albedo_color = Color("1a1412")
	char_m.roughness = 0.95
	var mi := kit.build({"stone": Look.mat("stone"), "timber": Look.mat("timber"), "iron": Inn._iron_mat(), "char": char_m, "snow": snow, "slit": Inn._unshaded(Color("0c0a08"))})
	mi.name = "Beacon18Tower"
	mi.visibility_range_end = 400.0
	root.add_child(mi)


## 塔身、塔顶的垛口一圈（站在塔顶不会掉下去）
static func _colliders(root: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Beacon18Solid"
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = R_TOP + 0.2
	cyl.height = H
	cs.shape = cyl
	cs.position.y = H * 0.5
	body.add_child(cs)
	for k in MERLONS:
		var a := TAU * k / MERLONS
		var w := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(1.45, 1.4, 0.3)
		w.shape = bx
		w.position = Vector3(cos(a), 0, sin(a)) * (R_TOP + 0.15) + Vector3(0, H + 0.7, 0)
		w.rotation.y = -a + PI * 0.5
		body.add_child(w)
	root.add_child(body)


## 梯子两头：塔脚「爬上去」、塔顶「爬下去」
static func _climb(root: Node3D) -> void:
	var foot := Vector3(0, 0, R_BOT + 1.6)
	var top := Vector3(0, H + 0.05, R_TOP - 0.9)
	var up := Examine.make("木梯", "爬上去", func(who: FpController) -> Dictionary:
		who.global_position = root.to_global(top)
		who.velocity = Vector3.ZERO
		return {"kind": "climb", "name": "第十八烽塔顶", "toast": "顺着冻硬的木梯爬上塔顶。"}, Vector3(1.0, 2.0, 0.8))
	up.name = "Ladder18Up"
	up.position = Vector3(0, 0, R_BOT + 0.9)
	root.add_child(up)
	var down := Examine.make("木梯", "爬下去", func(who: FpController) -> Dictionary:
		who.global_position = root.to_global(foot)
		who.velocity = Vector3.ZERO
		return {"kind": "climb", "name": "第十八烽塔脚", "toast": "爬下塔去。"}, Vector3(0.9, 0.9, 0.6))
	down.name = "Ladder18Down"
	down.position = Vector3(0, H, R_TOP + 0.05)
	root.add_child(down)


## 对着火盆：有柴有油就点着（支线做完）；缺什么说什么
static func _light(root: Node3D, _who: FpController, reduced_motion: bool) -> Dictionary:
	if lit():
		return {"kind": "examine", "toast": "火烧得正旺。往东看，第十九烽的火也亮着。"}
	var need := []
	if not GameState.has_item("firewood"):
		need.append("一捆柴")
	if not GameState.has_item("lamp_oil"):
		need.append("一罐火油")
	if not need.is_empty():
		return {"kind": "examine", "toast": "火盆冷透了，盆底半盆雪。要点着它，得有%s。" % "和".join(need)}
	GameState.take_item("firewood")
	GameState.take_item("lamp_oil")
	GameState.set_flag("ch2_beacon18", "lit")
	if GameState.quest_active("ch2_beacon18"):
		GameState.complete_quest("ch2_beacon18")
	_fire(root, reduced_motion)
	return {"kind": "examine", "name": "第十八烽的火盆", "toast": "你扒掉盆里的雪，码上柴，浇上油，打着火石——火呼地窜起来。往东看，第十九烽的火隔着山脊亮着；现在两座都亮了。"}


## 塔顶的火：几片卷动的火苗、火光（组 light_source）、近处一团光、远处隔着雾也看得见的暖光晕
static func _fire(root: Node3D, reduced_motion: bool) -> void:
	if root.get_node_or_null("Fire18") != null:
		return
	var fire := Node3D.new()
	fire.name = "Fire18"
	root.add_child(fire)
	var sh := load("res://shaders/flame.gdshader") as Shader
	for k in 3:
		var q := QuadMesh.new()
		var fw: float = [1.2, 0.9, 0.8][k]
		var fh: float = [1.9, 1.5, 1.3][k]
		q.size = Vector2(fw, fh)
		var fm := ShaderMaterial.new()
		fm.shader = sh
		fm.set_shader_parameter("noise_tex", Look.noise_texture())
		fm.set_shader_parameter("phase", 0.29 * k + 0.13)
		fm.set_shader_parameter("speed", 0.0 if reduced_motion else 1.0)
		fm.set_shader_parameter("strength", 1.25 if k == 0 else 1.0)
		q.material = fm
		var fl := MeshInstance3D.new()
		fl.mesh = q
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fl.visibility_range_end = 150.0
		var off: Vector3 = [Vector3.ZERO, Vector3(0.2, 0, 0.1), Vector3(-0.18, 0, -0.1)][k]
		fl.position = off + Vector3(0, H + 0.95 + fh * 0.5, 0)
		fire.add_child(fl)
	var light := Tavern.FireLight.new()
	light.light_color = Color("ff8a3a")
	light.base = 5.0
	light.omni_range = 22.0
	light.omni_attenuation = 1.3
	light.flicker = not reduced_motion
	light.position = Vector3(0, H + 1.8, 0)
	light.distance_fade_enabled = true
	light.distance_fade_begin = 90.0
	light.distance_fade_length = 20.0
	light.add_to_group("light_source")
	light.set_meta("radius", 2.4)
	fire.add_child(light)
	var glow := MeshInstance3D.new()
	var g := QuadMesh.new()
	g.size = Vector2(36.0, 36.0)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gm.albedo_texture = Look.halo_texture()
	gm.albedo_color = Color(1.0, 0.55, 0.22, 0.55)
	gm.disable_fog = true
	g.material = gm
	glow.mesh = g
	glow.position = Vector3(0, H + 1.6, 0)
	glow.name = "Beacon18Glow"
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fire.add_child(glow)
