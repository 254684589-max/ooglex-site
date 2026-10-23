class_name SoldierLook
extends Node3D
## 军阵士兵的真人外观（路线图 B.6；ART.md 7.1「兵装搭配」）：A.2 的服装包（Quaternius，CC0）按兵种挑打扮——
## 民兵穿平民的衣服，剑兵、盾兵、长枪兵穿游侠那套（兜帽摘了），弓手戴着兜帽，队长是佣兵那套；外衣按阵营的罩袍色染一遍，
## 胸前斜挎一条阵营布带（白 / 黑），一部分人戴一顶铁盔（代码搭的），头发、胡子、发色按兵的编号随机；手里拿剑、棍、长枪或弓，盾兵左手一面圆盾（布带颜色），
## 队长背上插一面小旗。数据在 data/looks.json 的 soldiers 一节。
## 只在近处画模型（MODEL_FAR 米以内）；远处还是 B.5 合并好的占位胶囊（visibility range 交接）。模型远了动作停下（和 NPC 一样）。
## 动作跟着兵的状态走（_process）：站着持剑、走、跑、出招（按起手 + 半个出招的时间对准命中）、格挡、挨打、踉跄、倒下、跪地求饶、逃跑；
## 长枪兵出招用冲刺突刺（Sword_Dash），弓手拉弓时举着弓站定（没有拉弓的动作素材，B.6b 再看）。

const MODEL_FAR := 22.0
const FADE := 3.0                 # 模型和胶囊交接的过渡（米）
const BONE := "spine_03"

var soldier: Soldier
var model: CharacterModel
var seed_i := 0
var _last_hp := -1
var _hit_left := 0.0
var _act := ""


## 给兵 s 搭外观；data/looks.json 没有 soldiers 这一节、或者这个兵种没配时返回 null（还是胶囊）
static func dress(s: Soldier) -> SoldierLook:
	var cfg: Dictionary = Looks.data().get("soldiers", {})
	var kinds: Dictionary = cfg.get("kinds", {})
	if not kinds.has(s.kind):
		return null
	var sl := SoldierLook.new()
	sl.name = "SoldierLook"
	sl.soldier = s
	sl.seed_i = absi(hash(s.enemy_id))
	s.add_child(sl)
	sl._build(cfg)
	return sl if sl.model != null else null


func _pick(arr: Array, salt: int) -> Variant:
	return arr[(seed_i / maxi(salt, 1)) % arr.size()] if not arr.is_empty() else null


func _build(cfg: Dictionary) -> void:
	var presets: Array = cfg.kinds[soldier.kind]
	var p := {"preset": str(_pick(presets, 1)), "hair": _pick(cfg.get("hair", [["Hair_Buzzed"]]), 3), "hair_color": str(_pick(cfg.get("hair_colors", ["#3a2a1a"]), 7))}
	var c := soldier.coat_color.lightened(0.35)
	var tint := Color.WHITE.lerp(c, float(cfg.get("tint_mix", 0.6)))
	p["tint"] = {"MI_Ranger": "#" + tint.to_html(false), "MI_Peasant": "#" + tint.to_html(false)}
	var spec := Looks.spec_of(p)
	var m := CharacterModel.new()
	m.name = "Look"
	m.parts = spec.parts
	m.look = spec.look
	m.set_meta("hide", spec.hide)
	m.rotation.y = PI                          # 模型面朝 +Z，兵的脸朝本地 -Z
	var h := 0.95 + float((seed_i / 11) % 11) * 0.01           # 高矮差一点（0.95–1.05）
	m.scale = Vector3(h, h, h)
	add_child(m)
	if not m.loaded:
		m.queue_free()
		return
	model = m
	Looks.hide_parts(m)
	for mi: MeshInstance3D in m.scene_root.find_children("*", "MeshInstance3D", true, false):
		mi.visibility_range_end = MODEL_FAR
		mi.visibility_range_end_margin = FADE
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var weapon := str(soldier.data.get("weapon", "sword"))
	var prop := Props.make({"club": "club", "spear": "spear", "bow": "bow"}.get(weapon, "sword"))
	m.hold_prop(prop)
	if soldier.kind == "shield":
		m.hold_prop(Props.make_shield(soldier.band_color), true)
	var helm_share: float = float(cfg.get("helmet", {}).get(soldier.kind, 0.0))
	_body_gear(soldier.band_color, float((seed_i / 13) % 100) / 100.0 < helm_share, soldier.is_captain)
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if mi.visibility_range_end == 0.0:
			mi.visibility_range_end = MODEL_FAR
			mi.visibility_range_end_margin = FADE
	m.play_loop("idle_armed", 1.0, 0.0)
	m.anim.seek(float(seed_i % 100) / 100.0, true)      # 起点错开
	m.set_anim_every(2)


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
	if model == null or soldier == null:
		return
	var cam := get_viewport().get_camera_3d()
	var near := cam == null or cam.global_position.distance_to(global_position) < MODEL_FAR + FADE
	if model.is_processing() != near:
		model.set_process(near)
	if not near:
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
	if s.action in ["windup", "strike", "recover"]:
		return
	if s.action == "block":
		var hold_at := float(model.map.block.hold)
		if model.anim.current_animation_position >= hold_at and model.anim.get_playing_speed() != 0.0:
			model.hold("block", hold_at, 0.0)
		return
	var speed := Vector2(s.velocity.x, s.velocity.z).length()
	var pick := CharacterModel.pick_locomotion(model.map, speed, false, s.state != Enemy.State.PATROL or s.battle != null)
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
