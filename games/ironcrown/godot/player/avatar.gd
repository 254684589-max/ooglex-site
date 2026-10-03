class_name PlayerAvatar
extends Node3D
## 第三人称时看到的主角（路线图 2.9；决定 D6）。A.1 起不再是占位胶囊人：用 CharacterModel（Quaternius 男性底模 + 动作库，D4 = B）。
## 第一人称时隐藏（第一人称只显示手里的武器）。动作跟着 Melee 的状态与玩家的移动走：
## 站 / 走 / 跑 / 蹲 / 空中 / 拔剑后的持剑待机 / 轻击 / 重击（蓄力时把起手推到最高）/ 格挡 / 失衡 / 受击 / 倒下。
## 动作与近战判定的时间对齐见 data/character_anims.json 的 attacks（命中帧 = 动作里剑最靠前的那一刻）。
## 动作库里只有朝前走、跑、蹲走：侧着走、倒着走时把身体转向移动方向（超过 REVERSE_FROM 度就倒着播放前进动作）。
## 模型在第一次显示时才加载（不开第三人称的人不付这笔加载和显存的钱）。
## 3.3 空手（Melee.unarmed()）：手里不挂剑；举拳待机是护脸的架势，出拳 / 重拳 / 格挡换成 character_anims.json 的 fists 一组动作。

const TURN_SPEED := 10.0          # 身体朝向跟上移动方向的快慢（每秒）
const REVERSE_FROM := 100.0       # 移动方向与镜头方向夹角超过这么多度：倒着走
const CHARGE_DELAY := 0.1         # 按住这么久才开始抬剑蓄力（点一下出轻击时不闪一下重击的起手）
const HIT_TIME := 0.33            # 挨打动作的时长
const AIR_DELAY := 0.12           # 离地这么久才算腾空（下台阶、坡面颠簸不切动作）
const HOLD_BLEND := 0.12

var player: FpController
var character: CharacterModel
var weapon_mesh: MeshInstance3D
var model := ""
var face_deg := 0.0               # 身体相对镜头方向的偏转（度，右为正）：斜走、侧着走时腿朝移动方向
var reversed := false             # 正在倒着走（动作倒放）
var _state := -1
var _last_role := ""
var _hit_left := 0.0
var _air_time := 0.0


func _ready() -> void:
	visible = false
	visibility_changed.connect(_on_visibility_changed)
	player.melee.swung.connect(_on_swung)
	player.melee.damaged.connect(_on_damaged)
	player.melee.defeated.connect(_on_defeated)


## 第一次显示时建人物（模型 + 动作库），挂上手里的武器
func _ensure_character() -> void:
	if character != null:
		return
	character = CharacterModel.new()
	character.name = "Character"
	character.rotation.y = PI          # 模型面朝 +Z，游戏里向前是 -Z
	add_child(character)
	_state = -1
	print("IC_AVATAR loaded=%s" % character.loaded)     # 网页冒烟测试读它


func _on_visibility_changed() -> void:
	if visible:
		_ensure_character()
	if character != null and character.loaded:
		character.anim.active = visible


func _set_model(m: String) -> void:
	if m == model and weapon_mesh != null:
		return
	model = m
	if weapon_mesh:
		weapon_mesh.get_parent().remove_child(weapon_mesh)
		weapon_mesh.queue_free()
	var kit := MeshKit.new()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("b4bcc6")
	steel.metallic = 0.35
	steel.roughness = 0.4
	steel.vertex_color_use_as_albedo = true
	if m == "club":
		kit.cylinder("wood", Vector3(0, -0.05, 0), Vector3(0, 0.62, 0), 0.026, 0.045, 6)
	else:
		kit.box("steel", Vector3(0, 0.42, 0), Vector3(0.045, 0.62, 0.01))
		kit.box("wood", Vector3(0, 0.08, 0), Vector3(0.18, 0.025, 0.03))
		kit.box("wood", Vector3(0, -0.01, 0), Vector3(0.032, 0.16, 0.032))
	weapon_mesh = kit.build({"steel": steel, "wood": Look.mat("timber")})
	character.grip.add_child(weapon_mesh)


func _process(delta: float) -> void:
	if not visible or player == null:
		return
	_ensure_character()
	if not character.loaded:
		return
	var m := player.melee
	_set_model(str(m.weapon().get("model", "sword")))
	weapon_mesh.visible = m.state != Melee.State.SHEATHED and not m.unarmed()
	_update_facing(delta)
	_update_anim(delta)
	if character.role != _last_role:
		_last_role = character.role
		print("IC_AVATAR role=%s clip=%s" % [_last_role, character.playing()])


## 身体朝向：不动或出招时正对镜头方向；走动时（斜走、侧走、倒着走）腿朝移动方向，不然动作库里只有朝前走的动作会像滑步
func _update_facing(delta: float) -> void:
	var v := player.velocity
	var local := player.global_transform.basis.inverse() * Vector3(v.x, 0.0, v.z)
	var want := 0.0
	reversed = false
	if Vector2(local.x, local.z).length() > 0.3 and not player.melee.busy():
		var ang := rad_to_deg(atan2(local.x, -local.z))     # 相对「向前」的夹角，右为正
		if absf(ang) > REVERSE_FROM:
			ang -= signf(ang) * 180.0                        # 倒着走：身体朝相反方向，前进动作倒放
			reversed = true
		want = ang
	face_deg = rad_to_deg(lerp_angle(deg_to_rad(face_deg), deg_to_rad(want), clampf(delta * TURN_SPEED, 0.0, 1.0)))
	character.rotation.y = PI - deg_to_rad(face_deg)


func _update_anim(delta: float) -> void:
	var m := player.melee
	var st: int = m.state
	var changed := st != _state
	_state = st
	_hit_left = maxf(_hit_left - delta, 0.0)
	if m.down:
		if character.role != "death":
			character.play_once("death", 1.0, 0.15)
		return
	if m.staggered():
		if character.role != "stagger":
			character.play_once("stagger", 1.0, 0.06)
		return
	if _hit_left > 0.0 and not m.busy():
		return                                                # 挨打的动作还没播完
	var fists := m.unarmed()
	var fm: Dictionary = character.map.get("fists", {})
	match st:
		Melee.State.BLOCK:
			if fists:
				character.hold("block_fists", float(fm.block_at), 0.1)     # 小臂横在胸前，停住直到松开
				return
			var hold_at := float(character.map.block.hold)
			if changed or character.role != "block":
				character.play_once("block", 1.3, 0.08)
			elif character.anim.current_animation_position >= hold_at and character.anim.get_playing_speed() != 0.0:
				character.hold("block", hold_at, 0.0)       # 举起来就停住，直到松开
			return
		Melee.State.CHARGE:
			if m.held > CHARGE_DELAY:
				var a: Dictionary = fm.heavy if fists else character.map.attacks.heavy
				var k := clampf((m.held - CHARGE_DELAY) / (Melee.HEAVY_HOLD - CHARGE_DELAY), 0.0, 1.0)
				character.hold(str(a.clip), float(a.wind_peak) * k, HOLD_BLEND)
				return
		Melee.State.WINDUP, Melee.State.STRIKE:
			return                                              # 出招动作是 _on_swung 里开始的，播它的
		Melee.State.RECOVER:
			if changed:
				if fists:
					character.hold("idle_fists", float(fm.idle_at), 0.25)     # 收拳：回到护脸的架势
				else:
					character.play_loop("idle_armed", 1.0, 0.25)   # 收招：缓缓回到持剑待机
			return
	var armed := st != Melee.State.SHEATHED
	var hspeed := Vector2(player.velocity.x, player.velocity.z).length()
	_air_time = 0.0 if player.is_on_floor() else _air_time + delta
	if _air_time > AIR_DELAY:
		character.play_loop("air", 1.0, 0.12)
		return
	var pick := CharacterModel.pick_locomotion(character.map, hspeed, player.crouching, armed)
	if pick.role == "idle_armed" and fists:
		if character.role != "idle_fists":
			character.hold("idle_fists", float(fm.idle_at), 0.18)          # 举着拳头站着：护脸的架势
		return
	character.play_loop(str(pick.role), float(pick.scale), 0.18, reversed and pick.role in ["walk", "run", "crouch_move"])


## 出招：把动作的命中时刻对到近战判定的命中帧（Melee.TIMING）；体力不够出招变慢时一起变慢
func _on_swung(kind: String) -> void:
	if not visible or character == null or not character.loaded:
		return
	var m := player.melee
	var tm: Dictionary = Melee.TIMING[kind]
	var moves: Dictionary = character.map.fists if m.unarmed() else character.map.attacks     # 空手出拳（3.3）
	var to_hit: float
	if kind == "heavy":
		var a: Dictionary = moves.heavy
		to_hit = float(tm.strike) * float(tm.hit_at) / m.speed
		var from_t := float(a.wind_peak)                      # 蓄力已经把剑推到最高处，从那里劈下
		character.play_once(str(a.clip), (float(a.impact) - from_t) / to_hit, 0.04, from_t)
	else:
		var a := CharacterModel.light_attack(moves, m.combo)
		to_hit = (float(tm.wind) + float(tm.strike) * float(tm.hit_at)) / m.speed
		character.play_once(str(a.clip), float(a.impact) / to_hit, 0.06)


func _on_damaged(_amount: int, _info: Dictionary) -> void:
	if not visible or character == null or not character.loaded or player.melee.down or player.melee.busy():
		return
	_hit_left = HIT_TIME
	character.play_once("hit", 1.0, 0.05)


## 倒下：游戏马上暂停（倒下界面），人物自己要继续播完倒地的动作
func _on_defeated() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
