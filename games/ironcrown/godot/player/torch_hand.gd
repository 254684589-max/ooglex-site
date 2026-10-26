class_name TorchHand
extends Node3D
## 左手的火把（路线图 5.4b；STORY.md 5.4「火把：能点、能举、会被风雪吹灭、能插在地上当火堆」）。
## 一个键（T，触屏「火」）按情况做事：手里空着 → 从背包拿一支、打火石点着（风里要多打几下）；举着点着的 → 插在面前的地上（PlantedTorch）；
## 举着灭了的 → 重新点。举着火把时左手占着，不能格挡（Melee.block_press 问 held()）。
## 举着的火是一团「火」：组 light_source、带 radius 元数据（长眠者群绕开它——火把能「引」着它们走，敌人看得见你站在亮处），
## 元数据 no_warm（暖不了身子：Cold.near_fire 不算）。高地的户外有风：每秒有一点机会被吹灭；被长眠者推倒也会摔灭。
## 烧完 FUEL 秒就没了。换区域时手里的火把跟着走（GameState.held_torch，不进存档）。

signal changed(state: int)
signal said(text: String)

enum {NONE, LIGHTING, LIT, OUT}

const FUEL := 300.0               # 一支火把烧多久（秒）
const LIGHT_TIME := 1.2           # 打火石点着要多久
const LIGHT_TIME_WIND := 2.4      # 风里多打几下
const RADIUS := 1.8               # 长眠者绕开的火边（SleeperCrowd 再乘 FIRE_GAIN）
const BLOW_HELD := 1.0 / 240.0    # 风里举着，每秒被吹灭的机会（平均四分钟一次；你用身子挡着风）
const HAND_FP := Vector3(-0.40, -0.44, -0.62)     # 第一人称：火把在画面左下（相机空间）
const HAND_BODY := Vector3(-0.38, 1.45, -0.42)    # 火在身上的位置（身体空间，算火的中心、插地的位置用）
const PLANT_DIST := 0.9
const LIGHT_MASK := 0xFFFFF & ~SleeperCrowd.LAYER    # 火把的光不照长眠者群（绘制调用；它们有自发光）

var player: FpController
var state := NONE
var fuel := 0.0
var lighting_left := 0.0
var windy := false                # 高地的户外（main 设）
var rng := RandomNumberGenerator.new()
var fp_visual: Node3D
var tp_visual: Node3D
var fire: Node3D                  # 火的中心（组 light_source）
var light: OmniLight3D


func _ready() -> void:
	rng.randomize()
	fire = Node3D.new()
	fire.name = "TorchFire"
	fire.set_meta("radius", RADIUS)
	fire.set_meta("no_warm", true)
	add_child(fire)
	fire.top_level = true
	if player and player.camera:
		fp_visual = make_visual()
		fp_visual.name = "TorchFP"
		fp_visual.position = HAND_FP
		fp_visual.rotation = Vector3(deg_to_rad(-8.0), 0.0, deg_to_rad(10.0))      # 火头稍微往外偏，不挡画面中间
		fp_visual.scale = Vector3.ONE * 0.62
		player.camera.add_child(fp_visual)
		for g in fp_visual.find_children("*", "VisualInstance3D", true, false):
			(g as VisualInstance3D).layers = SleeperCrowd.LAYER     # 自己的火光不照自己手里这根棍（贴得太近，照成一块亮橙色的板）
	var h: Dictionary = GameState.held_torch
	if not h.is_empty() and float(h.get("fuel", 0.0)) > 0.0:
		fuel = float(h.fuel)
		_set_state(LIT if bool(h.get("lit", false)) else OUT)
	else:
		_set_state(NONE)


func held() -> bool:
	return state != NONE


func lit() -> bool:
	return state == LIT


## T 键 / 触屏「火」
func use_key() -> void:
	if player and player.knocked():
		return
	match state:
		NONE:
			if not GameState.has_item("torch"):
				said.emit("没有火把。羊脊村的铁匠那儿有卖。")
				return
			GameState.take_item("torch")
			fuel = FUEL
			_start_lighting()
		LIT:
			plant()
		OUT:
			_start_lighting()


func _start_lighting() -> void:
	lighting_left = LIGHT_TIME_WIND if windy else LIGHT_TIME
	if windy:
		said.emit("风大，打了几下火石……")
	_set_state(LIGHTING)


## 插在面前的地上（地面用射线找；找不到就插在脚边）
func plant() -> PlantedTorch:
	if state != LIT or player == null:
		return null
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var at := player.global_position + fwd * PLANT_DIST
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 1.5, 0), at - Vector3(0, 3.0, 0), 1, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		at = hit.position
	else:
		at.y = player.global_position.y
	var t := PlantedTorch.make(fuel, windy)
	player.get_parent().add_child(t)
	t.global_position = at
	t.rotation.y = player.rotation.y
	fuel = 0.0
	_set_state(NONE)
	return t


## 从地上拔起一支点着的（PlantedTorch.interact）
func take_from_ground(f: float) -> void:
	fuel = f
	_set_state(LIT)


## 用举着的火去点 / 灭（被风吹、被推倒）
func blow_out(text := "风把火把吹灭了。") -> void:
	if state != LIT and state != LIGHTING:
		return
	_set_state(OUT)
	said.emit(text)


func on_knocked() -> void:
	blow_out("火把摔进雪里，灭了。")


func _physics_process(delta: float) -> void:
	if player == null:
		return
	fire.global_position = player.global_transform * HAND_BODY
	match state:
		LIGHTING:
			lighting_left -= delta
			if lighting_left <= 0.0:
				_set_state(LIT)
		LIT:
			fuel -= delta
			if fuel <= 0.0:
				fuel = 0.0
				_set_state(NONE)
				said.emit("火把烧完了。")
			elif windy and rng.randf() < BLOW_HELD * delta:
				blow_out()
			elif light and not Settings.reduced_motion:
				var t := Time.get_ticks_msec() * 0.001
				light.light_energy = 1.4 * (1.0 + sin(t * 9.3) * 0.07 + sin(t * 21.1 + 0.7) * 0.05)
	_sync_tp()


## 第三人称：挂到人物的左手（人物模型是用到时才搭的，搭好以后再挂）
func _sync_tp() -> void:
	if tp_visual == null and player.avatar and player.avatar.character and player.avatar.character.loaded:
		tp_visual = make_visual()
		tp_visual.name = "TorchTP"
		player.avatar.character.hold_prop(tp_visual, true)
		_apply_visuals()


func _set_state(s: int) -> void:
	state = s
	if s == LIT:
		fire.add_to_group("light_source")
	elif fire.is_in_group("light_source"):
		fire.remove_from_group("light_source")
	if s == LIT and light == null:            # 光源只在点着时才有（各区域的灯光预算按场景里有几盏点光源算，不能藏一盏在身上）
		light = OmniLight3D.new()
		light.name = "TorchLight"
		light.light_color = Color("ff9a4a")
		light.light_energy = 1.4
		light.omni_range = 7.5
		light.omni_attenuation = 1.4
		light.shadow_enabled = false
		light.light_cull_mask = LIGHT_MASK
		fire.add_child(light)
	elif s != LIT and light != null:
		light.queue_free()
		light = null
	_apply_visuals()
	GameState.held_torch = {"fuel": fuel, "lit": s == LIT or s == LIGHTING} if s != NONE else {}
	if player and player.melee and s != NONE and player.melee.block_held:
		player.melee.block_release()        # 举起火把：左手不再格挡
	changed.emit(s)


func _apply_visuals() -> void:
	for v in [fp_visual, tp_visual]:
		if v == null:
			continue
		v.visible = state != NONE
		set_lit(v, state == LIT)


## 火把的样子：木棍、缠着浸了松脂的布的头、两片卷动的火苗（shaders/flame.gdshader）、一团光晕。握把在原点、火头朝 +Y（同 Props 的握法）
static func make_visual(flame_count := 2) -> Node3D:
	var root := Node3D.new()
	var kit := MeshKit.new()
	kit.cylinder("wood", Vector3(0, -0.18, 0), Vector3(0, 0.46, 0), 0.022, 0.019, 9, 0.8)
	kit.cylinder("rag", Vector3(0, 0.40, 0), Vector3(0, 0.47, 0), 0.034, 0.042, 10, 0.7)
	kit.cylinder("rag", Vector3(0, 0.47, 0), Vector3(0, 0.58, 0), 0.042, 0.03, 10, 0.6)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("5a4030")
	wood.roughness = 0.9
	wood.vertex_color_use_as_albedo = true
	var rag := StandardMaterial3D.new()
	rag.albedo_color = Color("2a2018")
	rag.roughness = 1.0
	rag.vertex_color_use_as_albedo = true
	var stick := kit.build({"wood": wood, "rag": rag})
	stick.name = "Stick"
	stick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(stick)
	var flames := Node3D.new()
	flames.name = "Flames"
	root.add_child(flames)
	var sh := load("res://shaders/flame.gdshader") as Shader
	for k in flame_count:
		var q := QuadMesh.new()
		q.size = [Vector2(0.2, 0.38), Vector2(0.14, 0.28)][k]
		var fm := ShaderMaterial.new()
		fm.shader = sh
		fm.set_shader_parameter("noise_tex", Look.noise_texture())
		fm.set_shader_parameter("phase", 0.37 * k + 0.2)
		fm.set_shader_parameter("speed", 0.0 if Settings.reduced_motion else 1.6)
		fm.set_shader_parameter("strength", 1.2 if k == 0 else 1.0)
		q.material = fm
		var fl := MeshInstance3D.new()
		fl.mesh = q
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fl.position = Vector3(0.01 * k, 0.52 + q.size.y * 0.5, -0.01 * k)
		flames.add_child(fl)
	var halo := MeshInstance3D.new()
	var hq := QuadMesh.new()
	hq.size = Vector2(0.9, 0.9)
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.albedo_texture = Look.halo_texture()
	hm.albedo_color = Color(1.0, 0.6, 0.25, 0.7)
	hm.disable_fog = true
	hq.material = hm
	halo.mesh = hq
	halo.position = Vector3(0, 0.68, 0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flames.add_child(halo)
	return root


static func set_lit(v: Node3D, on: bool) -> void:
	var f := v.get_node_or_null("Flames")
	if f:
		f.visible = on
