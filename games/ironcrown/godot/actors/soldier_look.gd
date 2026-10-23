class_name SoldierLook
extends Node3D
## 军阵士兵的真人外观（路线图 B.6；ART.md 7.1「兵装搭配」）：A.2 的服装包（Quaternius，CC0）按兵种挑打扮——
## 民兵穿平民的衣服，剑兵、盾兵、长枪兵穿游侠那套（兜帽摘了），弓手戴着兜帽，队长是佣兵那套；外衣按阵营的罩袍色染一遍，
## 胸前斜挎一条阵营布带（白 / 黑），一部分人戴一顶铁盔（代码搭的），头发、胡子、发色按兵的编号随机；手里拿剑、棍、长枪或弓，盾兵左手一面圆盾（布带颜色），
## 队长背上插一面小旗。数据在 data/looks.json 的 soldiers 一节。
## 只给离镜头最近的 MAX_NEAR 个兵（MODEL_FAR 米以内）画模型，其余还是 B.5 合并好的占位胶囊（Battle 每 0.25 秒排一次：budget()）；
## 不画模型的兵模型藏起来、动作停下。第一版按距离各自交接（visibility range），60 人时观战台上看绘制调用 1033 / 1246、逻辑 64–79 毫秒，超了预算 400。
## 动作跟着兵的状态走（_process）：站着持剑、走、跑、出招（按起手 + 半个出招的时间对准命中）、格挡、挨打、踉跄、倒下、跪地求饶、逃跑；
## 长枪兵出招用冲刺突刺（Sword_Dash）；弓手左手拿弓、平时普通站姿，拉弓时用骨骼修改器把两条胳膊摆成拉弓的样子（BowAim，B.6b）。
## B.6b：军阵以外的敌人（营地、渡口、哨卡的无旗者，失守后庭院里巡的人）也用它，人少一直画真人；对峙说崩了变成敌人的，按那个人的名字穿同一身。

const MODEL_FAR := 22.0
const FADE := 3.0                 # （留给以后按距离渐变用）
const MAX_NEAR := 16              # 同时画真人模型的兵最多几个。B.6a 每人约 15 次绘制调用，8 个（60 人基准低 / 中 325–335 / 370–397）；B.6b 合并网格后每人约 8 次，翻倍到 16 个
const BONE := "spine_03"

var soldier: Enemy               # 兵（Soldier）或者军阵以外的敌人（B.6b：营地、渡口、哨卡的无旗者，失守后庭院里巡的人）
var model: CharacterModel
var seed_i := 0
var rng := RandomNumberGenerator.new()     # 按兵的编号定种子：每次进来同一个兵长得一样（编号的字符串哈希是挨着的，直接取模几乎都一样，B.6 实测）
var _last_hp := -1
var _hit_left := 0.0
var _act := ""
var bow: BowAim                   # 弓手拉弓的姿势（B.6b）
var merged: MeshInstance3D        # 合成一块的蒙皮网格（B.6b；合不了为空）
static var merge_on := true       # 测试比较用：关掉就不合（代码搭的东西照样压成一份）


## 给兵 s 搭外观；data/looks.json 没有 soldiers 这一节、或者这个兵种没配时返回 null（还是胶囊）
static func dress(s: Enemy) -> SoldierLook:
	var cfg: Dictionary = Looks.data().get("soldiers", {})
	var kinds: Dictionary = cfg.get("kinds", {})
	if not kinds.has(s.kind) and not Looks.has(s.display_override):
		return null
	var sl := SoldierLook.new()
	sl.name = "SoldierLook"
	sl.soldier = s
	sl.seed_i = absi(hash(s.enemy_id))
	sl.rng.seed = hash("soldier_look:" + s.enemy_id)
	s.add_child(sl)
	sl._build(cfg)
	return sl if sl.model != null else null


func _pick(arr: Array) -> Variant:
	return arr[rng.randi_range(0, arr.size() - 1)] if not arr.is_empty() else null


func _build(cfg: Dictionary) -> void:
	var spec: Dictionary
	if Looks.has(soldier.display_override):
		spec = Looks.spec(soldier.display_override)              # 从说过话的人变成的敌人（对峙说崩了）：还是那个人的样子（B.6b）
	else:
		var presets: Array = cfg.kinds[soldier.kind]
		var p := {"preset": str(_pick(presets)), "hair": _pick(cfg.get("hair", [["Hair_Buzzed"]])), "hair_color": str(_pick(cfg.get("hair_colors", ["#3a2a1a"])))}
		if soldier is Soldier:
			var c := (soldier as Soldier).coat_color.lightened(0.45)      # 罩袍色偏暗：提亮了再乘，衣服才看得出是哪一边（第一版 0.35 / 0.6 两边分不清）
			var tint := Color.WHITE.lerp(c, float(cfg.get("tint_mix", 0.6)))
			p["tint"] = {"MI_Ranger": "#" + tint.to_html(false), "MI_Peasant": "#" + tint.to_html(false)}
		spec = Looks.spec_of(p)
	var m := CharacterModel.new()
	m.name = "Look"
	m.parts = spec.parts
	m.look = spec.look
	m.set_meta("hide", spec.hide)
	m.rotation.y = PI                          # 模型面朝 +Z，兵的脸朝本地 -Z
	var h := rng.randf_range(0.95, 1.05)                         # 高矮差一点
	m.scale = Vector3(h, h, h)
	add_child(m)
	if not m.loaded:
		m.queue_free()
		return
	model = m
	Looks.hide_parts(m)
	for mi: MeshInstance3D in m.scene_root.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var weapon := str(soldier.data.get("weapon", "sword"))
	var prop := Props.make({"club": "club", "spear": "spear", "bow": "bow"}.get(weapon, "sword"))
	m.hold_prop(prop, weapon == "bow")                 # 弓拿在左手
	if weapon == "bow":
		bow = BowAim.new()
		bow.name = "BowAim"
		bow.influence = 0.0
		m.skeleton.add_child(bow)
	var sol := soldier as Soldier
	if sol and sol.kind == "shield":
		m.hold_prop(Props.make_shield(sol.band_color), true)
	var helm_share: float = float(cfg.get("helmet", {}).get(soldier.kind, 0.0))
	if sol:
		_body_gear(sol.band_color, rng.randf() < helm_share, sol.is_captain)       # 布带、铁盔、队长的小旗只有军阵的兵有
	_merge()
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.play_loop("idle_armed", 1.0, 0.0)
	m.anim.seek(rng.randf(), true)                      # 起点错开
	m.set_anim_every(2)
	set_near(false)                                   # 先画胶囊，Battle 排过以后近的才换成真人


## 少画几次（B.6b）：代码搭的东西（布带、铁盔、兵器、盾）各自压成一份顶点色网格；衣服、头、头发、胡子合成一块蒙皮网格（SkinMerge）
func _merge() -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null and mi.mesh != null and mi.mesh.get_surface_count() > 1:
			mi.mesh = MeshKit.flatten([mi], mi)
			mi.material_override = MeshKit.flat_mat(0.7)
	if merge_on:
		merged = SkinMerge.merge(model.skeleton)


## 这个人一共画几次（网格 × 表面；藏起来的不算）：测试、调预算用
func draw_surfaces() -> int:
	var n := 0
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh != null and mi.is_visible_in_tree():
			n += mi.mesh.get_surface_count()
	return n


## 画真人还是画胶囊
func set_near(on: bool) -> void:
	if model == null:
		return
	model.visible = on
	model.set_process(on)
	var sol := soldier as Soldier
	if sol and sol.look:
		sol.look.visible = not on
	elif not sol and soldier.body:
		soldier.body.visible = not on                   # 军阵以外的敌人：占位身子（没合并）整个藏起来
	if soldier.arm and soldier.arm.get_child_count() > 0:
		(soldier.arm.get_child(0) as Node3D).visible = not on


func is_near() -> bool:
	return model != null and model.visible


## 军阵每 0.25 秒排一次：离镜头最近、MODEL_FAR 以内的 MAX_NEAR 个兵画真人（倒下、跪下的也算：近处看得见），其余画胶囊
static func budget(soldiers: Array, cam: Camera3D) -> int:
	if cam == null:
		return 0
	var cp := cam.global_position
	var cand := []
	for s in soldiers:
		if is_instance_valid(s) and s.dressed != null and s.is_inside_tree():
			cand.append([s.global_position.distance_squared_to(cp), s])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	var n := 0
	for i in cand.size():
		var on: bool = n < MAX_NEAR and float(cand[i][0]) <= MODEL_FAR * MODEL_FAR
		if on:
			n += 1
		var sl: SoldierLook = cand[i][1].dressed
		if sl.is_near() != on:
			sl.set_near(on)
	return n


## 身上的东西（挂在 spine_03 / 头上，按 T 姿势的骨架空间摆，同 actors/gear.gd）：阵营布带、铁盔、队长的小旗
func _body_gear(band: Color, helmet: bool, pennant: bool) -> void:
	var sk := model.skeleton
	var kit := MeshKit.new()
	for pts in [[Vector3(-0.16, 1.53, 0.05), Vector3(0.0, 1.30, 0.17), Vector3(0.18, 1.02, 0.14)], [Vector3(-0.16, 1.53, -0.06), Vector3(0.0, 1.28, -0.165), Vector3(0.18, 1.02, -0.13)]]:
		for i in 2:
			_bar(kit, "band", pts[i], pts[i + 1], 0.07, 0.014)
	if pennant:
		kit.cylinder("pole", Vector3(-0.08, 1.05, -0.2), Vector3(-0.08, 2.25, -0.2), 0.012, 0.012, 5)
		kit.box("band", Vector3(-0.08 - 0.17, 2.08, -0.2), Vector3(0.32, 0.26, 0.012), Basis.IDENTITY)
	_attach(sk, BONE, kit.build({"band": _mat(band, 0.9), "pole": _mat(Color("4a3a28"), 0.8)}))
	if helmet:
		var hk := MeshKit.new()
		hk.cylinder("iron", Vector3(0, 1.70, 0.02), Vector3(0, 1.86, 0.02), 0.142, 0.07, 10)
		hk.cylinder("iron", Vector3(0, 1.69, 0.02), Vector3(0, 1.715, 0.02), 0.21, 0.205, 12)        # 帽檐（圆筒没有封口：从下往上看是一圈，正好）
		_attach(sk, "Head", hk.build({"iron": _mat(Color("5a5c60"), 0.45, 0.45)}))


func _attach(sk: Skeleton3D, bone: String, node: Node3D) -> void:
	var idx := sk.find_bone(bone)
	if idx < 0:
		node.free()
		return
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	sk.add_child(ba)
	var holder := Node3D.new()
	ba.add_child(holder)
	holder.transform = sk.get_bone_global_rest(idx).affine_inverse()
	holder.add_child(node)


func _bar(kit: MeshKit, mat: String, a: Vector3, b: Vector3, w: float, t: float) -> void:
	var y := b - a
	var up := y / y.length()
	var z := Vector3(0, 0, 1) - up * up.z
	z = z.normalized()
	kit.box(mat, (a + b) * 0.5, Vector3(w, y.length(), t), Basis(up.cross(z), up, z))


func _mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.vertex_color_use_as_albedo = true
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = CharacterModel.GLOW
	return m


## 动作跟着兵的状态走；远处（画的是胶囊）不推进
func _process(delta: float) -> void:
	if model == null or soldier == null or not model.visible:
		return
	var s := soldier
	if _last_hp >= 0 and s.hp < _last_hp and s.state not in [Enemy.State.DEAD, Enemy.State.STAGGER]:
		_hit_left = 0.35
		model.play_once("hit", 1.4, 0.05)
	_last_hp = s.hp
	match s.state:
		Enemy.State.DEAD:
			if model.role != "death":
				model.play_once("death", 1.0, 0.12)
			return
		Enemy.State.YIELD:
			if model.role != "kneel_fix":
				model.play_loop("kneel_fix", 0.4, 0.3)        # 跪在地上
			return
		Enemy.State.STAGGER:
			if model.role != "stagger":
				model.play_once("stagger", 1.0, 0.06)
			return
	if _hit_left > 0.0:
		_hit_left -= delta
		return
	if s.action != _act:
		_act = s.action
		match _act:
			"windup":
				_swing()
			"block":
				model.play_once("block", 1.3, 0.08)
	if bow:
		var drawing := s.action in ["draw", "loose"]
		bow.influence = move_toward(bow.influence, 1.0 if drawing else 0.0, delta * (5.0 if drawing else 3.0))      # 拉弓时两条胳膊抬起来（B.6b）
	if s.action in ["windup", "strike", "recover"]:
		return
	if s.action == "block":
		var hold_at := float(model.map.block.hold)
		if model.anim.current_animation_position >= hold_at and model.anim.get_playing_speed() != 0.0:
			model.hold("block", hold_at, 0.0)
		return
	var speed := Vector2(s.velocity.x, s.velocity.z).length()
	var in_battle: bool = s is Soldier and (s as Soldier).battle != null
	var pick := CharacterModel.pick_locomotion(model.map, speed, false, bow == null and (s.state != Enemy.State.PATROL or in_battle))     # 弓手站着不拿剑的架势
	model.play_loop(str(pick.role), float(pick.scale), 0.2)


## 出招：起手 + 半个出招的时间后命中（Enemy 的命中帧），动作的命中时刻对上它；长枪用冲刺突刺
func _swing() -> void:
	var s := soldier
	var to_hit := float(s.data.heavy_windup if s.attack_kind == "heavy" else s.data.windup) + float(s.data.strike) * 0.5
	var atk: Dictionary = model.map.attacks
	var a: Dictionary
	if str(s.data.get("weapon", "")) == "spear":
		a = atk.dash
	elif s.attack_kind == "heavy":
		a = atk.heavy
	else:
		a = (atk.light as Array)[(seed_i + s.hp) % 2]
	model.play_once(str(a.clip), float(a.impact) / maxf(to_hit, 0.05), 0.06)
