class_name ObjectiveMarker
extends Node3D
## 引导标记：在当前目标（老王、材料堆、卸货区、食堂、床铺……）头顶显示一个
## 上下浮动的黄色箭头和距离，隔着墙也能看到。可以在设置里关掉。

var _arrow: MeshInstance3D
var _label: Label3D
var _time := 0.0
var _objective: Dictionary = {}
var _refresh := 0.0


func _ready() -> void:
	_arrow = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.34
	cm.bottom_radius = 0.0
	cm.height = 0.6
	cm.radial_segments = 4
	_arrow.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.8, 0.1, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = 10
	_arrow.material_override = mat
	_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arrow)
	_label = Label3D.new()
	_label.font_size = 40
	_label.pixel_size = 0.006
	_label.outline_size = 10
	_label.modulate = Color(1.0, 0.9, 0.4)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0009
	_label.render_priority = 11
	_label.outline_render_priority = 10
	add_child(_label)
	Events.objective_changed.connect(func(): _refresh = 0.0)


func current() -> Dictionary:
	return _objective


func _process(delta: float) -> void:
	_time += delta
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.4
		_objective = GameState.current_objective() if GameState.playing else {}
	var p := GameState.player
	var target_id := String(_objective.get("target", ""))
	var node: Node3D = GameState.lookup(target_id) if target_id != "" else null
	if not GameState.playing or p == null or node == null or not bool(GameState.settings.get("guide", true)):
		visible = false
		return
	var pos := node.global_position
	var height := 2.9
	if node is Interactable and not (node is NpcTalk):
		height = 3.3
	if node is NPC:
		height = 2.75
	global_position = pos + Vector3(0, height + sin(_time * 3.0) * 0.12, 0)
	var dist := Vector2(pos.x - p.global_position.x, pos.z - p.global_position.z).length()
	visible = dist > 2.2
	_label.text = "%d 米" % int(dist)
	_label.position = Vector3(0, 0.62, 0)
	_arrow.rotation.y = _time * 1.5
