class_name Train
extends Node3D
## 开场的磁悬浮列车：五节车厢，沿高架轨道从东边驶入中央火车站并减速停下。

signal arrived

const CARS := 5
const CAR_LEN := 18.0
var start_x := 420.0
var stop_x := 30.0
var duration := 9.0
var _t := 0.0
var running := false


func _ready() -> void:
	var shell := BoxMesh.new()
	shell.size = Vector3(CAR_LEN - 0.6, 3.2, 3.2)
	var win := BoxMesh.new()
	win.size = Vector3(CAR_LEN - 3.0, 0.8, 3.25)
	var stripe := BoxMesh.new()
	stripe.size = Vector3(CAR_LEN - 0.6, 0.15, 3.28)
	for i in CARS:
		var car := Node3D.new()
		car.position = Vector3(i * CAR_LEN, 0, 0)
		add_child(car)
		var mi := MeshInstance3D.new()
		mi.mesh = shell
		mi.material_override = Mats.color(Color(0.8, 0.82, 0.86), 0.25)
		mi.position = Vector3(0, 1.8, 0)
		car.add_child(mi)
		var w := MeshInstance3D.new()
		w.mesh = win
		w.material_override = Mats.glow(Color(0.7, 0.9, 1.0))
		w.position = Vector3(0, 2.3, 0)
		car.add_child(w)
		var s := MeshInstance3D.new()
		s.mesh = stripe
		s.material_override = Mats.glow(Color(1.0, 0.2, 0.55))
		s.position = Vector3(0, 1.0, 0)
		car.add_child(s)
	var nose := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(3.2, 3.2, 3.0)
	nose.mesh = pm
	nose.rotation = Vector3(0, 0, PI * 0.5)
	nose.position = Vector3(-CAR_LEN * 0.5 - 1.2, 1.8, 0)
	nose.material_override = Mats.color(Color(0.8, 0.82, 0.86), 0.25)
	add_child(nose)
	var head := OmniLight3D.new()
	head.position = Vector3(-CAR_LEN * 0.5 - 3, 2, 0)
	head.light_color = Color(0.8, 0.95, 1.0)
	head.omni_range = 14.0
	head.light_energy = 2.0
	add_child(head)
	visible = false


func start() -> void:
	_t = 0.0
	running = true
	visible = true
	position.x = start_x


func place_at_stop() -> void:
	running = false
	visible = true
	position.x = stop_x


func _process(delta: float) -> void:
	if not running:
		return
	_t = minf(_t + delta, duration)
	var k := _t / duration
	# 缓出：先快后慢
	var e := 1.0 - pow(1.0 - k, 3.0)
	position.x = lerpf(start_x, stop_x, e)
	if _t >= duration:
		running = false
		arrived.emit()
