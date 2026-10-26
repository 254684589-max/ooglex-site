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
const LINEN := Color("b9b3a6")         # 睡衣：浅色的粗麻
const SKIN := Color("c9a58c")
const LAYER := 2                         # 渲染层 2（火把的光跳过这一层）
const LINEN_TINT := Color(1.85, 2.2, 2.8)   # 真人模型：农夫衣服的贴图是深褐色，乘上去变成浅色的粗麻（各通道按贴图平均色算）

var route: Array = []                  # [Vector2, ...]
var width := 6.0                       # 一股多宽（米）
var speed_base := 0.75
var count := 30
var spawn_gap := 0.7                   # 前后隔多远出来一个（米，沿路线往后排）
var obstacles: Array = []              # [[Vector2 圆心, 半径], ...]
var player: FpController
var height_fn: Callable                # (x, z) -> y；空 = 都在 y = 0
var near_enabled := true               # 测试里可以关掉真人模型（无头测试不加载模型也行）

var agents: Array = []                 # 每个人：{p: Vector2, prev: Vector2, v: Vector2, seg: int, lat: float, sp: float, phase: float, done: bool, last_trample: float, near: int}
var mm: MultiMeshInstance3D
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
	if near_enabled:
		for k in mini(near_max, NEAR_MAX):
			var spec := Looks.spec_of({"preset": "woman" if k % 3 == 1 else "commoner", "hair": [["Hair_Buzzed"], ["Hair_Long"], ["Hair_SimpleParted"]][k % 3],
				"hair_color": ["#3a2a1a", "#6a5a4a", "#9a948a", "#2a2018"][k % 4], "tint": {"MI_Peasant": LINEN_TINT}})
			if spec.is_empty():
				break
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
	for s in [-1.0, 1.0]:
		kit.cylinder("cloth", Vector3(s * 0.09, 0.06, 0.0), Vector3(s * 0.1, 0.84, 0.0), 0.058, 0.08, 8, 0.85)          # 腿（麻布裤）
		kit.cylinder("skin", Vector3(s * 0.09, 0.0, 0.03), Vector3(s * 0.09, 0.07, 0.03), 0.05, 0.055, 6, 0.8)          # 光脚
		kit.cylinder("cloth", Vector3(s * 0.2, 1.4, 0.0), Vector3(s * 0.24, 1.12, 0.03), 0.055, 0.05, 7, 0.9)           # 上臂、小臂（垂着，稍微往前）
		kit.cylinder("cloth", Vector3(s * 0.24, 1.12, 0.03), Vector3(s * 0.25, 0.9, 0.07), 0.048, 0.042, 7, 0.9)
		kit.cylinder("skin", Vector3(s * 0.25, 0.9, 0.07), Vector3(s * 0.25, 0.8, 0.08), 0.04, 0.03, 6, 0.85)           # 手
	kit.cylinder("cloth", Vector3(0, 0.78, 0), Vector3(0, 1.12, 0), 0.17, 0.16, 10, 0.92)                              # 腰到胸：麻衣
	kit.cylinder("cloth", Vector3(0, 1.12, 0), Vector3(0, 1.42, 0), 0.165, 0.2, 10, 1.0)                              # 胸到肩，肩宽一点
	kit.cylinder("cloth", Vector3(0, 1.42, 0), Vector3(0, 1.46, 0), 0.2, 0.08, 10, 1.0)
	kit.cylinder("skin", Vector3(0, 1.44, 0), Vector3(0, 1.53, 0), 0.05, 0.05, 6)                                     # 脖子
	kit.cylinder("skin", Vector3(0, 1.52, 0.01), Vector3(0, 1.6, 0.01), 0.075, 0.095, 9)                              # 头：下巴 → 颧骨 → 头顶，几段圆台拼圆
	kit.cylinder("skin", Vector3(0, 1.6, 0.01), Vector3(0, 1.69, 0.0), 0.095, 0.09, 9)
	kit.cylinder("hair", Vector3(0, 1.66, -0.01), Vector3(0, 1.76, -0.01), 0.1, 0.05, 9)                              # 头发（深色，盖住头顶后脑）
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = LINEN
	cloth.vertex_color_use_as_albedo = true
	cloth.roughness = 0.95
	cloth.emission_enabled = true          # 跟近处的真人模型一样背光处有一点自发光（CharacterModel.GLOW），远近换的时候亮度对得上
	cloth.emission = LINEN
	cloth.emission_energy_multiplier = CharacterModel.GLOW * 3.0   # 近处那份是贴图 × 两倍多的 tint 再发光，这边没贴图，乘 3 才对得上（5.4b 截图对过）
	var skin := StandardMaterial3D.new()
	skin.albedo_color = SKIN
	skin.vertex_color_use_as_albedo = true
	skin.roughness = 0.8
	skin.emission_enabled = true
	skin.emission = SKIN
	skin.emission_energy_multiplier = CharacterModel.GLOW
	var hair := StandardMaterial3D.new()
	hair.albedo_color = Color("3a2e24")
	hair.vertex_color_use_as_albedo = true
	hair.roughness = 0.9
	var mi := kit.build({"cloth": cloth, "skin": skin, "hair": hair})
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
		if int(a.detour) != 0 and int(a.seg) < route.size() - 1:
			want = ((route[int(a.seg) + 1] as Vector2) - (route[int(a.seg)] as Vector2)).normalized()   # 正在绕火：只朝路线的方向，不往路线中间拉（不然在一排火把前面横向拉扯、停住）
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
		for f in _fires + obstacles:
			var c: Vector2 = f[0]
			var r := float(f[1])
			var off: Vector2 = a.p - c
			var d := off.length()
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
	if not _done_sent and alive() == 0:
		_done_sent = true
		finished.emit()


## 往路线前方哪个方向走：投到当前这一段上，往前看 3 米，再加上自己在路线左右的偏移；最后一段走完 = done
func _route_dir(a: Dictionary) -> Vector2:
	var seg := int(a.seg)
	while seg < route.size() - 1:
		var p0: Vector2 = route[seg]
		var p1: Vector2 = route[seg + 1]
		var ab := p1 - p0
		var t := clampf((a.p - p0).dot(ab) / ab.length_squared(), 0.0, 1.0)
		if t >= 0.98 or (a.p.distance_to(p1) < 2.5 and seg < route.size() - 2):
			seg += 1
			continue
		a.seg = seg
		var n := Vector2(-ab.y, ab.x).normalized()
		var ahead := p0 + ab * minf(t + 3.0 / ab.length(), 1.0) + n * float(a.lat)
		return (ahead - a.p).normalized()
	a.done = true
	return Vector2.ZERO


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
			if not a.done:
				var d := Vector2(cp.x, cp.z).distance_squared_to(a.p)
				if d < NEAR_DIST * NEAR_DIST:
					order.append([d, i])
		order.sort_custom(func(x, y): return x[0] < y[0])
	var near := {}
	for k in mini(order.size(), models.size()):
		near[int(order[k][1])] = k
	var used := {}
	for i in agents.size():
		var a: Dictionary = agents[i]
		var m: MultiMesh = mm.multimesh
		if a.done:
			m.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), Vector3(0, -100, 0)))
			continue
		var p: Vector2 = (a.prev as Vector2).lerp(a.p, f)
		var y := float(height_fn.call(p.x, p.y)) if height_fn.is_valid() else 0.0
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
