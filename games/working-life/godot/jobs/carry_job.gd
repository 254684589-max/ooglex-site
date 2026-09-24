class_name CarryJob
extends Node3D
## 建筑工人的搬运小游戏（3D）：在材料堆按 F 扛起材料，走到卸货区按 F 放下。
## 限时内搬得越多分越高；雨天路滑走得更慢，但目标会少一点。进行中游戏时间暂停。

signal finished(score: float)

var target := 10
var delivered := 0
var duration := 110.0
var time_left := 110.0
var done := false
var _pile: CarryPoint
var _zone: CarryPoint
var _zone_mark: MeshInstance3D
var _stack_root: Node3D


func setup(pile_pos: Vector3, zone_pos: Vector3, difficulty: int) -> void:
	target = 10 + difficulty * 2
	if WeatherManager.is_raining():
		target -= 2
	duration = 105.0
	time_left = duration
	_pile = CarryPoint.new()
	add_child(_pile)
	_pile.setup(self, true)
	_pile.global_position = pile_pos
	_zone = CarryPoint.new()
	add_child(_zone)
	_zone.setup(self, false)
	_zone.global_position = zone_pos
	_zone_mark = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.6
	cm.bottom_radius = 2.6
	cm.height = 0.05
	_zone_mark.mesh = cm
	_zone_mark.material_override = Mats.marker(Color(1.0, 0.82, 0.25, 0.35))
	add_child(_zone_mark)
	_zone_mark.global_position = zone_pos + Vector3(0, 0.06, 0)
	var pm := MeshInstance3D.new()
	pm.mesh = cm
	pm.material_override = Mats.marker(Color(0.2, 0.9, 1.0, 0.3))
	add_child(pm)
	pm.global_position = pile_pos + Vector3(0, 0.06, 0)
	_stack_root = Node3D.new()
	add_child(_stack_root)
	_stack_root.global_position = zone_pos


func pick(player: Node) -> void:
	if done or String(player.get("carrying")) != "":
		return
	player.call("set_carry", "box")
	PlayerManager.change("energy", -0.8)
	AudioManager.play_sfx("pickup")


func drop(player: Node) -> void:
	if done or String(player.get("carrying")) == "":
		return
	player.call("set_carry", "")
	delivered += 1
	AudioManager.play_sfx("place")
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.4, 0.6)
	mi.mesh = bm
	mi.material_override = Mats.color(Color(0.7, 0.3, 0.2))
	mi.position = Vector3(-1.0 + (delivered % 3) * 1.0, 0.2 + int((delivered - 1) / 3) * 0.42, 0)
	_stack_root.add_child(mi)
	if delivered >= target:
		_finish()


func status_text() -> String:
	return "搬运任务：%d / %d  ·  剩余 %d 秒%s" % [delivered, target, int(ceil(maxf(time_left, 0.0))), "（雨天路滑）" if WeatherManager.is_raining() else ""]


func _process(delta: float) -> void:
	if done:
		return
	time_left -= delta
	if time_left <= 0.0:
		_finish()


func score() -> float:
	var s := float(delivered) / float(target) * 90.0
	if delivered >= target:
		s += clampf(time_left / duration, 0.0, 1.0) * 20.0
	return clampf(s, 0.0, 100.0)


func _finish() -> void:
	if done:
		return
	done = true
	var p := GameManager.player
	if p != null:
		p.call("set_carry", "")
	finished.emit(score())
