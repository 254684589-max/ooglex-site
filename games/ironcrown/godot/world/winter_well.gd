class_name WinterWell
extends Node3D
## 白寂边缘 · 冬井（路线图 5.8b；STORY.md 5.5 第 9 步「诺伯特带你翻过山脊：冰原上那口石井，长眠者围着它站成一圈，一动不动」）。
## 井（HighlandLayout.WELL）一直在：一圈半埋在雪里的古老石砌井栏，井口压着裂成两半的石盖，一块歪倒、露出黑洞洞的井口；一根冻住的铁链挂在井栏上。
## 主线「冬井」（to_well）起：长眠的人围着井站成一圈（RING_N 个，RING_R 米），脸都朝着井，一动不动（远看是 SleeperCrowd 那种简化的人，一份多实例）；
## 圈里有几张认得的脸（真人模型，换上麻衣、光脚，定住不动）：第一章芦栈村长眠的那个人（ch1_sleeper）、妮尔的父亲（答应过妮尔才有）、
## 随她去了的妮尔（还穿着自己的衣服、背着包袱）、点着了第十八烽的话那三个守塔人。走到 FACE_R 以内认出来（recognized 信号，各一次）。
## 诺伯特：诺伯特在塔顶说完以后从天窗下去，在山脊背后（RIDGE_WAIT）等你；你走到 FOLLOW_R 以内，他往冰原下面走，停在井边 STOP_R 米。
## 你走到 REVEAL_R 以内（revealed，提示一次）；他到了、你也走到 END_R 以内 → reached（main：他说一句、过一会儿章末）。

signal revealed
signal recognized(text: String)
signal reached

const RING_N := 22
const RING_R := 5.6
const RIDGE_WAIT := Vector2(-4.0, -86.0)        # 山脊背后，冰原往下的口子上
const STOP_R := 8.5
const FOLLOW_R := 6.0
const WALK_SPEED := 1.0
const REVEAL_R := 24.0
const FACE_R := 9.0
const END_R := 12.0
const STAGES := ["to_well", "ch2_end"]
const NELL_TEXT := "圈里站着妮尔。包袱还背在身上，眼睛闭着，脸朝着井。"
const FATHER_TEXT := "白头发的老人站在圈里，左手少了两根指头——妮尔的父亲。他不往北走了。"
const FATHER_NELL_TEXT := "白头发的老人站在圈里，左手少了两根指头——妮尔的父亲。妮尔就站在他旁边。"
const KEEPER_TEXT := "第十八烽那三个守塔人也在，挨着站在一起。第二天塔脚下就不见了的那三个。"
const SEEN_TEXT := {
	"boatman": "圈里有一张认得的脸——芦栈村的渡工。他光着脚站在雪里，脸朝着井。",
	"tobin": "圈里有一张认得的脸——芦栈村的托宾。他光着脚站在雪里，脸朝着井。",
	"netter": "圈里有一张认得的脸——芦栈村补网的女人。她光着脚站在雪里，脸朝着井。",
}

var player: FpController
var norbert: Npc
var norbert_state := "wait"                     # wait（在山脊背后等）/ walk / there
var faces: Array = []                           # [{model, slot, text, said}]
var mm: MultiMeshInstance3D
var revealed_said := false
var reached_sent := false


## 圈和诺伯特在不在：主线「冬井」以后（章末以后也还在）
static func due() -> bool:
	return GameState.chapter == 2 and GameState.quest_stage("ch2_main") in STAGES


## 井一直在；该有圈的时候摆上圈和诺伯特（main 在高地搭好以后调）
static func setup(world: Node3D) -> WinterWell:
	var w := WinterWell.new()
	w.name = "WinterWell"
	world.add_child(w)
	return w


static func ground(p: Vector2) -> Vector3:
	return Vector3(p.x, Highland.height_at(p.x, p.y), p.y)


## 井边诺伯特站住的地方（从山脊这边过来，离井 STOP_R 米）
static func stop_point() -> Vector2:
	var w := HighlandLayout.WELL
	return w + (RIDGE_WAIT - w).normalized() * STOP_R


## 圈上第 k 个人站的地方
static func slot(k: int) -> Vector2:
	var a := TAU * k / RING_N + 0.13
	return HighlandLayout.WELL + Vector2(cos(a), sin(a)) * RING_R


func _ready() -> void:
	_build_well()
	if due():
		_build_ring()
		ensure_norbert()


## 井：石砌的井栏（一圈两层的石块，半埋在雪里）、裂成两半的石盖（一半歪倒在雪里）、黑洞洞的井口、一根冻住的铁链
func _build_well() -> void:
	var c := ground(HighlandLayout.WELL)
	var kit := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5821
	for layer in 2:
		var n := 14
		for k in n:
			var a := TAU * (k + 0.5 * layer) / n
			var r := 1.25
			var p := c + Vector3(cos(a) * r, 0.18 + layer * 0.34 - 0.12, sin(a) * r)
			var b := Basis(Vector3.UP, -a) * Basis(Vector3.FORWARD, rng.randf_range(-0.05, 0.05))
			kit.box("stone", p, Vector3(0.36, 0.34 + rng.randf_range(-0.03, 0.04), 0.58), b, 0.92, 0.7)
	kit.cylinder("dark", c + Vector3(0, 0.55, 0), c + Vector3(0, 0.62, 0), 1.0, 1.0, 16, 1.0)              # 井口：黑的
	var half := Basis(Vector3.UP, 0.4) * Basis(Vector3.RIGHT, 0.03)
	kit.box("stone", c + half * Vector3(0.35, 0.72, 0), Vector3(0.75, 0.16, 2.3), half, 0.9, 0.7)          # 石盖：一半还压在井口上
	var tilt := Basis(Vector3.UP, 0.9) * Basis(Vector3.FORWARD, 0.55)
	kit.box("stone", c + Vector3(-1.75, 0.3, 0.6), Vector3(0.75, 0.16, 2.2), tilt, 0.9, 0.7)               # 另一半歪倒在雪里
	for k in 3:                                                                                            # 石盖上刻的几道线（磨得快看不清了）
		kit.box("groove", c + half * Vector3(0.35, 0.81, -0.6 + k * 0.6), Vector3(0.5, 0.012, 0.04), half)
	var top := c + Vector3(1.2, 0.78, 0.2)
	for k in 7:                                                                                            # 冻住的铁链：从井栏上垂进井里
		var p0 := top + Vector3(-0.12 * k, -0.08 * k * k * 0.25, 0.02 * k)
		kit.cylinder("iron", p0, p0 + Vector3(-0.12, -0.1, 0.02), 0.025, 0.025, 5)
	var stone := Look.mat("stone")
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("050608")
	dark.roughness = 1.0
	var groove := StandardMaterial3D.new()
	groove.albedo_color = Color("2a2a2c")
	var mi := kit.build({"stone": stone, "dark": dark, "groove": groove, "iron": Inn._iron_mat()})
	mi.name = "WinterWellStones"
	mi.visibility_range_end = 160.0
	add_child(mi)
	Castle._solid(self, c + Vector3(0, 0.5, 0), Vector3(2.9, 1.0, 2.9))


## 圈：多实例的简化人（同 SleeperCrowd 的远处画法），认得的脸换成真人模型
func _build_ring() -> void:
	var specs := _face_specs()
	var taken := {}
	for f in specs:
		taken[int(f.slot)] = true
	mm = MultiMeshInstance3D.new()
	mm.name = "WellRing"
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.use_colors = true
	m.mesh = SleeperCrowd.figure_mesh()
	m.instance_count = RING_N - taken.size()
	mm.multimesh = m
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mm.layers = SleeperCrowd.LAYER
	add_child(mm)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5822
	var i := 0
	for k in RING_N:
		if taken.has(k):
			continue
		var p := slot(k)
		var g := ground(p)
		var to := HighlandLayout.WELL - p
		var b := Basis(Vector3.UP, atan2(to.x, to.y) + rng.randf_range(-0.08, 0.08)).scaled(Vector3.ONE * rng.randf_range(0.93, 1.06))
		m.set_instance_transform(i, Transform3D(b, g))
		var t := rng.randf_range(0.85, 1.05)
		m.set_instance_color(i, Color(t, t, t))
		i += 1
	for f in specs:
		var model := _face(f)
		if model:
			faces.append({"model": model, "slot": int(f.slot), "text": str(f.text), "said": false})


## 圈里认得的脸：[{look, slot, text, linen}]
static func _face_specs() -> Array:
	var out := []
	var who := str(GameState.get_flag("ch1_sleeper", ""))
	if FirstTide.SEEN_NAMES.has(who):
		out.append({"look": FirstTide.SEEN_NAMES[who], "slot": 1, "text": SEEN_TEXT.get(who, ""), "linen": true})
	var nell := str(GameState.get_flag("ch2_nell", ""))
	if nell != "":
		out.append({"look": "妮尔的父亲", "slot": 8, "text": FATHER_NELL_TEXT if nell == "left" else FATHER_TEXT, "linen": true})
	if nell == "left":
		out.append({"look": "妮尔", "slot": 9, "text": NELL_TEXT, "linen": false})
	if str(GameState.get_flag("ch2_beacon18", "")) == "lit":
		for k in 3:
			out.append({"look": "长眠的守塔人", "slot": 14 + k, "text": KEEPER_TEXT if k == 0 else "", "linen": true})
	return out


func _face(f: Dictionary) -> CharacterModel:
	var spec := Looks.spec(str(f.look))
	if spec.is_empty():
		return null
	if bool(f.linen):
		var tint: Dictionary = (spec.look.get("tint", {}) as Dictionary).duplicate()
		tint["MI_Peasant"] = SleeperCrowd.LINEN_TINT
		spec.look["tint"] = tint
	var m := CharacterModel.new()
	m.name = "WellFace%d" % int(f.slot)
	m.parts = spec.parts
	m.look = spec.look
	add_child(m)
	var p := slot(int(f.slot))
	m.global_position = ground(p)
	var to := HighlandLayout.WELL - p
	m.rotation.y = atan2(to.x, to.y)
	if m.loaded:
		Looks.hide_parts(m)
		m.hold("idle", 0.4)                       # 定住：一动不动
		for mi: MeshInstance3D in m.scene_root.find_children("*", "MeshInstance3D", true, false):
			mi.visibility_range_end = Looks.LOD_FAR
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## 诺伯特：不在（塔顶那个已经下去了）就放到山脊背后等你
func ensure_norbert() -> void:
	if norbert and is_instance_valid(norbert):
		return
	var at := RIDGE_WAIT
	if GameState.quest_stage("ch2_main") == "ch2_end":
		at = stop_point()
		norbert_state = "there"
	norbert = Npc.make("诺伯特", ["（他看着井，没回头）", "……它们在等。"], Color("5a5650"))
	norbert.name = "Npc_norbert_well"
	add_child(norbert)
	norbert.global_position = ground(at)
	_face_well(norbert)


func _face_well(n: Node3D) -> void:
	var p := Vector2(n.global_position.x, n.global_position.z)
	var to := HighlandLayout.WELL - p
	n.rotation.y = atan2(-to.x, -to.y)            # Npc：rotation.y = θ 时面朝 (-sin θ, -cos θ)


func _physics_process(delta: float) -> void:
	if not due() or player == null:
		return
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var w := HighlandLayout.WELL
	if norbert and is_instance_valid(norbert):
		var np := Vector2(norbert.global_position.x, norbert.global_position.z)
		match norbert_state:
			"wait":
				if pp.distance_to(np) <= FOLLOW_R:
					norbert_state = "walk"
					_anim(norbert, "walk", 0.62)
					print("IC_WELL norbert_walk")
			"walk":
				var goal := stop_point()
				var d := goal - np
				if d.length() <= WALK_SPEED * delta:
					norbert.global_position = ground(goal)
					norbert_state = "there"
					_anim(norbert, "idle", 1.0)
					_face_well(norbert)
					print("IC_WELL norbert_there")
				else:
					var np2 := np + d.normalized() * WALK_SPEED * delta
					norbert.global_position = ground(np2)
					norbert.rotation.y = atan2(-d.x, -d.y)
	if not revealed_said and pp.distance_to(w) <= REVEAL_R and mm != null:
		revealed_said = true
		revealed.emit()
	for f in faces:
		if not bool(f.said) and str(f.text) != "" and pp.distance_to(slot(int(f.slot))) <= FACE_R:
			f.said = true
			recognized.emit(str(f.text))
	if not reached_sent and norbert_state == "there" and pp.distance_to(w) <= END_R:
		reached_sent = true
		reached.emit()
		print("IC_WELL reached")


static func _anim(n: Npc, r: String, speed: float) -> void:
	if n.look_model and n.look_model.loaded:
		n.look_model.play_loop(r, speed)
