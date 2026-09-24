class_name NPC
extends CharacterBody3D
## 有名字的 NPC：按日程在城市里移动（NavigationAgent3D 寻路），到点上班、下班回家、偶尔闲逛。
## 远离玩家（80 米外）时不逐帧走路，直接出现在目的地，省 CPU。
## 玩家按 E 交谈时停下并转身面向玩家。

const WALK_SPEED := 2.3
const FAR_DIST := 80.0

var npc_id := ""
var data: Dictionary = {}
var model: CharacterModel
var agent: NavigationAgent3D
var anim: AnimationController
var talk: NpcTalk
var at_home := false
var talking := false
## 路径：先走到地点门口（导航），再直线走到具体站位
var _final := Vector3.ZERO
var _final_yaw := 0.0
var _stage := 0   # 0 到达 1 导航中 2 直线进入
var _hide_on_arrive := false
var _idle_t := 0.0


func setup(id: String) -> void:
	npc_id = id
	data = DataDB.npc(id)
	name = "NPC_" + id
	collision_layer = 4
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0, 0.85, 0)
	add_child(cs)
	model = CharacterModel.new()
	model.apply_look(data.get("look", {}))
	model.accent_color = Color.from_hsv(float(id.hash() % 360) / 360.0, 0.8, 1.0)
	add_child(model)
	anim = AnimationController.new(model)
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 1.0
	agent.target_desired_distance = 1.2
	agent.avoidance_enabled = false
	add_child(agent)
	talk = NpcTalk.new()
	talk.npc = self
	add_child(talk)
	talk.setup_shape()
	var tag := Label3D.new()
	tag.text = String(data.get("name", id))
	tag.font = load(BuildingKit.FONT_PATH)
	tag.font_size = 40
	tag.pixel_size = 0.008
	tag.position = Vector3(0, 2.15, 0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(1, 0.95, 0.7)
	tag.outline_size = 8
	tag.visibility_range_end = 18.0
	tag.no_depth_test = false
	add_child(tag)
	NPCManager.register_node(id, self)
	GameManager.register("npc:" + id, self)


func _ready() -> void:
	if model != null and not model._built:
		model.build()


func go_to_spot(spot: String, instant := false) -> void:
	if talking and not instant:
		return
	var target := Vector3.ZERO
	var front := Vector3.ZERO
	_hide_on_arrive = spot == ""
	if spot == "":
		var home_loc := "old_street" if npc_id in ["laoma", "daliu"] else "apartment"
		if npc_id == "laoli":
			home_loc = "shared_house"
		var ln := GameManager.lookup("loc:" + home_loc) as LocationNode
		if ln == null:
			return
		front = ln.front_position()
		target = front
		_final_yaw = 0.0
	else:
		var parts := spot.split(".")
		var ln2 := GameManager.lookup("loc:" + parts[0]) as LocationNode
		if ln2 == null:
			return
		front = ln2.front_position()
		target = ln2.spot_position(parts[1] if parts.size() > 1 else "front")
		# 站位面朝建筑正门方向（柜台后面的人面向顾客）
		_final_yaw = float(ln2.frame.get("yaw", 0.0)) + PI
	_final = target
	if at_home and not _hide_on_arrive:
		# 从家里出门：直接出现在家门口
		at_home = false
		visible = true
		talk.monitorable = true
	if instant or _far_from_player() or not visible:
		talking = false
		_arrive_now()
		return
	_stage = 1
	agent.target_position = front


func _far_from_player() -> bool:
	var p := GameManager.player
	if p == null:
		return true
	return p.global_position.distance_to(global_position) > FAR_DIST and p.global_position.distance_to(_final) > FAR_DIST


func _arrive_now() -> void:
	global_position = _final
	rotation.y = _final_yaw
	_stage = 0
	velocity = Vector3.ZERO
	_set_home(_hide_on_arrive)


func _set_home(h: bool) -> void:
	at_home = h
	visible = not h
	talk.monitorable = not h
	collision_layer = 0 if h else 4


func _physics_process(delta: float) -> void:
	if talking:
		var p := GameManager.player
		if p != null:
			var to := p.global_position - global_position
			rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), clampf(delta * 8.0, 0.0, 1.0))
		anim.update(delta, 0.0)
		return
	if _stage == 0:
		_idle_t += delta
		anim.update(delta, 0.0)
		rotation.y = lerp_angle(rotation.y, _final_yaw + sin(_idle_t * 0.3) * 0.25, clampf(delta * 3.0, 0.0, 1.0))
		return
	if _far_from_player():
		_arrive_now()
		return
	var next := Vector3.ZERO
	if _stage == 1:
		if agent.is_navigation_finished():
			_stage = 2
			return
		next = agent.get_next_path_position()
	else:
		next = _final
		if Vector2(global_position.x - _final.x, global_position.z - _final.z).length() < 0.35:
			_arrive_now()
			return
	var to2 := next - global_position
	to2.y = 0.0
	var dist := to2.length()
	if dist > 0.05:
		var dir := to2 / dist
		var v := dir * WALK_SPEED
		global_position += v * delta
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(delta * 8.0, 0.0, 1.0))
		anim.update(delta, WALK_SPEED)
	else:
		anim.update(delta, 0.0)


func begin_talk() -> void:
	talking = true


func end_talk() -> void:
	talking = false
	rotation.y = _final_yaw if _stage == 0 else rotation.y
