class_name OathRitual
extends Node3D
## 封誓（路线图 8.4；STORY.md 8.5 第 6 步「封誓的时候，井口上的长眠者往下涌……你点亮井底的四个火盆撑到血滴进誓瓶：火盆灭一个，长眠者近一步。
## 火盆全灭了、或者拿不出誓瓶——封誓失败，也是长冬」；8.7「井底四个火盆（点火、续火，同第二章火把桩的规则）、血滴进誓瓶的进度；长眠者从井壁石阶上一个一个往下走」）。
## 谁去封誓在石台的对话里定（winter.json oath：oath_taker），对话一关上 main 调 start()：
##   DURATION 秒里，长眠者每 INTERVAL 秒从石阶顶上下来一个（一共 COUNT 个；第二十一烽的人引开过的少一半，ch5_watch21），顺着石阶走到底、再朝石台走；
##   四个火盆：点着的烧 FUEL 秒就灭，走过去按交互再续上（verb「点着火盆」「添柴」）；长眠者走进点着的火盆 FIRE_R 米以内就停住、往回退几步（火让它们拐弯，同第二章）；
##   走到石台 REACH_R 米以内算「够着了」：够着 FAIL_AT 个封誓就断了（failed），撑满 DURATION 秒就封上了（sealed）。
## 结果写 ch5_oath，结局写 ending（new_king / crownless_spring / long_winter），主线到 after；main 接着出结局画面（8.5）。

signal finished(result: String)

const DURATION := 45.0
const INTERVAL := 4.0
const COUNT := 10
const FUEL := 18.0
const FIRE_R := 3.0
const REACH_R := 1.6
const FAIL_AT := 3
const SPEED := 0.7
const PATH := [Vector3(3.0, 3.6, 5.3), Vector3(-4.0, 0.0, 5.3), Vector3(-2.0, 0.0, 2.0), Vector3(0.0, 0.0, 0.2)]

var t := 0.0
var spawned := 0
var reached := 0
var fuel: Array = [0.0, 0.0, 0.0, 0.0]
var walkers: Array = []                 # [{node, seg, at: Vector3, back: float}]
var done := ""
var total := COUNT


## 对话定了谁去（oath_taker 不是 none、也没封过）：在井底摆上封誓
static func due() -> bool:
	return GameState.quest_stage("ch5_main") == "oath" and GameState.has_flag("ch5_ritual") and str(GameState.get_flag("ch5_oath", "")) == ""


static func start(world: Node3D) -> OathRitual:
	if not due() or world.get_node_or_null("OathRitual") != null:
		return null
	var r := OathRitual.new()
	r.name = "OathRitual"
	r.total = COUNT / 2 if GameState.has_flag("ch5_watch21") else COUNT
	world.add_child(r)
	print("IC_OATH start taker=%s sleepers=%d" % [GameState.get_flag("oath_taker", ""), r.total])
	return r


func lit(k: int) -> bool:
	return float(fuel[k]) > 0.0


## 点火盆 / 添柴（火盆的 Examine 调）
func feed(k: int) -> Dictionary:
	if done != "":
		return {"toast": "火盆里的火慢慢矮下去了。"}
	var was := lit(k)
	fuel[k] = FUEL
	_flame(k, true)
	return {"toast": "你往火盆里添了一把柴，火又窜高了。" if was else "你点着了火盆。冰壁上的名字一下子亮了。"}


func _flame(k: int, on: bool) -> void:
	var l := get_node_or_null("Fire%d" % k) as OmniLight3D
	if l == null:
		l = OmniLight3D.new()
		l.name = "Fire%d" % k
		l.light_color = Color("ff8a3a")
		l.omni_range = 6.0
		l.position = (WellRooms.BRAZIERS[k] as Vector3) + Vector3(0, 1.3, 0)
		add_child(l)
	l.light_energy = 2.4 if on else 0.0


func _spawn() -> void:
	var spec := Looks.spec_of({"preset": "commoner" if spawned % 2 == 0 else "woman", "hair": [["Hair_Buzzed"], ["Hair_Long"]][spawned % 2], "hair_color": "#6a5a4a"})
	SleeperCrowd.chill(spec)
	var n: Node3D
	if spec.is_empty():
		n = Node3D.new()
	else:
		var m := CharacterModel.new()
		m.parts = spec.parts
		m.look = spec.look
		n = m
	n.name = "OathSleeper%d" % spawned
	add_child(n)
	n.position = PATH[0]
	if n is CharacterModel and (n as CharacterModel).loaded:
		Looks.hide_parts(n)
		(n as CharacterModel).play_loop("walk", 0.5)
	walkers.append({"node": n, "seg": 1, "back": 0.0})
	spawned += 1


## 一步（_physics_process 调；测试里直接调）
func step(delta: float) -> void:
	if done != "":
		return
	t += delta
	for k in fuel.size():
		if lit(k):
			fuel[k] = maxf(0.0, float(fuel[k]) - delta)
			if not lit(k):
				_flame(k, false)
	if spawned < total and t >= spawned * INTERVAL:
		_spawn()
	for w: Dictionary in walkers.duplicate():
		var n: Node3D = w.node
		if not is_instance_valid(n):
			continue
		var p := n.position
		var near_fire := false
		for k in fuel.size():
			if lit(k) and Vector2(p.x, p.z).distance_to(Vector2((WellRooms.BRAZIERS[k] as Vector3).x, (WellRooms.BRAZIERS[k] as Vector3).z)) < FIRE_R:
				near_fire = true
		if near_fire:
			w.back = 1.2                                                  # 碰到火：往回退一会儿
		var seg: int = int(w.seg)
		var goal: Vector3 = PATH[seg] if float(w.back) <= 0.0 else PATH[maxi(seg - 1, 0)]
		var d := goal - p
		var v := SPEED * delta * (0.6 if float(w.back) > 0.0 else 1.0)
		if d.length() <= v:
			n.position = goal
			if float(w.back) <= 0.0:
				if seg >= PATH.size() - 1:
					pass
				else:
					w.seg = seg + 1
		else:
			n.position = p + d.normalized() * v
			n.rotation.y = atan2(d.x, d.z)
		w.back = maxf(0.0, float(w.back) - delta)
		if Vector2(n.position.x, n.position.z).distance_to(Vector2(WellRooms.ALTAR.x, WellRooms.ALTAR.z)) < REACH_R:
			reached += 1
			walkers.erase(w)
			n.queue_free()
			print("IC_OATH reached=%d" % reached)
			if reached >= FAIL_AT:
				_finish("failed")
				return
	if t >= DURATION:
		_finish("sealed")


func _physics_process(delta: float) -> void:
	step(delta)


func _finish(result: String) -> void:
	done = result
	settle(result)
	for w: Dictionary in walkers:
		if is_instance_valid(w.node):
			(w.node as Node3D).queue_free()
	walkers.clear()
	print("IC_OATH done=%s reached=%d" % [result, reached])
	finished.emit(result)


## 封誓的结果写进旗标：ch5_oath、ending；主线到 after
static func settle(result: String) -> void:
	GameState.set_flag("ch5_oath", result)
	var taker := str(GameState.get_flag("oath_taker", "none"))
	var ending := "long_winter"
	if result == "sealed":
		ending = "new_king" if taker == "heir" else "crownless_spring"
	GameState.set_flag("ending", ending)
	if GameState.quest_stage("ch5_main") == "oath":
		GameState.set_stage("ch5_main", "after")
