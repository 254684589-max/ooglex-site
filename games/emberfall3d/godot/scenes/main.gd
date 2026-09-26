extends Node3D
## 阶段 1 灰盒场景：工程与网页导出（1.1）、斜俯视相机（1.2）、点击移动 / 摇杆 / 导航网格（1.3）、
## 战斗手感（1.4：烬卫断誓斩 + 焚地践踏，训练木桩）。
## 画面里的所有模型都是代码生成的**占位几何体**，不代表最终美术（ART.md）。

const PITCH_DEG := 55.0
const WORLD_MASK := 1 | IsoCamera.OCCLUDER_LAYER   # 墙体与柱子：世界碰撞（第 1 层）+ 遮挡视线（第 2 层）

var auto_pack_test := true
var run_nav_bench := true
var level: NavigationRegion3D
var hero: Player
var touch: TouchControls
var dummies: Array[TrainingDummy] = []
var res_bar: ProgressBar
var res_label: Label
var btn_attack: Button
var btn_stomp: Button
var torch_light: OmniLight3D
var camera: IsoCamera
var info: Label
var pack_label: Label
var pack_state := "章节包：未测试"
var nav_state := ""
var nav_bake_ms := 0.0
var t := 0.0


func _ready() -> void:
	_build_world()
	_build_ui()
	PackLoader.pack_loaded.connect(_on_pack_loaded)
	print("EF_READY renderer=%s web=%s" % [RenderingServer.get_current_rendering_method(), OS.has_feature("web")])
	print("EF_NAV_BAKE room_ms=%.1f polygons=%d" % [nav_bake_ms, level.navigation_mesh.get_polygon_count()])
	if auto_pack_test and OS.has_feature("web"):
		pack_state = "章节包：下载中……"
		_refresh_labels()
		PackLoader.load_chapter("ch_test")
	# 给网页冒烟测试用：第一个木桩在屏幕上的位置
	await get_tree().process_frame
	# unproject_position 返回的是缩放后的视口坐标；换算成窗口像素（界面缩放 ≠ 1 时两者不同）
	var sp := camera.unproject_position(dummies[0].global_position + Vector3(0, 1.0, 0)) * get_window().content_scale_factor
	print("EF_DUMMY_SCREEN x=%d y=%d" % [sp.x, sp.y])
	if run_nav_bench and OS.has_feature("web"):
		# 等两帧再跑，避免和首帧渲染抢时间；结果打到控制台与左下角
		await get_tree().process_frame
		await get_tree().process_frame
		var b := NavBuilder.bench_dungeon(7, 0.25)
		nav_state = "整层地下城导航烘焙 %.0f 毫秒（%d 个多边形）" % [b.ms, b.polygons]
		print("EF_NAV_BENCH ms=%.1f polygons=%d floor_tiles=%d wall_tiles=%d cell=%.2f" % [b.ms, b.polygons, b.floor_tiles, b.wall_tiles, b.cell_size])
		_refresh_labels()


func _process(delta: float) -> void:
	t += delta
	if torch_light:
		torch_light.light_energy = 2.2 + sin(t * 11.0) * 0.18 + sin(t * 7.3) * 0.12
	if res_bar and hero:
		var k: EmberguardKit = hero.kit
		res_bar.value = k.resource
		var cd: float = k.cooldowns.get("scorch_stomp", 0.0)
		var cost: int = Balance.skill("scorch_stomp").cost
		res_label.text = "誓火 %d / %d　焚地践踏：%s" % [k.resource, k.resource_max, ("冷却 %.1f 秒" % cd) if cd > 0.0 else ("可用" if k.resource >= cost else "誓火不足（需要 %d）" % cost)]
		if btn_stomp:
			btn_stomp.disabled = not k.can_cast("scorch_stomp")


func _on_pack_loaded(id: String, ok: bool, ms: int, detail: String) -> void:
	if ok:
		var scene := load("res://packs/%s/marker.tscn" % id) as PackedScene
		if scene:
			var inst := scene.instantiate()
			inst.position = Vector3(3.5, 0, -2.5)
			add_child(inst)
			pack_state = "章节包 %s：加载成功，用时 %d 毫秒" % [id, ms]
			print("EF_PACK_OK id=%s ms=%d" % [id, ms])
		else:
			pack_state = "章节包 %s：已挂载，但找不到场景" % id
			print("EF_PACK_FAIL id=%s reason=scene_missing" % id)
	else:
		pack_state = "章节包 %s：加载失败（%s）" % [id, detail]
		print("EF_PACK_FAIL id=%s reason=%s" % [id, detail])
	_refresh_labels()


# ---------------- 场景 ----------------

func _mat(c: Color, emissive: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emissive
	return m


func _box(size: Vector3, pos: Vector3, c: Color, solid := true) -> MeshInstance3D:
	## 占位方块。solid = true 时带静态碰撞体（世界 + 遮挡层），挂在导航区域下参与烘焙；
	## 相机会在它挡住主角时把它变半透明。
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(c)
	if not solid:
		mi.position = pos
		add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.collision_layer = WORLD_MASK
	body.collision_mask = 0
	body.position = pos
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	body.add_child(mi)
	body.set_meta("fade_meshes", [mi])
	level.add_child(body)
	return mi


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.03, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.26, 0.24, 0.34)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.08, 0.1)
	env.fog_density = 0.02
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.6, 0.85)
	moon.light_energy = 0.35
	moon.shadow_enabled = true
	moon.rotation_degrees = Vector3(-60, 30, 0)
	add_child(moon)

	# 关卡几何挂在导航区域下，运行时烘焙导航网格
	level = NavBuilder.make_region()
	add_child(level)

	# 地面（占位）：地面层碰撞只用于点击拾取与导航解析，主角不与它碰撞（平面移动）
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(28, 28)
	ground.mesh = plane
	ground.material_override = _mat(Color(0.23, 0.21, 0.19))
	var gbody := StaticBody3D.new()
	gbody.collision_layer = Player.LAYER_GROUND
	gbody.collision_mask = 0
	var gshape := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(28, 0.2, 28)
	gshape.shape = gbox
	gshape.position.y = -0.1
	gbody.add_child(gshape)
	gbody.add_child(ground)
	level.add_child(gbody)

	# 一间有缺口的灰盒房间 + 石柱（占位）。墙高 3.2 米（约主角身高 1.8 倍）
	var wall := Color(0.36, 0.33, 0.3)
	_box(Vector3(12, 3.2, 0.6), Vector3(0, 1.6, -6), wall)
	_box(Vector3(0.6, 3.2, 12), Vector3(-6, 1.6, 0), wall)
	_box(Vector3(0.6, 3.2, 5), Vector3(6, 1.6, -3.5), wall)
	_box(Vector3(5, 3.2, 0.6), Vector3(-3.5, 1.6, 6), wall)
	for p in [Vector3(-3, 0, -3), Vector3(3, 0, 3), Vector3(-3, 0, 3)]:
		_box(Vector3(0.7, 3.0, 0.7), p + Vector3(0, 1.5, 0), Color(0.42, 0.38, 0.34))
	# 房间外的几块矮石，让门外也有东西可以绕
	_box(Vector3(2.0, 1.0, 1.2), Vector3(8.5, 0.5, 4.0), Color(0.33, 0.3, 0.28))
	_box(Vector3(1.2, 1.0, 2.4), Vector3(3.0, 0.5, 9.0), Color(0.33, 0.3, 0.28))

	nav_bake_ms = NavBuilder.bake(level)

	# 火把（占位）：柱 + 发光球 + 闪烁点光源
	_box(Vector3(0.16, 1.6, 0.16), Vector3(-5.4, 0.8, -5.4), Color(0.3, 0.2, 0.12), false)
	var flame := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.16
	sph.height = 0.32
	flame.mesh = sph
	flame.material_override = _mat(Color(1.0, 0.55, 0.16), 3.0)
	flame.position = Vector3(-5.4, 1.7, -5.4)
	add_child(flame)
	torch_light = OmniLight3D.new()
	torch_light.light_color = Color(1.0, 0.58, 0.25)
	torch_light.omni_range = 7.0
	torch_light.position = Vector3(-5.4, 1.9, -5.4)
	add_child(torch_light)

	# 训练木桩（占位敌人）：房间里两个挨着（测试范围技能）、门外一个
	for p in [Vector3(2.2, 0, -1.2), Vector3(3.0, 0, 0.3), Vector3(-1.5, 0, 9.5)]:
		var d := TrainingDummy.new()
		add_child(d)
		d.global_position = p
		d.home = p
		dummies.append(d)

	# 玩家（占位外观）与斜俯视相机
	hero = Player.new()
	add_child(hero)
	camera = IsoCamera.new()
	camera.pitch_deg = PITCH_DEG
	camera.target = hero
	add_child(camera)
	hero.camera = camera


# ---------------- 界面 ----------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	# 左上角一列：说明文字 → 职业资源条 →（手机上）状态文字，按内容高度往下排，互不重叠
	var top := VBoxContainer.new()
	top.anchor_right = 1.0
	top.offset_left = 16
	top.offset_top = 12
	top.offset_right = -16
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(top)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 18)
	info.add_theme_color_override("font_color", Color(0.91, 0.52, 0.23))
	var how := "手机：左下摇杆移动；点木桩或按「攻击」打，「践踏」放技能" if DisplayServer.is_touchscreen_available() else "点地面移动；点木桩攻击（按住连打）；右键或 1 键：焚地践踏；WASD 移动；滚轮缩放"
	info.text = "余烬陷落 EMBERFALL · 大作版灰盒原型（阶段 1.4 战斗手感）\n画面全部为占位几何体，不代表最终美术。" + how
	top.add_child(info)
	pack_label = Label.new()
	pack_label.anchor_top = 1.0
	pack_label.anchor_bottom = 1.0
	pack_label.anchor_right = 1.0
	pack_label.offset_left = 16
	pack_label.offset_right = -16
	pack_label.offset_top = -56
	pack_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pack_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pack_label.add_theme_font_size_override("font_size", 14)
	pack_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))
	layer.add_child(pack_label)
	# 职业资源条（占位；正式界面按 ART.md 第五节做成环绕技能栏的火焰）
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(box)
	res_bar = ProgressBar.new()
	res_bar.custom_minimum_size = Vector2(220, 14)
	res_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	res_bar.max_value = hero.kit.resource_max
	res_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.91, 0.52, 0.23)
	res_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.07, 0.05, 0.8)
	res_bar.add_theme_stylebox_override("background", bg)
	box.add_child(res_bar)
	res_label = Label.new()
	res_label.add_theme_font_size_override("font_size", 14)
	res_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.7))
	box.add_child(res_label)
	touch = TouchControls.new()
	layer.add_child(touch)
	if touch.visible:
		btn_attack = _touch_button(layer, "攻击", Vector2(-130, -150), 96)
		btn_stomp = _touch_button(layer, "践踏", Vector2(-230, -110), 72)
		btn_attack.button_down.connect(func(): hero.attack_nearest(true))
		btn_attack.button_up.connect(func(): hero.attack_nearest(false))
		btn_stomp.pressed.connect(func(): hero.cast_skill("scorch_stomp"))
		hero.ui_blockers = [btn_attack, btn_stomp]
	touch.changed.connect(func(v: Vector2): hero.stick = v)
	if touch.visible:
		# 手机上底部有摇杆和按钮：状态文字挪到左上角那一列的最后
		pack_label.get_parent().remove_child(pack_label)
		pack_label.anchor_top = 0.0
		pack_label.anchor_bottom = 0.0
		pack_label.anchor_right = 0.0
		pack_label.offset_left = 0
		pack_label.offset_right = 0
		pack_label.offset_top = 0
		pack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		top.add_child(pack_label)
	_refresh_labels()


func _touch_button(layer: CanvasLayer, text: String, offset: Vector2, size: float) -> Button:
	var b := Button.new()
	b.text = text
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = offset.x
	b.offset_top = offset.y
	b.offset_right = offset.x + size
	b.offset_bottom = offset.y + size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18 if size > 80 else 15)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.35, 0.16, 0.08, 0.75)
	sb.border_color = Color(0.79, 0.64, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(size / 2))
	b.add_theme_stylebox_override("normal", sb)
	var sp := sb.duplicate()
	sp.bg_color = Color(0.6, 0.28, 0.1, 0.9)
	b.add_theme_stylebox_override("pressed", sp)
	b.add_theme_stylebox_override("hover", sb)
	var sd := sb.duplicate()
	sd.bg_color = Color(0.15, 0.12, 0.1, 0.6)
	b.add_theme_stylebox_override("disabled", sd)
	layer.add_child(b)
	return b


func _refresh_labels() -> void:
	if pack_label:
		var lines := [pack_state, "房间导航烘焙 %.0f 毫秒" % nav_bake_ms]
		if nav_state != "":
			lines.append(nav_state)
		lines.append("渲染器：%s" % RenderingServer.get_current_rendering_method())
		pack_label.text = "　·　".join(lines)
