class_name CombatFx
extends Node3D
## 战斗特效（路线图 C.1）。贴合本作的低魔写实：没有法术光，只有钢刃划过的一道冷白刀光、格挡时迸出的火星、
## 砍中时几滴暗红的血、拳头和钝器打中时扬起的一点灰、木桩上崩出的木屑。都在代码里搭（不用外部贴图），自己到时间就删掉。
##   slash()：一条弧形的带子（shaders/slash.gdshader），亮的刀头顺着弧走过去、拖一段渐暗的尾巴。玩家按招式和连击段换方向
##     （第一段右上往左下、第二段左上往右下、第三段和重击从头顶劈下），敌人按自己的朝向；
##   impact()：一团一次性的 CPUParticles3D，加一下叠加混合的闪光（火星、完美格挡）。
## 同时存在的特效最多 MAX_ALIVE 个（军阵里兵打兵很多，超了就不再出）；低画质（low）粒子数减半。

const MAX_ALIVE := 14
const ARC_SEG := 20
const ARC_SPAN := 62.0          # 弧从正前方往两边各张开多少度
const ARC_R := 0.95             # 外沿（刀尖）离眼睛多远
const ARC_IN := 0.6             # 内沿
const STEEL := Color(0.8, 0.86, 0.95, 0.6)
const STEEL_HEAVY := Color(0.93, 0.9, 0.82, 0.8)
const IRON := Color(0.7, 0.68, 0.64, 0.42)          # 钝器：灰一点、淡一点

static var low := false
static var alive := 0
static var spawned := 0             # 一共出过几个（测试看）
static var _arc: ArrayMesh
static var _crescent: ArrayMesh
static var _shader: Shader
static var _mats := {}
static var _flash_tex: GradientTexture2D

var what := ""                   # "slash" 或 impact 的 kind（同名兄弟节点会被引擎改名，测试按这个认）
var left := 0.0
var dur := 0.0
var delay := 0.0
var t := 0.0
var mat: ShaderMaterial
var flash: MeshInstance3D
var flash_mat: StandardMaterial3D


func _enter_tree() -> void:
	alive += 1


func _exit_tree() -> void:
	alive = maxi(alive - 1, 0)


static func room() -> bool:
	return alive < MAX_ALIVE


# ---------------- 刀光 ----------------

## 玩家挥砍。第一人称：眼前 0.85 米一道正对着你的月牙（绕着眼睛转的弧会正好侧对着你，看着只是一条线）；
## 第三人称：和敌人一样绕着身子胸口高度的一圈。combo 是这一段连击（0、1、2），skill 是武器的技能（blade / blunt / brawl）
static func slash_player(player: FpController, kind: String, combo: int, skill: String, wait: float, length: float) -> CombatFx:
	if skill == "brawl" or kind == "dash" or not room() or player.get_parent() == null:
		return null
	var roll := 20.0
	var mirror := false
	if kind == "heavy" or combo == 2:
		roll = 84.0
	elif combo % 2 == 1:
		roll = -20.0
		mirror = true
	if player.third_person:
		var f := player.aim_forward()
		f.y = 0.0
		if f.length() < 0.01:
			return null
		var at := Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), player.global_position + Vector3(0, 1.3, 0))
		return slash(player.get_parent(), at, roll, mirror, kind == "heavy", skill, wait, length)
	var basis := player.camera.global_transform.basis.orthonormalized()
	var origin := player.aim_origin() - basis.z * 0.85 - basis.y * 0.12
	return slash(player.get_parent(), Transform3D(basis, origin), roll, mirror, kind == "heavy", skill, wait, length, true)


## 敌人 / 兵挥砍：胸口高度，按它的朝向；方向从三种里随机挑
static func slash_enemy(e: Node3D, fwd: Vector3, kind: String, weapon: String, length: float, pick: int) -> CombatFx:
	if not weapon in ["sword", "club"] or kind == "kick" or not room() or e.get_parent() == null:
		return null
	var f := Vector3(fwd.x, 0, fwd.z)
	if f.length() < 0.01:
		return null
	var basis := Basis.looking_at(f.normalized(), Vector3.UP)
	var origin := e.global_position + Vector3(0, 1.3, 0)
	var rolls := [[20.0, false], [-20.0, true], [84.0, false]]
	var r: Array = rolls[(2 if kind == "heavy" else pick) % rolls.size()]
	return slash(e.get_parent(), Transform3D(basis, origin), float(r[0]), bool(r[1]), kind == "heavy", "blunt" if weapon == "club" else "blade", 0.0, length)


static func slash(parent: Node, at: Transform3D, roll_deg: float, mirror: bool, heavy: bool, skill: String, wait: float, length: float, facing := false) -> CombatFx:
	var fx := CombatFx.new()
	fx.name = "Slash"
	fx.what = "slash"
	fx.delay = wait
	fx.dur = maxf(length, 0.08)
	fx.left = wait + fx.dur + 0.05
	var mi := MeshInstance3D.new()
	mi.mesh = crescent_mesh() if facing else arc_mesh()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.mat = ShaderMaterial.new()
	fx.mat.shader = _slash_shader()
	var blunt := skill in ["blunt", "club"]
	fx.mat.set_shader_parameter("tint", IRON if blunt else (STEEL_HEAVY if heavy else STEEL))
	fx.mat.set_shader_parameter("energy", 1.35 if heavy else 1.0)
	fx.mat.set_shader_parameter("tail", 0.6 if heavy else 0.45)
	fx.mat.set_shader_parameter("progress", 0.0)
	mi.material_override = fx.mat
	mi.visible = wait <= 0.0
	var s := 1.12 if heavy else 1.0
	mi.scale = Vector3(-s if mirror else s, s, s)
	mi.rotation = Vector3(deg_to_rad(-28.0) if facing else 0.0, 0.0, deg_to_rad(roll_deg))     # 月牙上沿往远处倒一点，看得出深浅
	fx.add_child(mi)
	parent.add_child(fx)
	fx.global_transform = at
	spawned += 1
	return fx


## 弧形带子：在眼前的水平面里从右（+ARC_SPAN）扫到左（−ARC_SPAN）；UV.x 沿弧，UV.y 内沿 0 → 外沿 1
static func arc_mesh() -> ArrayMesh:
	if _arc:
		return _arc
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in ARC_SEG:
		var a0 := deg_to_rad(lerpf(ARC_SPAN, -ARC_SPAN, float(i) / ARC_SEG))
		var a1 := deg_to_rad(lerpf(ARC_SPAN, -ARC_SPAN, float(i + 1) / ARC_SEG))
		var u0 := float(i) / ARC_SEG
		var u1 := float(i + 1) / ARC_SEG
		var p := [Vector3(sin(a0), 0, -cos(a0)) * ARC_IN, Vector3(sin(a0), 0, -cos(a0)) * ARC_R,
			Vector3(sin(a1), 0, -cos(a1)) * ARC_IN, Vector3(sin(a1), 0, -cos(a1)) * ARC_R]
		var uv := [Vector2(u0, 0), Vector2(u0, 1), Vector2(u1, 0), Vector2(u1, 1)]
		for k in [0, 1, 2, 2, 1, 3]:
			st.set_uv(uv[k])
			st.set_normal(Vector3.UP)
			st.add_vertex(p[k])
	_arc = st.commit()
	return _arc


## 正对着你的月牙（第一人称）：在 XY 平面里，从右（+CRESCENT_SPAN）扫到左；拱顶在中心上方，两头往下垂
const CRESCENT_SPAN := 66.0
const CRESCENT_R := 0.76
const CRESCENT_IN := 0.6
const CRESCENT_DROP := 0.64
static func crescent_mesh() -> ArrayMesh:
	if _crescent:
		return _crescent
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in ARC_SEG:
		var a0 := deg_to_rad(lerpf(CRESCENT_SPAN, -CRESCENT_SPAN, float(i) / ARC_SEG))
		var a1 := deg_to_rad(lerpf(CRESCENT_SPAN, -CRESCENT_SPAN, float(i + 1) / ARC_SEG))
		var u0 := float(i) / ARC_SEG
		var u1 := float(i + 1) / ARC_SEG
		var d := Vector3(0, CRESCENT_DROP, 0)
		var p := [Vector3(sin(a0), cos(a0), 0) * CRESCENT_IN - d, Vector3(sin(a0), cos(a0), 0) * CRESCENT_R - d,
			Vector3(sin(a1), cos(a1), 0) * CRESCENT_IN - d, Vector3(sin(a1), cos(a1), 0) * CRESCENT_R - d]
		var uv := [Vector2(u0, 0), Vector2(u0, 1), Vector2(u1, 0), Vector2(u1, 1)]
		for k in [0, 1, 2, 2, 1, 3]:
			st.set_uv(uv[k])
			st.set_normal(Vector3.BACK)
			st.add_vertex(p[k])
	_crescent = st.commit()
	return _crescent


static func _slash_shader() -> Shader:
	if _shader == null:
		_shader = load("res://shaders/slash.gdshader")
	return _shader


# ---------------- 打中 ----------------

## 打中的地方迸出来的东西。out = 往外飞的方向（一般朝着出手的人）；kind：
##   metal（格挡的火星）、perfect（完美格挡：更多更亮）、break（破防：火星加碎屑）、flesh（砍中：几滴暗红）、dust（拳头、钝器：一点灰）、wood（木屑）
static func impact(parent: Node, at: Vector3, out: Vector3, kind: String) -> CombatFx:
	if parent == null or not room():
		return null
	var fx := CombatFx.new()
	fx.name = "Impact"
	fx.what = kind
	fx.left = 0.7
	parent.add_child(fx)
	fx.global_position = at
	var dir := out.normalized() if out.length() > 0.01 else Vector3.UP
	dir = (dir + Vector3(0, 0.45, 0)).normalized()
	var k := 0.5 if low else 1.0
	match kind:
		"metal":
			fx._burst(int(14 * k), dir, 55.0, 2.8, 5.5, 0.28, Color(1.0, 0.78, 0.4), Color(1.0, 0.35, 0.06, 0.2), 0.034, true)
			fx._flash(0.2, Color(1.0, 0.75, 0.45, 0.8), 0.07)
		"perfect":
			fx._burst(int(24 * k), dir, 75.0, 3.5, 7.0, 0.36, Color(1.0, 0.9, 0.62), Color(1.0, 0.45, 0.1, 0.2), 0.04, true)
			fx._flash(0.34, Color(1.0, 0.92, 0.75, 0.9), 0.11)
		"break":
			fx._burst(int(12 * k), dir, 70.0, 2.0, 4.5, 0.3, Color(1.0, 0.75, 0.38), Color(1.0, 0.32, 0.06, 0.2), 0.032, true)
			fx._burst(int(8 * k), dir, 60.0, 1.0, 2.5, 0.45, Color(0.55, 0.5, 0.45), Color(0.4, 0.38, 0.35, 0.0), 0.05, false)
			fx._flash(0.24, Color(1.0, 0.72, 0.42, 0.8), 0.08)
		"flesh":
			fx._burst(int(9 * k), dir, 45.0, 1.4, 3.0, 0.42, Color(0.58, 0.06, 0.04), Color(0.4, 0.03, 0.02, 0.0), 0.04, false)
		"dust":
			fx._burst(int(7 * k), dir, 80.0, 0.5, 1.4, 0.45, Color(0.75, 0.71, 0.65, 0.6), Color(0.7, 0.66, 0.6, 0.0), 0.14, false, 0.25)
		"wood":
			fx._burst(int(9 * k), dir, 60.0, 1.5, 3.2, 0.42, Color(0.78, 0.6, 0.38), Color(0.6, 0.45, 0.28, 0.0), 0.045, false)
	spawned += 1
	return fx


func _burst(n: int, dir: Vector3, spread: float, v0: float, v1: float, life: float, c0: Color, c1: Color, size: float, additive: bool, grav := 1.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(n, 2)
	p.lifetime = life
	p.local_coords = false
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = v0
	p.initial_velocity_max = v1
	p.gravity = Vector3(0, -9.8 * grav, 0)
	p.damping_min = 0.5
	p.damping_max = 1.5
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var sc := Curve.new()                           # 越飞越小，不是一块方片停在空中
	sc.add_point(Vector2(0, 1))
	sc.add_point(Vector2(1, 0.25))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _particle_mat(additive)
	p.mesh = q
	p.emitting = true
	add_child(p)


static func _particle_mat(additive: bool) -> StandardMaterial3D:
	var key := "add" if additive else "mix"
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _flash_texture()             # 圆的、边上虚的一点，不是方片
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.no_depth_test = true                      # 火星压在兵器和身子上面（碰上的地方常被对方的身子挡住）
	m.disable_receive_shadows = true
	_mats[key] = m
	return m


func _flash(size: float, c: Color, time: float) -> void:
	flash = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	flash.mesh = q
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash_mat = StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_mat.albedo_texture = _flash_texture()
	flash_mat.albedo_color = c
	flash_mat.no_depth_test = true
	flash.material_override = flash_mat
	flash.set_meta("time", time)
	flash.set_meta("a0", c.a)
	add_child(flash)


static func _flash_texture() -> GradientTexture2D:
	if _flash_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.25, Color(1, 1, 1, 0.55))
		_flash_tex = GradientTexture2D.new()
		_flash_tex.gradient = g
		_flash_tex.fill = GradientTexture2D.FILL_RADIAL
		_flash_tex.fill_from = Vector2(0.5, 0.5)
		_flash_tex.fill_to = Vector2(1.0, 0.5)
		_flash_tex.width = 64
		_flash_tex.height = 64
	return _flash_tex


func _process(delta: float) -> void:
	left -= delta
	if mat:
		if delay > 0.0:
			delay -= delta
			if delay <= 0.0:
				(get_child(0) as Node3D).visible = true
		else:
			t += delta
			mat.set_shader_parameter("progress", 1.4 * t / dur)
	if flash:
		var ft := float(flash.get_meta("time"))
		var k := clampf((0.7 - left) / ft, 0.0, 1.0)
		flash.scale = Vector3.ONE * (0.6 + 0.8 * k)
		flash_mat.albedo_color.a = float(flash.get_meta("a0")) * (1.0 - k)
		if k >= 1.0:
			flash.queue_free()
			flash = null
	if left <= 0.0:
		queue_free()
