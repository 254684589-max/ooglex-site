class_name SnowTracks
extends MultiMeshInstance3D
## 主角在雪里留下的脚印（路线图 5.3a；STORY.md 5.7「深雪……第一人称镜头下有脚印（只在近处）」）。
## 走过雪地（Surface「snow」「deep_snow」）每 0.72 米左右脚交替留一个；深雪里的印子大一点、深一点。
## 只留最近 COUNT 个（多实例循环覆盖最旧的），一次绘制调用；印子是一张软边椭圆贴图剪出来的小面片（alpha scissor，不排序）。

const COUNT := 70
const STRIDE := 0.72
const SNOW_KINDS := ["snow", "deep_snow"]

var player: FpController
var last := Vector3.INF
var next := 0
var left := true


static func make(p: FpController) -> SnowTracks:
	var t := SnowTracks.new()
	t.name = "SnowTracks"
	t.player = p
	t.top_level = true
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := PlaneMesh.new()
	q.size = Vector2(0.13, 0.28)
	q.material = _material()
	mm.mesh = q
	mm.instance_count = COUNT
	mm.visible_instance_count = 0
	t.multimesh = mm
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.visibility_range_end = 40.0
	return t


static func _material() -> StandardMaterial3D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 32
	tex.height = 32
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = Color("8d98aa")
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.45
	m.roughness = 0.95
	return m


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	if not (player.surface in SNOW_KINDS):
		last = Vector3.INF
		return
	if not player.is_on_floor():
		return
	var p := player.global_position
	if last == Vector3.INF:
		last = p
		return
	var step := Vector2(p.x - last.x, p.z - last.z)
	if step.length() < STRIDE:
		return
	var dir := step.normalized()
	last = p
	var side := Vector2(-dir.y, dir.x) * (0.12 if left else -0.12)
	left = not left
	var deep := player.surface == "deep_snow"
	var s := 1.25 if deep else 1.0
	var at := Vector3(p.x + side.x, p.y + 0.025, p.z + side.y)
	var yaw := atan2(dir.x, dir.y)
	multimesh.set_instance_transform(next, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, 1.0, s)), at))
	var shade := 0.82 if deep else 1.0
	multimesh.set_instance_color(next, Color(shade, shade, shade))
	next = (next + 1) % COUNT
	multimesh.visible_instance_count = mini(multimesh.visible_instance_count + 1, COUNT)
