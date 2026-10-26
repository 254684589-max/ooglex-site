class_name PlantedTorch
extends Interactable
## 插在地上的火把（路线图 5.4b）：主角举着点着的火把按 T 插下去（TorchHand.plant）。
## 亮着时是一团火：组 light_source + radius 元数据（长眠者绕开、敌人看得见亮处），no_warm（暖不了身子）；
## 接着烧手里剩下的那些时间，烧完剩一根黑棍；高地的户外会被风吹灭（比举着的更容易：没人用身子挡风）。
## 对着它按 E：亮着 → 拔起来（手里空着才行）；灭了 → 用举着的、点着的火把点着它。
## 实时光源只给最新插下的几支（max_lights，main 按画质设）：网页上每多一盏灯都要多画一遍，其余的只有火苗和光晕。

const BLOW := 1.0 / 180.0         # 风里每秒被吹灭的机会（平均三分钟一次：没人挡风；插一排的话，三十来秒就得去点一支）
const BURNT_FREE := 60.0          # 烧完的黑棍多久以后收走

static var max_lights := 3
static var _serial := 0

var fuel := TorchHand.FUEL
var lit := true
var windy := false
var serial := 0
var visual: Node3D
var light: OmniLight3D
var rng := RandomNumberGenerator.new()
var burnt_left := -1.0


static func make(f: float, is_windy: bool) -> PlantedTorch:
	var t := PlantedTorch.new()
	t.fuel = f
	t.windy = is_windy
	return t


func _ready() -> void:
	rng.randomize()
	_serial += 1
	serial = _serial
	name = "PlantedTorch%d" % serial
	display_name = "火把"
	collision_layer = LAYER_INTERACT                  # 只让射线找到，不挡路
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.35, 1.4, 0.35)
	cs.shape = bs
	cs.position.y = 0.7
	add_child(cs)
	visual = TorchHand.make_visual(1)                    # 插着的只要一片火苗（一排十几支，绘制调用省一半）
	visual.position = Vector3(0, 0.62, 0)                # 握把那截插进雪里
	visual.rotation.x = deg_to_rad(-6.0)
	visual.scale = Vector3.ONE * 1.25
	add_child(visual)
	light = OmniLight3D.new()
	light.light_color = Color("ff9a4a")
	light.light_energy = 1.3
	light.omni_range = 6.0
	light.omni_attenuation = 1.4
	light.position = Vector3(0, 1.5, 0)
	light.distance_fade_enabled = true
	light.distance_fade_begin = 40.0
	light.distance_fade_length = 10.0
	add_child(light)
	set_meta("radius", TorchHand.RADIUS)
	set_meta("no_warm", true)
	add_to_group("planted_torch")
	set_lit(lit)


func verb_now() -> String:
	return "拔起" if lit else "点着"


func prompt() -> String:
	return "%s · %s" % [verb_now(), "火把" if lit else "灭了的火把"]


func can_interact() -> bool:
	return fuel > 0.0


func interact(who: FpController) -> Dictionary:
	var hand: TorchHand = who.torch if who else null
	if hand == null:
		return {}
	if lit:
		if hand.held():
			return {"kind": "torch", "toast": "手里已经拿着火把了。"}
		hand.take_from_ground(fuel)
		collision_layer = 0
		remove_from_group("light_source")
		remove_from_group("planted_torch")
		queue_free()
		_budget.call_deferred(get_tree())
		return {"kind": "torch", "name": "火把", "toast": "拔起火把"}
	if hand.lit():
		set_lit(true)
		return {"kind": "torch", "name": "火把", "toast": "点着了"}
	return {"kind": "torch", "toast": "得拿着点着的火把才能点。"}


func set_lit(on: bool) -> void:
	lit = on
	TorchHand.set_lit(visual, on)
	if on:
		add_to_group("light_source")
	elif is_in_group("light_source"):
		remove_from_group("light_source")
	if is_inside_tree():
		_budget(get_tree())


func blow_out() -> void:
	if lit:
		set_lit(false)


func _physics_process(delta: float) -> void:
	if burnt_left >= 0.0:
		burnt_left -= delta
		if burnt_left < 0.0:
			queue_free()
		return
	if not lit:
		return
	fuel -= delta
	if fuel <= 0.0:
		fuel = 0.0
		set_lit(false)
		display_name = "烧完的火把"
		burnt_left = BURNT_FREE
		return
	if windy and rng.randf() < BLOW * delta:
		blow_out()
	elif light.visible and not Settings.reduced_motion:
		var t := Time.get_ticks_msec() * 0.001 + serial * 1.7
		light.light_energy = 1.3 * (1.0 + sin(t * 8.7) * 0.07 + sin(t * 19.3 + 0.4) * 0.05)


## 亮着的里面最新插下的 max_lights 支带实时光源
static func _budget(tree: SceneTree) -> void:
	if tree == null:
		return
	var on := []
	for n in tree.get_nodes_in_group("planted_torch"):
		var t := n as PlantedTorch
		if t and not t.is_queued_for_deletion():
			if t.lit:
				on.append(t)
			else:
				t.light.visible = false
	on.sort_custom(func(a, b): return a.serial > b.serial)
	for i in on.size():
		(on[i] as PlantedTorch).light.visible = i < max_lights


## 现在亮着的插地火把
static func lit_count(tree: SceneTree) -> int:
	return tree.get_nodes_in_group("planted_torch").filter(func(t): return t.lit and not t.is_queued_for_deletion()).size()
