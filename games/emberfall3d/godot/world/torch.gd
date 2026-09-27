class_name Torch
extends Node3D
## 火把（ART.md 第六、七节）：墙上的铁托架与火把（PropModels「torch」，2.6 之七）+ 发光火苗（「torch_flame」：主火舌 + 两条小火舌，
## 高亮度自发光、配合环境泛光，每帧伸缩摇曳、慢慢转）+ 光晕贴片（加法混合）+ 闪烁点光源。
## 挂在墙上时节点的 +Z 朝外（墙面在身后 0.12 米）；mounted = false 时只有火苗（篝火用）。
## 点光源不投阴影（见 set_quality）；low 时光照范围略小。

var mounted := true               # 在 add_child 之前设置
var model: MeshInstance3D         # 托架 + 火把（mounted 时才有）
var light: OmniLight3D
var flame: MeshInstance3D
var halo: Sprite3D
var energy := 1.9
var _t := 0.0


func _ready() -> void:
	_t = randf() * 10.0
	if mounted:
		model = PropModels.instance("torch")
		# 火把自己的托架和火苗紧贴着点光源，高画质开点光源阴影时会把大半面墙遮成一片黑、只剩一块硬边的亮斑（2.6 实测），所以不投影
		model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(model)
	flame = MeshInstance3D.new()
	flame.name = "Flame"
	flame.mesh = PropModels.get_model("torch_flame").mesh
	flame.position = Vector3(0, -0.04, 0.02) if mounted else Vector3(0, -0.2, 0)     # 挂墙：坐在火把头上；篝火：从柴堆中间冒出来
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(1.0, 0.55, 0.18)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.5, 0.15)
	fm.emission_energy_multiplier = 5.0
	flame.material_override = fm
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flame)
	# 光晕：加法混合的广告牌贴片，火把周围一圈暖光（便宜的「光」，低画质也保留）
	halo = Sprite3D.new()
	halo.texture = Look.radial_texture()
	halo.pixel_size = 0.03
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hm.albedo_texture = Look.radial_texture()
	hm.albedo_color = Color(1.0, 0.5, 0.18, 0.5)
	hm.no_depth_test = false
	hm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	halo.material_override = hm
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.58, 0.25)
	light.light_energy = energy
	light.omni_range = 8.0
	light.omni_attenuation = 1.4
	light.position.y = 0.2
	add_child(light)


func set_quality(tier: String) -> void:
	# 点光源阴影（原先高画质开）在兼容渲染器里把火把所在的墙切成一块硬边亮斑（2.6 实测：立方体 / 双抛物面两种模式、加大偏移都一样），
	# 所以三档都不开；高画质仍有月光阴影和抗锯齿
	light.shadow_enabled = false
	light.omni_range = 6.5 if tier == "low" else 8.0


func _process(delta: float) -> void:
	_t += delta
	var f := sin(_t * 11.0) * 0.1 + sin(_t * 7.3) * 0.07 + sin(_t * 23.0) * 0.03
	light.light_energy = energy * (1.0 + f)
	flame.scale = Vector3(1.0 - f * 0.5, 1.0 + f * 0.9, 1.0 - f * 0.5)
	flame.rotation = Vector3(f * 0.25, _t * 1.3, -f * 0.3)
	(halo.material_override as StandardMaterial3D).albedo_color.a = 0.45 + f
