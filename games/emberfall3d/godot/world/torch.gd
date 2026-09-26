class_name Torch
extends Node3D
## 火把（ART.md 第六、七节）：木柄 + 发光火苗（高亮度自发光，配合环境泛光）+ 光晕贴片（加法混合）+ 闪烁点光源。
## 画质 high 时点光源投射阴影；low 时光照范围略小。外观是程序生成的占位。

var light: OmniLight3D
var flame: MeshInstance3D
var halo: Sprite3D
var energy := 1.9
var _t := 0.0


func _ready() -> void:
	_t = randf() * 10.0
	var post := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.12, 0.5, 0.12)
	post.mesh = b
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.25, 0.16, 0.1)
	post.material_override = pm
	post.position.y = -0.3
	add_child(post)
	flame = MeshInstance3D.new()
	flame.mesh = LowPoly.sphere(0.13)
	flame.scale = Vector3(1, 1.6, 1)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(1.0, 0.55, 0.18)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.5, 0.15)
	fm.emission_energy_multiplier = 5.0
	flame.material_override = fm
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
	add_child(halo)
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.58, 0.25)
	light.light_energy = energy
	light.omni_range = 8.0
	light.omni_attenuation = 1.4
	light.position.y = 0.2
	add_child(light)


func set_quality(tier: String) -> void:
	light.shadow_enabled = tier == "high"
	light.omni_range = 6.5 if tier == "low" else 8.0


func _process(delta: float) -> void:
	_t += delta
	var f := sin(_t * 11.0) * 0.1 + sin(_t * 7.3) * 0.07 + sin(_t * 23.0) * 0.03
	light.light_energy = energy * (1.0 + f)
	flame.scale = Vector3(1.0 - f * 0.5, 1.6 + f * 1.5, 1.0 - f * 0.5)
	(halo.material_override as StandardMaterial3D).albedo_color.a = 0.45 + f
