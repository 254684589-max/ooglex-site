class_name SleeperCrowd
extends Node3D
## 长眠者群（路线图 5.4a；STORY.md 5.7「长眠者群」；WORLD.md 4.2「人越多走得越快」）：几十个睡着了不醒、光着脚往北走的人，一起走成一股「潮水」。
## 不进士兵 AI、不占军阵 60 人的名额：每个人只是一个点，按简化的群体规则走——
##   跟着一条路线（route，XZ 折线）往前，各自在路线左右偏一点（lateral）排成一股；
##   互相让开（离得太近就往外推，按格子找邻居）；
##   绕开火：亮着的火（组 light_source 带 radius 元数据：铁匠炉、火盆、篝火；5.4b 起插在地上的火把在组 crowd_fire）半径里往外推、顺着火边绕过去——
##     火能让它们拐弯，所以火把能「引」着它们走；
##   绕开 obstacles（[圆心, 半径]，例如房子、塔）；
##   人越多走得越快（speed_base × (1 + 每人 0.6%)，最多快 45%）。
## 挡在前面的人：主角被推倒（躺 KNOCK_SEC 秒）、踩过（每个人每 TRAMPLE_GAP 秒最多踩一下：伤害、寒冷值 +TRAMPLE_COLD）。它们叫不醒、杀不死（不进打击的层，剑砍不着——5.4a 先不处理砍）。
## 画法（性能）：远处的人是一个多实例（代码搭的简单人形：浅色的睡衣、光着的头和手，走路时上下颠一点），一次画完；
##   离镜头最近、NEAR_DIST 以内的 NEAR_MAX 个换成真人模型（A.2 的村民打扮、浅色衣服，慢慢地走），多实例里那个藏起来。
## 走到路线尽头就不在了（done）。逻辑每 TICK 秒算一次（20 赫兹），位置在两次之间插值画。

signal trampled(count: int)            # 主角被踩了一下（第几次）
signal knocked                         # 主角被推倒
signal finished                        # 全走完了

const TICK := 0.05
const NEAR_MAX := 8
static var near_max := NEAR_MAX          # 按画质（main：低 3、中 5、高 8）。一个真人模型约 8 次绘制调用：中档 40 人加五支火把时 426 → 5 个 400 以内
var near_cap := NEAR_MAX                # 这一群最多几个（劫粮那场仗里兵已经占了绘制调用：2）
const NEAR_DIST := 18.0
const SPACING := 0.95                  # 互相让开：比这近就推
const CELL := 1.6
const FIRE_GAIN := 2.0                 # 火的半径（radius 元数据）乘多少算「火边」：在这里面就往外绕
const FIRE_MARGIN := 2.0
const KNOCK_DIST := 0.75
const KNOCK_SEC := 1.6
const TRAMPLE_GAP := 1.0
const TRAMPLE_DAMAGE := 5
const TRAMPLE_COLD := 12.0
const LINEN := Color("85827c")         # 睡衣：灰白的粗麻，脏、潮（2026-11-07 所有者「长眠者不恐怖」：原来 b9b3a6 太干净）
const SKIN := Color("a7b0b8")          # 失温的灰青皮肤（原来 c9a58c 是活人的肤色）
const HAIR := Color("70757b")          # 头发上结了霜
const EYE := Color("0e0f12")           # 眼窝：两道深陷的暗影（眼睛闭着）
const LAYER := 2                         # 渲染层 2（火把的光跳过这一层）
const LINEN_TINT := Color(0.92, 0.98, 1.08)  # 真人模型：农夫衣服的贴图是深褐色，乘上去变成灰白的脏粗麻（原来 1.85, 2.2, 2.8 太白太干净）
const SKIN_TINT := Color(0.58, 0.68, 0.8)   # 皮肤贴图乘上去：失温的灰青色，嘴唇、指尖跟着发青
const EYE_TINT := Color(0.16, 0.17, 0.2)     # 眼睛的材质压暗：远看是闭着的、深陷的眼窝（不是睁着的眼珠）
const FROST := Color(0.86, 0.9, 0.95)        # 头发往这个颜色混：结了一层霜
const FROST_MIX := 0.45
const SKIN_KEYS := ["MI_Superhero_Male", "MI_Superhero_Female", "MI_Regular_Male", "MI_Regular_Female"]


## 长眠者的样子（2026-11-07 所有者「长眠者做的不恐怖，能再恐怖些吗」→「先设计一下形象」）：Looks 的外观再改一遍——
## 灰白的脏麻衣、失温发青的皮肤、深陷发暗的眼窝、头发上结霜；自发光跟着底色（CharacterModel），暗处透出一点冷光。认得的脸（妮尔、托宾……）也一样换。
static func chill(spec: Dictionary) -> Dictionary:
	if spec.is_empty():
		return spec
	var tint: Dictionary = (spec.look.get("tint", {}) as Dictionary).duplicate()
	tint["MI_Peasant"] = LINEN_TINT
	for k in SKIN_KEYS:
		tint[k] = SKIN_TINT
	tint["MI_Eyes"] = EYE_TINT
	for k in ["MI_Hair_1", "MI_Hair_2"]:
		var h: Variant = tint.get(k, "#3a2a1a")
		var c: Color = h if h is Color else Color(str(h))
		tint[k] = c.lerp(FROST, FROST_MIX)
	spec.look["tint"] = tint
	spec.look["slump"] = true                       # 头垂下去、歪向一边（SleeperSlump）
	return spec

var route: Array = []                  # [Vector2, ...]
var width := 6.0                       # 一股多宽（米）
var speed_base := 0.75
var count := 30
var spawn_gap := 0.7                   # 前后隔多远出来一个（米，沿路线往后排）
var obstacles: Array = []              # [[Vector2 圆心, 半径], ...]
var alt_route: Array = []              # 5.4c：碰到火的人改走这条（「火让它们拐弯」：第一夜那排火把把潮水从营地引到西边绕过去）；空 = 不改道
var hidden := {}                       # 5.4c：这几个人不画（编号 → true），由外面换成别的模型（潮水里认得的那张脸）
var rerouted := 0                      # 改了道的人数
var victims: Array = []                # 5.7a：会被推倒踩过的兵（Soldier.trampled）
var trampled_soldiers := 0
const SOLDIER_KNOCK := 0.9
const SOLDIER_TRAMPLE_DMG := 6
const SOLDIER_FEAR := 12.0
var player: FpController
var height_fn: Callable                # (x, z) -> y；空 = 都在 y = 0
var near_enabled := true               # 测试里可以关掉真人模型（无头测试不加载模型也行）

var agents: Array = []                 # 每个人：{p: Vector2, prev: Vector2, v: Vector2, seg: int, lat: float, sp: float, phase: float, done: bool, last_trample: float, near: int}
var mm: MultiMeshInstance3D
var mist: MultiMeshInstance3D            # 脚下贴地的薄白雾（2026-11-07）：每人一片，一次画完
var hum: SleeperHum                      # 走近时听得见的呼吸和脚步（2026-11-07）
var _near_d := INF                       # 离镜头最近的那个人多远（声音、火把用）
const MIST_SIZE := 3.4
const TORCH_DIM_R := 6.0                 # 火把离最近的人这么近就开始暗下去
const TORCH_DIM_MIN := 0.35
var models: Array = []                 # 真人模型池
var _acc := 0.0
var _clock := 0.0
var _fires: Array = []
var _fires_left := 0.0
var _tramples := 0
var _done_sent := false


static func make(p_route: Array, p_count: int, p_width := 6.0) -> SleeperCrowd:
	var c := SleeperCrowd.new()
	c.name = "SleeperCrowd"
	c.route = p_route
	c.count = p_count
	c.width = p_width
	return c


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5401 + count
	var start: Vector2 = route[0]
	var dir0: Vector2 = ((route[1] as Vector2) - start).normalized()
	for i in count:
		var lat := rng.randf_range(-0.5, 0.5) * width
		var back := i * spawn_gap / maxf(1.0, width / 2.2) + rng.randf_range(0.0, 0.6)
		var p := start - dir0 * back + Vector2(-dir0.y, dir0.x) * lat
		agents.append({"p": p, "prev": p, "v": Vector2.ZERO, "seg": 0, "lat": lat, "sp": rng.randf_range(0.88, 1.12), "phase": rng.randf() * TAU,
			"done": false, "last_trample": -99.0, "detour": 0, "detour_t": 0.0, "near": -1, "tint": rng.randf_range(0.85, 1.05)})
	mm = MultiMeshInstance3D.new()
	mm.name = "CrowdFar"
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.use_colors = true
	m.mesh = figure_mesh()
	m.instance_count = count
	mm.multimesh = m
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mm.layers = LAYER                       # 火把的光不照它们（TorchHand.LIGHT_MASK）：几十个人每多一盏灯都要多画一遍；它们自己有一点自发光
	add_child(mm)
	mist = MultiMeshInstance3D.new()
	mist.name = "Mist"
	var mq := QuadMesh.new()
	mq.size = Vector2(MIST_SIZE, MIST_SIZE)
	mq.orientation = PlaneMesh.FACE_Y
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/ground_mist.gdshader")
	mq.material = sm
	var mmist := MultiMesh.new()
	mmist.transform_format = MultiMesh.TRANSFORM_3D
	mmist.use_colors = true
	mmist.mesh = mq
	mmist.instance_count = count
	mist.multimesh = mmist
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mist)
	hum = SleeperHum.make(func() -> float: return _near_d, true)
	add_child(hum)
	if near_enabled:
		for k in mini(near_max, near_cap):
			var spec := Looks.spec_of({"preset": "woman" if k % 3 == 1 else "commoner", "hair": [["Hair_Buzzed"], ["Hair_Long"], ["Hair_SimpleParted"]][k % 3],
				"hair_color": ["#3a2a1a", "#6a5a4a", "#9a948a", "#2a2018"][k % 4]})
			if spec.is_empty():
				break
			chill(spec)
			var cm := CharacterModel.new()
			cm.name = "Sleeper%d" % k
			cm.parts = spec.parts
			cm.look = spec.look
			cm.set_meta("hide", spec.hide)
			cm.visible = false
			add_child(cm)
			if cm.loaded:
				Looks.hide_parts(cm)
				cm.play_loop("walk", 0.62)
				cm.anim.seek(randf() * cm.clip_length("walk"), true)
				for mi: MeshInstance3D in cm.scene_root.find_children("*", "MeshInstance3D", true, false):
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					mi.layers = LAYER                # 火把的光不照（同多实例那份）
				models.append(cm)
			else:
				cm.queue_free()
	_draw(0.0)


## 远处的人形（约 1.7 米）：两条腿、身子、两条垂着的胳膊、头；顶点色 r = 睡衣还是皮肤（多实例的颜色再乘一遍）
static func figure_mesh() -> ArrayMesh:
	var kit := MeshKit.new()
	# 2026-11-07（所有者「队伍中还有一部分是方块人物」）：原来 6–10 边的圆台，远看一节一节像方块；边数加到 14–18、关节处多接一段，
	# 头垂到胸前、歪向一边，肩膀往前塌——远处一眼看过去也是「睡着在走」的样子
	var hd := Vector3(0.035, -0.07, 0.11)           # 头往前、往下垂，偏向一边
	for s in [-1.0, 1.0]:
		kit.cylinder("cloth", Vector3(s * 0.09, 0.06, 0.0), Vector3(s * 0.095, 0.45, 0.01), 0.056, 0.07, 14, 0.85)        # 小腿（麻布裤）
		kit.cylinder("cloth", Vector3(s * 0.095, 0.45, 0.01), Vector3(s * 0.1, 0.84, 0.0), 0.07, 0.085, 14, 0.85)          # 大腿
		kit.cylinder("skin", Vector3(s * 0.09, 0.0, 0.05), Vector3(s * 0.09, 0.07, 0.02), 0.045, 0.05, 10, 0.8)            # 光脚（冻青）
		kit.cylinder("cloth", Vector3(s * 0.19, 1.36, 0.05), Vector3(s * 0.22, 1.1, 0.08), 0.055, 0.05, 12, 0.9)           # 上臂：肩膀往前塌，胳膊垂着
		kit.cylinder("cloth", Vector3(s * 0.22, 1.1, 0.08), Vector3(s * 0.22, 0.88, 0.1), 0.048, 0.04, 12, 0.9)            # 小臂
		kit.cylinder("skin", Vector3(s * 0.22, 0.88, 0.1), Vector3(s * 0.215, 0.76, 0.11), 0.038, 0.028, 10, 0.85)         # 手：垂着
	kit.cylinder("cloth", Vector3(0, 0.78, 0), Vector3(0, 1.0, 0.01), 0.165, 0.17, 18, 0.92)                           # 腰
	kit.cylinder("cloth", Vector3(0, 1.0, 0.01), Vector3(0, 1.2, 0.03), 0.17, 0.18, 18, 0.95)                          # 胸
	kit.cylinder("cloth", Vector3(0, 1.2, 0.03), Vector3(0, 1.38, 0.06), 0.18, 0.19, 18, 1.0)                          # 胸到肩：往前塌
	kit.cylinder("cloth", Vector3(0, 1.38, 0.06), Vector3(0, 1.43, 0.07), 0.19, 0.08, 18, 1.0)
	kit.cylinder("skin", Vector3(0, 1.41, 0.07), Vector3(hd.x * 0.5, 1.5 + hd.y * 0.5, 0.07 + hd.z * 0.5), 0.05, 0.048, 10)   # 脖子往前探
	var hc := Vector3(0, 1.52, 0.01) + hd
	kit.cylinder("skin", hc, hc + Vector3(0, 0.05, -0.01), 0.07, 0.09, 16)                                            # 头：下巴 → 颧骨 → 头顶
	kit.cylinder("skin", hc + Vector3(0, 0.05, -0.01), hc + Vector3(0, 0.12, -0.02), 0.09, 0.092, 16)
	kit.cylinder("skin", hc + Vector3(0, 0.12, -0.02), hc + Vector3(0, 0.17, -0.03), 0.092, 0.06, 16)
	kit.cylinder("hair", hc + Vector3(0, 0.1, -0.04), hc + Vector3(0, 0.21, -0.05), 0.1, 0.04, 16)                    # 头发（结霜的灰）
	for s in [-1.0, 1.0]:
		kit.box("eye", hc + Vector3(s * 0.035, 0.085, 0.085), Vector3(0.034, 0.022, 0.012))                             # 两道深陷的眼窝
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = LINEN
	cloth.vertex_color_use_as_albedo = true
	cloth.roughness = 0.95
	cloth.emission_enabled = true          # 跟近处的真人模型一样背光处有一点自发光（CharacterModel.GLOW），远近换的时候亮度对得上
	cloth.emission = LINEN
	cloth.emission_energy_multiplier = CharacterModel.GLOW * 1.4      # 原来 ×3（浅色麻衣时对过近处模型）；换成脏灰的麻衣以后远处一片发白，压下来   # 近处那份是贴图 × 两倍多的 tint 再发光，这边没贴图，乘 3 才对得上（5.4b 截图对过）
	var skin := StandardMaterial3D.new()
	skin.albedo_color = SKIN
	skin.vertex_color_use_as_albedo = true
	skin.roughness = 0.8
	skin.emission_enabled = true
	skin.emission = SKIN
	skin.emission_energy_multiplier = CharacterModel.GLOW
	var hair := StandardMaterial3D.new()
	hair.albedo_color = HAIR
	hair.vertex_color_use_as_albedo = true
	hair.roughness = 0.9
	var eye := StandardMaterial3D.new()
	eye.albedo_color = EYE
	eye.vertex_color_use_as_albedo = true
	eye.roughness = 1.0
	var mi := kit.build({"cloth": cloth, "skin": skin, "hair": hair, "eye": eye})
	var mesh := mi.mesh as ArrayMesh
	mi.free()
	return mesh


func alive() -> int:
	return agents.filter(func(a): return not a.done).size()


func tramples() -> int:
	return _tramples


func current_speed() -> float:
	return speed_base * (1.0 + minf(alive() * 0.006, 0.45))


func _physics_process(delta: float) -> void:
	_acc += delta
	_clock += delta
	while _acc >= TICK:
		_acc -= TICK
		_step(TICK)
	_draw(_acc / TICK)


## 一步：每个人往路线前方走、互相让、绕开火和障碍、推倒踩过挡路的主角
func _step(dt: float) -> void:
	_fires_left -= dt
	if _fires_left <= 0.0:
		_fires_left = 0.5
		_fires = fires(get_tree())
	var grid := {}
	for i in agents.size():
		var a: Dictionary = agents[i]
		if a.done:
			continue
		var key := Vector2i(floori(a.p.x / CELL), floori(a.p.y / CELL))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(i)
	var spd := current_speed()
	var pp := Vector2.INF
	if is_instance_valid(player):
		pp = Vector2(player.global_position.x, player.global_position.z)
	for i in agents.size():
		var a: Dictionary = agents[i]
		if a.done:
			continue
		a.prev = a.p
		var want := _route_dir(a)
		if a.done:
			continue
		var rt: Array = alt_route if bool(a.get("alt", false)) else route
		if int(a.detour) != 0 and int(a.seg) < rt.size() - 1:
			want = ((rt[int(a.seg) + 1] as Vector2) - (rt[int(a.seg)] as Vector2)).normalized()   # 正在绕火：只朝路线的方向，不往路线中间拉（不然在一排火把前面横向拉扯、停住）
		var push := Vector2.ZERO
		var key := Vector2i(floori(a.p.x / CELL), floori(a.p.y / CELL))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for j in grid.get(key + Vector2i(dx, dz), []):
					if j == i:
						continue
					var off: Vector2 = a.p - (agents[j] as Dictionary).p
					var d := off.length()
					if d < SPACING and d > 0.001:
						push += off / d * (SPACING - d) / SPACING
		var steer := Vector2.ZERO
		var fire_n := _fires.size()
		var all_f: Array = _fires + obstacles
		for fi in all_f.size():
			var f: Array = all_f[fi]
			var c: Vector2 = f[0]
			var r := float(f[1])
			var off: Vector2 = a.p - c
			var d := off.length()
			if fi < fire_n and d < r + FIRE_MARGIN and not alt_route.is_empty() and not bool(a.get("alt", false)):
				_switch_alt(a)                                           # 碰到火：改走绕开营地的那条
			if d < r and d > 0.001:
				steer += off / d * (2.5 + 3.0 * (r - d) / r)                # 已经在火边里面：只往外推（5.4b：一排插得密的火把，两支中间的空当不能钻——顺着火边绕会把人往空当里送）
			elif d < r + FIRE_MARGIN and d > 0.001:
				var out := off / d
				var k := clampf((r + FIRE_MARGIN - d) / FIRE_MARGIN, 0.0, 1.0)
				var left := Vector2(-want.y, want.x)
				if int(a.detour) == 0:                                   # 第一次碰到火：定下往哪边绕（人在火的哪一边就往哪边；正对着按自己在队伍里偏左偏右）
					var cr := left.dot(off)
					a.detour = 1 if (cr > 0.05 or (absf(cr) <= 0.05 and float(a.lat) >= 0.0)) else -1
				a.detour_t = _clock
				var side := Vector2(-out.y, out.x)
				if side.dot(want + left * float(a.detour)) < 0.0:        # 顺着火边往前、往定下的那一边走：一排火把挨着插，大家顺着这堵墙滑到头再绕过去，不会在两支中间来回打转
					side = -side
				steer += side * 2.0 * k + out * 1.4 * k * k              # 主要是顺着火边绕；贴得很近才往外推
		if int(a.detour) != 0 and _clock - float(a.detour_t) > 2.0:
			a.detour = 0                                                  # 离开火边两秒：下次再碰到重新定
		var dir := want + push * 1.4 + steer
		if dir.length() > 0.001:
			dir = dir.normalized()
		a.v = a.v.lerp(dir * spd * float(a.sp), 0.35)
		a.p += a.v * dt
		a.phase += dt * 5.2 * spd
		if pp != Vector2.INF:
			_hit_player(a, pp)
		if not victims.is_empty() and (a.v as Vector2).length() > 0.1:
			_hit_soldiers(a)
	if not _done_sent and alive() == 0:
		_done_sent = true
		finished.emit()


## 改走 alt_route：从离自己最近的那一段接上
func _switch_alt(a: Dictionary) -> void:
	a.alt = true
	rerouted += 1
	var best := 0
	var bd := INF
	for k in alt_route.size() - 1:
		var p0: Vector2 = alt_route[k]
		var p1: Vector2 = alt_route[k + 1]
		var ab := p1 - p0
		var t := clampf((a.p - p0).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d: float = (a.p as Vector2).distance_to(p0 + ab * t)
		if d < bd:
			bd = d
			best = k
	a.seg = best


## 往路线前方哪个方向走：投到当前这一段上，往前看 3 米，再加上自己在路线左右的偏移；最后一段走完 = done
func _route_dir(a: Dictionary) -> Vector2:
	var rt: Array = alt_route if bool(a.get("alt", false)) else route
	var seg := int(a.seg)
	while seg < rt.size() - 1:
		var p0: Vector2 = rt[seg]
		var p1: Vector2 = rt[seg + 1]
		var ab := p1 - p0
		var t := clampf((a.p - p0).dot(ab) / ab.length_squared(), 0.0, 1.0)
		if t >= 0.98 or (a.p.distance_to(p1) < 2.5 and seg < rt.size() - 2):
			seg += 1
			continue
		a.seg = seg
		var n := Vector2(-ab.y, ab.x).normalized()
		var ahead := p0 + ab * minf(t + 3.0 / ab.length(), 1.0) + n * float(a.lat)
		return (ahead - a.p).normalized()
	a.done = true
	return Vector2.ZERO


## 挡在前面的兵（5.7a）：推倒、踩过（每个兵每 TRAMPLE_GAP 秒最多一次）
func _hit_soldiers(a: Dictionary) -> void:
	for v in victims:
		var s := v as Soldier
		if s == null or not is_instance_valid(s) or not s.fighting():
			continue
		var sp := Vector2(s.global_position.x, s.global_position.z)
		if sp.distance_squared_to(a.p) > SOLDIER_KNOCK * SOLDIER_KNOCK:
			continue
		var last := float(s.get_meta("trampled_t", -99.0))
		if _clock - last < TRAMPLE_GAP:
			continue
		s.set_meta("trampled_t", _clock)
		s.trampled(SOLDIER_TRAMPLE_DMG, SOLDIER_FEAR)
		trampled_soldiers += 1


## 挡在前面的主角：走到 KNOCK_DIST 以内、朝着他走 → 推倒（躺一会儿）、踩一下（伤害、寒冷）
func _hit_player(a: Dictionary, pp: Vector2) -> void:
	var off: Vector2 = pp - a.p
	if off.length() > KNOCK_DIST or a.v.length() < 0.1 or off.normalized().dot(a.v.normalized()) < 0.2:
		return
	if _clock - float(a.last_trample) < TRAMPLE_GAP:
		return
	a.last_trample = _clock
	if not player.knocked():
		player.knock_down(KNOCK_SEC, Vector3(a.v.x, 0, a.v.y))
		knocked.emit()
	_tramples += 1
	if player.melee:
		player.melee.receive_hit({"damage": TRAMPLE_DAMAGE, "kind": "trample", "nonlethal": true})
	GameState.cold = clampf(GameState.cold + TRAMPLE_COLD, 0.0, 100.0)          # 被踩进雪里（STORY.md 5.7：踩过直接加一截寒冷）
	trampled.emit(_tramples)


## 现在有哪些火：[圆心, 半径]——组 light_source 带 radius 元数据的（铁匠炉、火盆、壁炉）、组 crowd_fire 的（5.4b：插在地上的火把）
## 人群走近，插在地上的火把被压得暗下去（2026-11-07）：离最近的人 TORCH_DIM_R 米以内按距离压到 TORCH_DIM_MIN（PlantedTorch.dim，它自己闪的时候乘上）；
## 人群走完了、不在了还原成 1
func _dim_torches() -> void:
	if not is_inside_tree():
		return
	for t in get_tree().get_nodes_in_group("planted_torch"):
		if not (t is PlantedTorch):
			continue
		var tp := (t as Node3D).global_position
		var d := INF
		for a: Dictionary in agents:
			if not a.done:
				d = minf(d, Vector2(tp.x, tp.z).distance_to(a.p))
		(t as PlantedTorch).dim = lerpf(TORCH_DIM_MIN, 1.0, clampf((d - 1.5) / (TORCH_DIM_R - 1.5), 0.0, 1.0))


func _exit_tree() -> void:
	if is_inside_tree():
		for t in get_tree().get_nodes_in_group("planted_torch"):
			if t is PlantedTorch:
				(t as PlantedTorch).dim = 1.0


static func fires(tree: SceneTree) -> Array:
	var out := []
	for g in ["light_source", "crowd_fire"]:
		for l in tree.get_nodes_in_group(g):
			if l is Node3D and l.has_meta("radius") and (l as Node3D).is_visible_in_tree():
				var p := (l as Node3D).global_position
				out.append([Vector2(p.x, p.z), float(l.get_meta("radius")) * FIRE_GAIN])
	return out


## 画：远处的人一个多实例（插值的位置、走路颠一下）；离镜头最近的几个换成真人模型
func _draw(f: float) -> void:
	if mm == null:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var cp := cam.global_position if cam else Vector3.INF
	var order := []
	if not models.is_empty() and cam:
		for i in agents.size():
			var a: Dictionary = agents[i]
			if not a.done and not hidden.has(i):
				var d := Vector2(cp.x, cp.z).distance_squared_to(a.p)
				if d < NEAR_DIST * NEAR_DIST:
					order.append([d, i])
		order.sort_custom(func(x, y): return x[0] < y[0])
	_near_d = INF
	if cam:
		for a: Dictionary in agents:
			if not a.done:
				_near_d = minf(_near_d, Vector2(cp.x, cp.z).distance_to(a.p))
	_dim_torches()
	var near := {}
	for k in mini(order.size(), models.size()):
		near[int(order[k][1])] = k
	var used := {}
	for i in agents.size():
		var a: Dictionary = agents[i]
		var m: MultiMesh = mm.multimesh
		if a.done or hidden.has(i):
			m.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), Vector3(0, -100, 0)))
			if mist:
				mist.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), Vector3(0, -100, 0)))
			continue
		var p: Vector2 = (a.prev as Vector2).lerp(a.p, f)
		var y := float(height_fn.call(p.x, p.y)) if height_fn.is_valid() else 0.0
		if mist:
			mist.multimesh.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(a.phase)), Vector3(p.x, y + 0.35, p.y)))
			mist.multimesh.set_instance_color(i, Color(1, 1, 1, 1))
		var yaw := atan2(a.v.x, a.v.y) if a.v.length() > 0.05 else 0.0
		var bob := absf(sin(float(a.phase))) * 0.04
		if near.has(i):
			var cm: CharacterModel = models[near[i]]
			used[near[i]] = true
			cm.visible = true
			cm.position = Vector3(p.x, y, p.y)
			cm.rotation.y = yaw
			m.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), Vector3(0, -100, 0)))
			continue
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.08)             # 往前倾一点：梦游一样，头先走
		m.set_instance_transform(i, Transform3D(b, Vector3(p.x, y + bob, p.y)))
		var t := float(a.tint)
		m.set_instance_color(i, Color(t, t, t))
	for k in models.size():
		if not used.has(k):
			(models[k] as CharacterModel).visible = false
