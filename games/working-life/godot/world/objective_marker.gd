class_name ObjectiveMarker
extends Node3D
## 引导标记：当前追踪任务目标处的一道霓虹光柱 + 浮动箭头与距离（隔着楼也能看到）。
## 每 0.4 秒重新计算一次目标，不逐帧查询任务系统。可以在设置里关掉。

var target_pos := Vector3.ZERO
var target_name := ""
var has_target := false
var _arrow: MeshInstance3D
var _beam: MeshInstance3D
var _label: Label3D
var _time := 0.0
var _refresh := 0.0


func _ready() -> void:
	GameManager.register("objective_marker", self)
	_beam = MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.6
	bm.bottom_radius = 0.6
	bm.height = 60.0
	bm.radial_segments = 8
	bm.cap_top = false
	bm.cap_bottom = false
	_beam.mesh = bm
	_beam.material_override = Mats.marker(Color(1.0, 0.82, 0.25, 0.22))
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	_arrow = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.45
	cm.bottom_radius = 0.0
	cm.height = 0.8
	cm.radial_segments = 4
	_arrow.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.82, 0.25, 0.95)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = 10
	_arrow.material_override = mat
	_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arrow)
	_label = Label3D.new()
	_label.font = UIKit.font()
	_label.font_size = 40
	_label.outline_size = 10
	_label.modulate = Color(1.0, 0.9, 0.5)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0009
	_label.render_priority = 11
	_label.outline_render_priority = 10
	add_child(_label)


func _resolve() -> void:
	has_target = false
	var t := QuestManager.objective_target()
	if t.is_empty():
		return
	match String(t.get("kind", "")):
		"location":
			var id := String(t.get("id", ""))
			var ln := GameManager.lookup("loc:" + id) as LocationNode
			if ln == null:
				return
			target_pos = ln.front_position()
			target_name = DataDB.location_name(id)
			if id == "park" and QuestManager.is_active("m7_rooftop"):
				var sp := GameManager.lookup("point:park:rooftop") as Node3D
				if sp != null:
					target_pos = sp.global_position
					target_name = "中央公园观景台"
			has_target = true
		"npc":
			var id2 := String(t.get("id", ""))
			var n := GameManager.lookup("npc:" + id2) as NPC
			target_name = DataDB.npc_name(id2)
			if n != null and not n.at_home:
				target_pos = n.global_position
				has_target = true
			else:
				target_name += "（现在不在外面）"
		"spawn":
			var ln2 := GameManager.lookup("loc:" + String(t.get("id", ""))) as LocationNode
			if ln2 != null:
				var p: Array = t.get("pos", [0, 0])
				target_pos = BuildingKit.xf(ln2.frame, float(p[0]), 0, float(p[1]))
				target_name = "任务物品"
				has_target = true


func _process(delta: float) -> void:
	_time += delta
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.4
		if GameManager.playing:
			_resolve()
		else:
			has_target = false
	var p := GameManager.player
	if not GameManager.playing or p == null or not has_target or not bool(SettingsManager.get_v("show_marker", true)):
		visible = false
		return
	global_position = target_pos
	var dist := Vector2(target_pos.x - p.global_position.x, target_pos.z - p.global_position.z).length()
	visible = dist > 3.0
	_beam.position = Vector3(0, 30.0, 0)
	_beam.visible = dist > 12.0
	_arrow.position = Vector3(0, 3.2 + sin(_time * 3.0) * 0.15, 0)
	_arrow.rotation.y = _time * 1.5
	_label.text = "%s · %d 米" % [target_name, int(dist)]
	_label.position = Vector3(0, 4.1, 0)
