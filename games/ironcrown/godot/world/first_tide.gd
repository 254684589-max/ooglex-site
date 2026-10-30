class_name FirstTide
extends Node3D
## 第一夜 · 潮水（路线图 5.4c；STORY.md 5.5 第 4 步）。诺伯特说「先过了今夜」以后，马蒂亚斯给你四支火把（主线「插火把」）：
## 栅外西南、潮水上来的那条路上有一排木桩（SPOTS），营里的兵在两头各插了一支，你把中间插满。
## 插好 READY_AT 支（或者等了 PREP_MAX 秒）潮水就上来（主线「潮水」）：COUNT 个长眠者从南边山坡（ROUTE_CAMP）径直朝营地走——
## 碰到火的改走 ROUTE_AROUND（从营地西边绕过去，SleeperCrowd.alt_route）；火把被风吹灭的空当里漏过来的，照直穿过营地。
## 走进木栅里面的算「漫进营地」；漫进来 LOSE_AT 个以上，营里被卷走一个人（`ch2_first_tide` = lost_one：天亮以后数麻袋的兵不见了），否则 held。
## 挡在路上的照样被推倒、踩过（5.4a）。不是战斗。人群走完（或者 TIDE_MAX 秒）天亮，主线「天亮以后」（5.5 接）。
## 潮水里有一张认得的脸：第一章芦栈村长眠的那个人（`ch1_sleeper`），走近了认出来。
## 进行中读档 / 换区域：从「插火把」重来（插下的火把不进存档）。

signal tide_started
signal ended(result: String)
signal recognized(text: String)

const SPOT_CENTER := Vector2(9.0, -48.0)
const SPOT_DIR := Vector2(0.79, 0.61)          # 木桩一排的方向（垂直于潮水上来的方向）
const SPOT_GAP := 2.2
const SPOT_N := 7
const SPOT_REACH := 1.6                         # 插在木桩这么近以内才算插在桩上
const READY_AT := 6                             # 七根桩插满六根就来了
const PREP_MAX := 120.0                         # 不插也就等这么久
const TIDE_MAX := 320.0
const COUNT := 36
const LOSE_AT := 5
const ROUTE_CAMP := [Vector2(-6.0, -28.0), Vector2(8.0, -46.0), Vector2(22.0, -62.0), Vector2(30.0, -90.0), Vector2(10.0, -126.0)]
const ROUTE_AROUND := [Vector2(-6.0, -28.0), Vector2(0.0, -46.0), Vector2(-1.0, -66.0), Vector2(6.0, -90.0), Vector2(10.0, -126.0)]
const SEEN_INDEX := 14                           # 认得的那张脸混在潮水中间
const FATHER_INDEX := 22                         # 妮尔的父亲（5.5b：答应过妮尔留意他才有）
const FATHER_TEXT := "潮水里有个白头发的老人，左手垂在身边——少了两根指头。是妮尔的父亲。他从你面前走过去，往北，走得很稳。"
const SEEN_NAMES := {"boatman": "渡工", "tobin": "托宾", "netter": "补网的女人"}
const SEEN_TEXT := {
	"boatman": "潮水里有一张认得的脸——芦栈村的渡工。他光着脚，闭着眼，从你面前走过去，往北。",
	"tobin": "潮水里有一张认得的脸——芦栈村的托宾。他光着脚，闭着眼，从你面前走过去，往北。",
	"netter": "潮水里有一张认得的脸——芦栈村补网的女人。她光着脚，闭着眼，从你面前走过去，往北。",
}

enum {PREP, TIDE, DONE}

var state := PREP
var player: FpController
var prep_time := 0.0
var tide_time := 0.0
var crowd: SleeperCrowd
var intruded := {}                               # 漫进营地的人（编号 → true）
var seen_model: CharacterModel                   # 第一章芦栈村长眠的那个人
var seen_said := false
var faces: Array = []                            # 潮水里认得的脸：[{index, model, text, flag, said}]（seen_model 是第一个）
var result := ""


static func spots() -> Array:
	var out := []
	for k in SPOT_N:
		out.append(SPOT_CENTER + SPOT_DIR * (k - (SPOT_N - 1) * 0.5) * SPOT_GAP)
	return out


func _ready() -> void:
	name = "FirstTide"
	_stakes()
	var sp := spots()
	for k in [0, SPOT_N - 1]:                    # 营里的兵先插了两头
		var t := PlantedTorch.make(TorchHand.FUEL, true)
		add_child(t)
		var q: Vector2 = sp[k]
		t.global_position = Vector3(q.x, Highland.height_at(q.x, q.y), q.y)


## 一排木桩：削尖的短木桩，桩头缠一圈草绳（插火把的地方）；一根绳子把它们连成一排
func _stakes() -> void:
	var kit := MeshKit.new()
	var sp := spots()
	for k in sp.size():
		var q: Vector2 = sp[k]
		var y := Highland.height_at(q.x, q.y)
		var base := Vector3(q.x + 0.35, y - 0.1, q.y)
		kit.cylinder("timber", base, base + Vector3(0, 0.75, 0), 0.06, 0.05, 6, 0.75)
		kit.cylinder("rope", base + Vector3(0, 0.55, 0), base + Vector3(0, 0.62, 0), 0.07, 0.07, 6, 0.8)
		if k + 1 < sp.size():
			var q2: Vector2 = sp[k + 1]
			var b2 := Vector3(q2.x + 0.35, Highland.height_at(q2.x, q2.y) - 0.1, q2.y)
			kit.cylinder("rope", base + Vector3(0, 0.6, 0), b2 + Vector3(0, 0.6, 0), 0.012, 0.012, 4, 0.7)
	var rope := StandardMaterial3D.new()
	rope.albedo_color = Color("8a7a5a")
	rope.roughness = 1.0
	rope.vertex_color_use_as_albedo = true
	var mi := kit.build({"timber": Look.mat("timber"), "rope": rope})
	mi.name = "TideStakes"
	add_child(mi)


## 插在桩上的、亮着的火把有几支
func lit_spots() -> int:
	var n := 0
	var torches := get_tree().get_nodes_in_group("planted_torch")
	for q in spots():
		for t in torches:
			var pt := t as PlantedTorch
			if pt and pt.lit and not pt.is_queued_for_deletion() and Vector2(pt.global_position.x, pt.global_position.z).distance_to(q) <= SPOT_REACH:
				n += 1
				break
	return n


func _physics_process(delta: float) -> void:
	match state:
		PREP:
			prep_time += delta
			if lit_spots() >= READY_AT or prep_time >= PREP_MAX:
				start_tide()
		TIDE:
			tide_time += delta
			_count_intrusions()
			_seen_tick()
			if tide_time >= TIDE_MAX:
				finish()


func start_tide() -> void:
	if state != PREP:
		return
	state = TIDE
	crowd = SleeperCrowd.make(ROUTE_CAMP, COUNT, 5.0)
	crowd.alt_route = ROUTE_AROUND
	crowd.height_fn = Highland.height_at
	crowd.player = player
	crowd.speed_base = 0.85
	var obs := [[HighlandLayout.TOWER[0], HighlandLayout.TOWER_W]]          # 木栅挡不住它们（「从营地中间走过去」）；塔和屋子绕着走
	for b in [HighlandLayout.BARRACKS, HighlandLayout.WOODSHED, HighlandLayout.GRANARY]:
		obs.append([b[0], maxf(float(b[2]), float(b[3])) * 0.55])
	crowd.obstacles = obs
	var who := str(GameState.get_flag("ch1_sleeper", ""))
	var father := str(GameState.get_flag("ch2_nell", "")) == "asked"
	if SEEN_NAMES.has(who):
		crowd.hidden[SEEN_INDEX] = true
	if father:
		crowd.hidden[FATHER_INDEX] = true
	add_child(crowd)
	crowd.finished.connect(finish)
	if SEEN_NAMES.has(who):
		seen_model = _make_face(SEEN_NAMES[who], SEEN_INDEX, SEEN_TEXT.get(who, ""), "")
	if father:
		_make_face("妮尔的父亲", FATHER_INDEX, FATHER_TEXT, "ch2_nell_father_seen")
	tide_started.emit()


## 认得的脸：用那个人的外观（data/looks.json 的名字），换上光脚的麻衣，跟着第 index 个人走；主角走到 9 米以内提示一次（flag 不空时记下旗标）
func _make_face(look_name: String, index: int, text: String, flag: String) -> CharacterModel:
	var spec := Looks.spec(look_name)
	if spec.is_empty():
		return null
	var tint: Dictionary = (spec.look.get("tint", {}) as Dictionary).duplicate()
	tint["MI_Peasant"] = SleeperCrowd.LINEN_TINT
	spec.look["tint"] = tint
	var m := CharacterModel.new()
	m.name = "Face%d" % index
	m.parts = spec.parts
	m.look = spec.look
	add_child(m)
	if m.loaded:
		Looks.hide_parts(m)
		m.play_loop("walk", 0.62)
	faces.append({"index": index, "model": m, "text": text, "flag": flag, "said": false})
	return m


func _seen_tick() -> void:
	if crowd == null:
		return
	for f in faces:
		var m: CharacterModel = f.model
		if crowd.agents.size() <= int(f.index):
			continue
		var a: Dictionary = crowd.agents[int(f.index)]
		m.visible = not a.done
		if a.done:
			continue
		var p: Vector2 = a.p
		m.global_position = Vector3(p.x, Highland.height_at(p.x, p.y), p.y)
		if (a.v as Vector2).length() > 0.05:
			m.rotation.y = atan2(a.v.x, a.v.y)
		if not bool(f.said) and player and Vector2(player.global_position.x, player.global_position.z).distance_to(p) < 9.0:
			f.said = true
			if int(f.index) == SEEN_INDEX:
				seen_said = true
			if str(f.flag) != "":
				GameState.set_flag(str(f.flag))
			recognized.emit(str(f.text))


func _count_intrusions() -> void:
	for i in crowd.agents.size():
		var a: Dictionary = crowd.agents[i]
		if not a.done and not intruded.has(i) and (a.p as Vector2).distance_to(HighlandLayout.BEACON19) < HighlandLayout.PALISADE_R - 1.0:
			intruded[i] = true


func finish() -> void:
	if state != TIDE:
		return
	state = DONE
	result = "lost_one" if intruded.size() >= LOSE_AT else "held"
	ended.emit(result)
