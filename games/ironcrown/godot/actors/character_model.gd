class_name CharacterModel
extends Node3D
## 人物模型与动作（路线图 A.1，D4 = B）：Quaternius Universal Base Characters 的男性底模（CC0）+ Universal Animation Library 的动作（CC0）。
## 模型和动作用同一套 65 根骨头的骨架，动作不用重定向。动作与「角色」（站、走、跑、出招……）的对应写在 data/character_anims.json；
## 动画库由 tools/build_character_anims.gd 从原包里挑出用到的动作打成 assets/characters/anims/ual_core.res。
## glTF 里人物面朝 +Z（游戏里的「向前」是 -Z），所以挂到别的节点下时要转 180°（PlayerAvatar 里做）。
## 节点都是代码建的：玩家、NPC 与敌人以后（A.2）都能用这个类，换装只换模型。

const MODEL := "res://assets/characters/Superhero_Male_FullBody.gltf"
const ANIMS := "res://assets/characters/anims/ual_core.res"
const MAP := "res://data/character_anims.json"
const HAND_BONE := "hand_r"
## 皮肤在背光处不要变成黑影：加一点点自发光（和 2.9 起占位人形、武器同一个办法）
const GLOW := 0.16

var map: Dictionary = {}
var scene_root: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var hand: BoneAttachment3D        # 右手骨骼：拿东西挂在它的子节点 grip 下
var grip: Node3D
var role := ""                    # 现在在演哪个「角色」（站 / 走 / 跑 / 出招……），测试与调试用
var loaded := false
var _reverse := false
var anim_every := 1               # 每几帧推进一次动作（B.5：军阵里离镜头远的兵 2；1 = 每帧，引擎自己推进）
var _anim_frames := 0
var _anim_dt := 0.0


func _ready() -> void:
	map = load_map()
	var packed := ResourceLoader.load(MODEL) as PackedScene
	var lib := ResourceLoader.load(ANIMS) as AnimationLibrary
	if packed == null or lib == null or map.is_empty():
		push_warning("人物模型或动作库没有加载成功（%s）" % MODEL)
		return
	scene_root = packed.instantiate() as Node3D
	scene_root.name = "Model"
	add_child(scene_root)
	var skels := scene_root.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		push_warning("人物模型里没有骨架")
		return
	skeleton = skels[0]
	_glow_materials()
	anim = AnimationPlayer.new()
	anim.name = "Anim"
	add_child(anim)
	anim.root_node = anim.get_path_to(scene_root)
	anim.add_animation_library("", lib)
	hand = BoneAttachment3D.new()
	hand.name = "HandR"
	hand.bone_name = HAND_BONE
	skeleton.add_child(hand)
	grip = Node3D.new()
	grip.name = "Grip"
	hand.add_child(grip)
	var g: Dictionary = map.get("grip", {})
	var gp: Array = g.get("position", [0, 0, 0])
	var gr: Array = g.get("rotation_deg", [0, 0, 0])
	grip.position = Vector3(gp[0], gp[1], gp[2])
	grip.rotation_degrees = Vector3(gr[0], gr[1], gr[2])
	loaded = true


## data/character_anims.json（每次读一遍；不用 static 缓存，测试退出时脚本才释放得干净）
static func load_map() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP))
	return parsed if parsed is Dictionary else {}


## 站 / 走 / 跑 / 蹲走里选哪一个、播多快（纯函数）。speed 是水平移动速度（米 / 秒）。
static func pick_locomotion(m: Dictionary, speed: float, crouching: bool, armed: bool) -> Dictionary:
	var loco: Dictionary = m.locomotion
	if speed < float(loco.stop_below):
		return {"role": "crouch_idle" if crouching else ("idle_armed" if armed else "idle"), "scale": 1.0}
	var r := "crouch_move" if crouching else ("run" if speed >= float(loco.run_from) else "walk")
	var c: Dictionary = loco[r]
	return {"role": r, "scale": clampf(speed / float(c.ref_speed), float(c.scale_min), float(c.scale_max))}


## 轻击第 combo 段用哪个动作（只有两个，第三段回到第一个）：{clip, impact}。
## moves = 整张映射（用持剑的 attacks）或者直接传 attacks / fists 一组（3.3 空手出拳）
static func light_attack(moves: Dictionary, combo: int) -> Dictionary:
	var list: Array = moves.attacks.light if moves.has("attacks") else moves.light
	return list[combo % list.size()]


## 角色名 → 动作名（也可以直接传动作名）
## 动作降频（B.5，军阵 60 人）：n > 1 时改成手动推进，每 n 帧把攒下的时间一次推进（骨骼姿势也每 n 帧算一次）
func set_anim_every(n: int) -> void:
	n = maxi(n, 1)
	if n == anim_every or anim == null:
		return
	anim_every = n
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE if n == 1 else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if n == 1 and _anim_dt > 0.0:
		anim.advance(_anim_dt)
	_anim_frames = 0
	_anim_dt = 0.0
	set_process(n > 1)


func _process(delta: float) -> void:
	if anim_every <= 1 or anim == null:
		set_process(false)
		return
	_anim_dt += delta
	_anim_frames += 1
	if _anim_frames >= anim_every:
		anim.advance(_anim_dt)
		_anim_frames = 0
		_anim_dt = 0.0


func clip(r: String) -> String:
	return str(map.get("roles", {}).get(r, r))


## 循环动作（站、走、跑、蹲……）：同一个动作在播就只改速度，不重来；reverse = 倒放（倒着走）
func play_loop(r: String, speed := 1.0, blend := 0.18, reverse := false) -> void:
	if not loaded:
		return
	var n := clip(r)
	if anim.current_animation != n or _reverse != reverse or not anim.is_playing() or anim.get_playing_speed() == 0.0:
		anim.play(n, blend, -1.0 if reverse else 1.0, reverse)
	anim.speed_scale = maxf(speed, 0.01)
	_reverse = reverse
	role = r


## 一次性的动作（出招、挨打、倒下）：从 from 秒开始播，speed 倍速
func play_once(r: String, speed := 1.0, blend := 0.08, from := 0.0) -> void:
	if not loaded:
		return
	anim.speed_scale = 1.0
	anim.play(clip(r), blend, speed)
	if from > 0.0:
		anim.seek(from, true)
	_reverse = false
	role = r


## 停在动作的某一刻（蓄力时把挥剑的起手推到最高、举盾格挡时停在举起的那一帧）
func hold(r: String, at: float, blend := 0.1) -> void:
	if not loaded:
		return
	var n := clip(r)
	if anim.current_animation != n or anim.get_playing_speed() != 0.0:
		anim.speed_scale = 1.0
		anim.play(n, blend, 0.0)
	anim.seek(at, true)
	_reverse = false
	role = r


func playing() -> String:
	return anim.current_animation if loaded else ""


func finished() -> bool:
	return loaded and not anim.is_playing()


func clip_length(r: String) -> float:
	return anim.get_animation(clip(r)).length if loaded else 0.0


## 导入的材质是共享资源：复制一份再改（背面剔除、背光时的自发光）
func _glow_materials() -> void:
	for mi: MeshInstance3D in scene_root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var src := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if src == null:
				continue
			var mat := src.duplicate() as StandardMaterial3D
			mat.cull_mode = BaseMaterial3D.CULL_BACK if mat.albedo_texture != null else BaseMaterial3D.CULL_DISABLED
			mat.emission_enabled = true
			if mat.albedo_texture != null:
				mat.emission = Color.WHITE
				mat.emission_texture = mat.albedo_texture
			else:
				mat.emission = mat.albedo_color
			mat.emission_energy_multiplier = GLOW
			mi.set_surface_override_material(s, mat)
