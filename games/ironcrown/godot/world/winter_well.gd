class_name WinterWell
extends Node3D
## 白寂边缘 · 冬井（路线图 5.8b；STORY.md 5.5 第 9 步「诺伯特带你翻过山脊：冰原上那口石井，长眠者围着它站成一圈，一动不动」）。
## 井（HighlandLayout.WELL）一直在：一圈半埋在雪里的古老石砌井栏，井口压着裂成两半的石盖，一块歪倒、露出黑洞洞的井口；一根冻住的铁链挂在井栏上。
## 主线「冬井」（to_well）起：长眠的人围着井站成一圈（RING_N 个，RING_R 米），脸都朝着井，一动不动（都是真人模型，换上麻衣、光脚，定住不动）；
## 圈里有几张认得的脸（用那个人的外观）：第一章芦栈村长眠的那个人（ch1_sleeper）、妮尔的父亲（答应过妮尔才有）、
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
var ring: Node3D                                # 圈（主线「冬井」起才摆）
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


## 井（2026-11-07 所有者「把冬井做得更逼真，深一些，太浅太普通，缺乏仪式感」）：
##   脚下三圈半埋在雪里的石阶台（一圈比一圈高）；井栏三层石块，上面压一圈厚盖石，盖石边上挂着冰凌；
##   井口往下看得见一米多的井壁（一圈一圈越往下越暗），再往下是黑的，底下透上来一点冷光、冒着一股寒气；
##   外面一圈六块高高的立石（刻着几道磨平了的线，顶上积着霜），像是给什么仪式立的；井口上架着一副三根木杆的旧吊架，冻住的铁链从架顶垂进井里；
##   裂成两半的石盖：一半还压在井口边上，一半歪倒在台阶上。
const CURB_R := 1.25
const CURB_H := 1.05
const STONES_R := 3.5


func _build_well() -> void:
	var c := ground(HighlandLayout.WELL)
	var kit := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5821
	for ring_i in 3:                                                                                       # 石阶台：三圈，半埋在雪里
		var r: float = [2.75, 2.25, 1.8][ring_i]
		var hgt: float = [0.08, 0.15, 0.22][ring_i]
		var n: int = [26, 22, 18][ring_i]
		for k in n:
			var a := TAU * (k + 0.3 * ring_i) / n
			var w := TAU * r / n * 0.97
			kit.box("stone", c + Vector3(cos(a) * (r - 0.25), hgt * 0.5 - 0.02, sin(a) * (r - 0.25)), Vector3(0.5, hgt + 0.04, w), Basis(Vector3.UP, -a), 0.82, 0.6)
	for layer in 3:                                                                                        # 井栏：三层石块
		var n := 14
		for k in n:
			var a := TAU * (k + 0.5 * layer) / n
			var p := c + Vector3(cos(a) * CURB_R, 0.22 + 0.18 + layer * 0.3, sin(a) * CURB_R)
			var bb := Basis(Vector3.UP, -a) * Basis(Vector3.FORWARD, rng.randf_range(-0.04, 0.04))
			kit.box("stone", p, Vector3(0.38, 0.3 + rng.randf_range(-0.02, 0.03), 0.6), bb, 0.9 - layer * 0.04, 0.7)
	for k in 10:                                                                                           # 盖石：一圈厚石板，边上挂着冰凌
		var a := TAU * k / 10.0
		var p := c + Vector3(cos(a) * (CURB_R + 0.04), CURB_H - 0.03, sin(a) * (CURB_R + 0.04))
		kit.box("stone", p, Vector3(0.52, 0.14, 0.82), Basis(Vector3.UP, -a), 1.0, 0.85)
		kit.box("frost", p + Vector3(0, 0.08, 0), Vector3(0.5, 0.02, 0.8), Basis(Vector3.UP, -a))
		for j in 3:
			var ia := a + (j - 1) * 0.18
			var ip := c + Vector3(cos(ia) * (CURB_R + 0.33), CURB_H - 0.1, sin(ia) * (CURB_R + 0.33))
			kit.tube("ice", ip, ip - Vector3(0, rng.randf_range(0.12, 0.3), 0), 0.025, 0.003, 6)
	for d in 6:                                                                                            # 井壁：往下一圈一圈，越往下越暗
		var y0 := CURB_H - 0.1 - d * 0.18
		kit.tube("shaft", c + Vector3(0, y0, 0), c + Vector3(0, y0 - 0.2, 0), CURB_R - 0.22, CURB_R - 0.22, 18, 1.0 - d * 0.16, 0.0)
	kit.cylinder("dark", c + Vector3(0, CURB_H - 1.2, 0), c + Vector3(0, CURB_H - 1.17, 0), CURB_R - 0.2, CURB_R - 0.2, 18, 1.0)   # 再往下：黑的
	var half := Basis(Vector3.UP, 0.4) * Basis(Vector3.RIGHT, 0.03)
	kit.box("stone", c + half * Vector3(0.55, CURB_H + 0.12, 0), Vector3(0.75, 0.16, 2.4), half, 0.9, 0.7)  # 石盖：一半还压在井口边上
	for k in 3:
		kit.box("groove", c + half * Vector3(0.55, CURB_H + 0.21, -0.6 + k * 0.6), Vector3(0.5, 0.012, 0.04), half)
	var tilt := Basis(Vector3.UP, 0.9) * Basis(Vector3.FORWARD, 0.4)
	kit.box("stone", c + Vector3(-2.05, 0.38, 0.75), Vector3(0.75, 0.16, 2.2), tilt, 0.9, 0.7)            # 另一半歪倒在台阶上
	for k in 6:                                                                                            # 立石：一圈六块，刻着几道线，顶上积霜
		var a := TAU * k / 6.0 + 0.26
		var hgt := rng.randf_range(2.1, 2.9)
		var base := c + Vector3(cos(a) * STONES_R, -0.2, sin(a) * STONES_R)
		var lean := Basis(Vector3.UP, -a) * Basis(Vector3.FORWARD, rng.randf_range(-0.07, 0.07)) * Basis(Vector3.RIGHT, rng.randf_range(-0.05, 0.05))
		kit.box("stone", base + lean * Vector3(0, hgt * 0.5, 0), Vector3(0.36, hgt, 0.62), lean, 1.0, 0.65)
		kit.box("frost", base + lean * Vector3(0, hgt + 0.02, 0), Vector3(0.38, 0.05, 0.64), lean)
		for g in 4:
			kit.box("groove", base + lean * Vector3(-0.185, hgt * (0.45 + g * 0.1), 0), Vector3(0.012, 0.03, 0.4 - g * 0.06), lean)
	var top := c + Vector3(0, 2.9, 0)                                                                      # 吊架：三根木杆
	for k in 3:
		var a := TAU * k / 3.0 + 0.5
		kit.tube("timber", c + Vector3(cos(a) * (CURB_R + 0.55), 0.15, sin(a) * (CURB_R + 0.55)), top, 0.07, 0.05, 8)
	var link := top
	for k in 16:                                                                                           # 铁链：从架顶垂进井里
		var nxt := top + Vector3(0.02 * sin(k * 0.7), -0.16 * (k + 1), 0)
		kit.tube("iron", link, nxt, 0.022, 0.022, 6)
		link = nxt
	var stone := Look.mat("stone")
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("020304")
	dark.roughness = 1.0
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var shaft := Look.mat("stone").duplicate() as StandardMaterial3D
	shaft.cull_mode = BaseMaterial3D.CULL_DISABLED
	shaft.vertex_color_use_as_albedo = true
	var groove := StandardMaterial3D.new()
	groove.albedo_color = Color("2a2a2c")
	var frost := StandardMaterial3D.new()
	frost.albedo_color = Color("e4ecf2")
	frost.roughness = 0.9
	var ice := StandardMaterial3D.new()
	ice.albedo_color = Color(0.8, 0.9, 1.0, 0.75)
	ice.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ice.roughness = 0.15
	var timber := Look.mat("timber")
	var mi := kit.build({"stone": stone, "dark": dark, "shaft": shaft, "groove": groove, "iron": Inn._iron_mat(), "frost": frost, "ice": ice, "timber": timber})
	mi.name = "WinterWellStones"
	mi.visibility_range_end = 180.0
	add_child(mi)
	var glow := OmniLight3D.new()                                                                          # 井底透上来的一点冷光
	glow.name = "WellGlow"
	glow.light_color = Color(0.55, 0.72, 1.0)
	glow.light_energy = 0.9
	glow.omni_range = 3.2
	glow.position = c + Vector3(0, CURB_H - 0.9, 0)
	add_child(glow)
	Castle._solid(self, c + Vector3(0, 0.6, 0), Vector3(2.9, 1.2, 2.9))
	for k in 6:
		var a := TAU * k / 6.0 + 0.26
		Castle._solid(self, c + Vector3(cos(a) * STONES_R, 1.2, sin(a) * STONES_R), Vector3(0.5, 2.4, 0.5))
	Castle._solid(self, c + Vector3(0, 0.08, 0), Vector3(5.2, 0.16, 5.2))                                 # 石阶台：站得上去


## 圈：每个人都是真人模型（白天看得清：SleeperCrowd 远处那种简化的人在天光下像一排白石膏）——生人换上麻衣、光脚，几种村民的打扮轮着来；认得的脸用那个人的外观
func _build_ring() -> void:
	if ring:
		return
	ring = Node3D.new()
	ring.name = "WellRing"
	add_child(ring)
	var specs := _face_specs()
	var taken := {}
	for f in specs:
		taken[int(f.slot)] = true
	for k in RING_N:
		if taken.has(k):
			continue
		var spec := Looks.spec_of({"preset": "woman" if k % 3 == 1 else "commoner", "hair": [["Hair_Buzzed"], ["Hair_Long"], ["Hair_SimpleParted"], ["Hair_Buzzed", "Hair_Beard"]][k % 4],
			"hair_color": ["#3a2a1a", "#6a5a4a", "#9a948a", "#2a2018", "#c8c4bc"][k % 5]})
		if spec.is_empty():
			continue
		SleeperCrowd.chill(spec)
		_place_model(spec, k)
	for f in specs:
		var model := _face(f)
		if model:
			faces.append({"model": model, "slot": int(f.slot), "text": str(f.text), "said": false})
	add_child(SleeperHum.make(func() -> float:                # 走近那一圈：一片很低的、整齐的呼吸（站着不走，没有脚步声；2026-11-07）
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam == null:
			return INF
		return absf(Vector2(cam.global_position.x, cam.global_position.z).distance_to(HighlandLayout.WELL) - RING_R), false))


## 一个人站在圈上第 k 个位置，脸朝井，定住不动
func _place_model(spec: Dictionary, k: int) -> CharacterModel:
	var m := CharacterModel.new()
	m.name = "WellFace%d" % k
	m.parts = spec.parts
	m.look = spec.look
	ring.add_child(m)
	var p := slot(k)
	m.global_position = ground(p)
	var to := HighlandLayout.WELL - p
	m.rotation.y = atan2(to.x, to.y) + 0.06 * sin(k * 2.3)
	if m.loaded:
		Looks.hide_parts(m)
		m.hold("idle", 0.2 + 0.05 * (k % 5))         # 定住：一动不动（各停在呼吸的不同一刻，不像一排木头）
		for mi: MeshInstance3D in m.scene_root.find_children("*", "MeshInstance3D", true, false):
			mi.visibility_range_end = Looks.LOD_FAR
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


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
		SleeperCrowd.chill(spec)                          # 长眠了的认得的脸：一样换成长眠者的样子
	return _place_model(spec, int(f.slot))


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
	if not revealed_said and pp.distance_to(w) <= REVEAL_R and ring != null:
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
