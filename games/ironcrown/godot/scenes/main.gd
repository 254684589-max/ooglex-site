extends Node3D
## 《铁冠之争》主场景（阶段 1.4：霜渡镇主街）。
## 默认是霜渡镇主街（world/frostford.gd）；网页 ?test=1 或 use_test_range = true 打开灰盒测试场（台阶、斜坡、窄门、矮洞、交互）。
## 网页参数：?q=low|medium|high 强制画质档；?view=0|1|2 从固定机位开始（截图用）；?perf=1 两秒后打出一次性能统计（IC_PERF）。
## 人物仍是占位胶囊，界面上明确标注。
##
## 鼠标：电脑上点击画面锁定指针（浏览器只允许在点击后锁定）；Esc 或浏览器释放锁定时打开暂停菜单，
## 不会自己把鼠标抢回来（TECH.md 4.1）。触屏设备不锁定鼠标，用 TouchControls。

const FOG_COLOR := Color("22344a")              # 夜空与远雾（ART.md 第四节 #1C2A3A 提亮一点，远处是「雾」而不是「黑」）
const AMBIENT_COLOR := Color("6f8faf")          # 月光 / 环境光
const HINT_DESKTOP := "点击画面开始 · WASD 移动 · 鼠标转视角 · E 交互 · Shift 跑 · C 蹲下 · 空格 跳 · Esc 暂停"
const HINT_TOUCH := "左半屏拖动走路（推到底是跑）· 右半屏拖动转视角 · 对准东西时点右下角的交互按钮"
const HINT_SECONDS := 8.0

@export var use_test_range := false

var moon: DirectionalLight3D
var quality := ""

var env: Environment
var world: Node3D
var player: FpController
var camera: Camera3D
var hud: Hud
var touch: TouchControls
var pause_menu: PauseMenu
var touch_mode := false
var spawn := Vector3.ZERO
var yaw0 := 0.0
var moved_logged := false
var look_logged := false
var lock_seen := false          # 指针真的锁定过（锁定失败时不要误开暂停菜单）
var hint_left := HINT_SECONDS
var started := false
var inventory: Array = []       # 捡到的物品编号（背包界面在 2.4）
var use_screen_logged := false


func _ready() -> void:
	touch_mode = DisplayServer.is_touchscreen_available()
	if OS.has_feature("web"):
		if _query("test") == "1":
			use_test_range = true
		# 系统设置了「减少动态效果」：默认关掉镜头摆动（GDD.md 第四节）
		if str(JavaScriptBridge.eval("!!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches)", true)) == "true":
			Settings.reduced_motion = true
			Settings.head_bob = false
			print("IC_REDUCED_MOTION")
	_build_environment()
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	var t := TestRange.build(world) if use_test_range else Frostford.build(world, Settings.reduced_motion)
	player = FpController.new()
	player.name = "Player"
	add_child(player)
	player.global_transform = t
	camera = player.camera
	camera.make_current()
	var view := _query("view")
	if not use_test_range and view.is_valid_int() and int(view) >= 0 and int(view) < Frostford.VIEWS.size():
		set_view(int(view))
	spawn = player.global_position
	yaw0 = player.yaw_deg()
	_build_ui()
	var q := _query("q")
	apply_quality(q if q in Look.TIERS else Look.default_tier())
	print("IC_READY renderer=%s web=%s scene=%s touch=%s quality=%s size=%s" % [
		ProjectSettings.get_setting("rendering/renderer/rendering_method"), OS.has_feature("web"),
		"test_range" if use_test_range else "frostford", touch_mode, quality, get_viewport().get_visible_rect().size])
	if _query("perf") == "1":
		await get_tree().create_timer(2.0).timeout
		await perf_probe()
		return
	# 给网页冒烟测试用：「菜单」按钮在窗口里的位置（窗口像素，已乘界面缩放）
	await get_tree().process_frame
	var c := hud.menu_btn.get_global_rect().get_center() * get_tree().root.content_scale_factor
	print("IC_MENU_SCREEN x=%d y=%d" % [c.x, c.y])


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = FOG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT_COLOR
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.fog_enabled = true
	env.fog_light_color = FOG_COLOR
	if use_test_range:
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_density = 0.045
	else:
		# 霜渡镇：深度雾从 3 米开始、50 米处完全吞没（ART.md 第三节「雾是构图工具」），再加一点贴地的高度雾
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_depth_begin = 2.0
		env.fog_depth_end = 36.0
		env.fog_depth_curve = 0.85
		env.fog_density = 1.0
		env.fog_height = 0.8
		env.fog_height_density = 0.25
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	moon = DirectionalLight3D.new()
	moon.light_color = Color("8fb0d6")
	moon.light_energy = 0.32
	moon.rotation_degrees = Vector3(-38, 150, 0)     # 从背后偏左照过来，给房子勾一道冷色轮廓
	moon.directional_shadow_max_distance = 25.0
	add_child(moon)


func _query(key: String) -> String:
	if not OS.has_feature("web"):
		return ""
	return str(JavaScriptBridge.eval("(new URLSearchParams(window.location.search)).get('%s') || ''" % key, true))


## 从固定机位开始（Frostford.VIEWS；截图与冒烟测试用）
func set_view(i: int) -> void:
	var v: Array = Frostford.VIEWS[i]
	player.global_position = v[0]
	player.rotation.y = deg_to_rad(v[1])
	player.pitch = v[2]
	player.head.rotation.x = deg_to_rad(v[2])


## 画质分档（TECH.md 第五节）：低 = 0.75 倍分辨率、无阴影、无泛光、无各向异性过滤、雾带减半；
## 中 = 原分辨率、月光阴影（1 段）、泛光；高 = 再加 2 倍抗锯齿、阴影 2 段
func apply_quality(tier: String) -> void:
	quality = tier
	var vp := get_viewport()
	vp.scaling_3d_scale = 0.75 if tier == "low" else 1.0
	vp.msaa_3d = Viewport.MSAA_2X if tier == "high" else Viewport.MSAA_DISABLED
	moon.shadow_enabled = tier != "low"
	# 默认 4 段级联阴影会把场景重画 4 遍（1.4 实测：绘制调用 154 → 393）；中档 1 段、高档 2 段
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if tier == "high" else DirectionalLight3D.SHADOW_ORTHOGONAL
	env.glow_enabled = tier != "low"
	Look.set_anisotropic(tier != "low")
	for f in get_tree().get_nodes_in_group("fog_band"):
		f.visible = tier != "low" or int(f.get_meta("fog_index", 0)) % 2 == 0


## 性能统计（TECH.md 第五节）：在当前机位连续采样 1 秒
func perf_probe() -> Dictionary:
	var dc := 0.0
	var prim := 0.0
	var obj := 0.0
	var n := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1000:
		await get_tree().process_frame
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		obj += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		n += 1
	var r := {"draw_calls": dc / n, "primitives": prim / n, "objects": obj / n, "fps": n, "quality": quality,
		"occlusion": get_viewport().use_occlusion_culling}
	print("IC_PERF draw_calls=%.0f primitives=%.0f objects=%.0f fps=%d quality=%s occlusion=%s" % [r.draw_calls, r.primitives, r.objects, r.fps, quality, r.occlusion])
	return r


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var vignette := ColorRect.new()
	vignette.name = "Vignette"
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = load("res://shaders/vignette.gdshader")
	vignette.material = vm
	layer.add_child(vignette)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud = Hud.new()
	layer.add_child(hud)
	hud.set_hint(HINT_TOUCH if touch_mode else HINT_DESKTOP)
	hud.menu_pressed.connect(open_pause)
	if touch_mode:
		hud.key_hint = ""
	player.interactor.target_changed.connect(_on_target_changed)
	player.interactor.interacted.connect(_on_interacted)
	touch = TouchControls.new()
	touch.player = player
	layer.add_child(touch)
	pause_menu = PauseMenu.new()
	layer.add_child(pause_menu)
	pause_menu.resume_requested.connect(close_pause)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		open_pause()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact"):
		player.interactor.use()
		get_viewport().set_input_as_handled()
		return
	# 触屏产生的模拟鼠标事件（DEVICE_ID_EMULATION）不算鼠标（余烬陷落 TECH.md 4.1 的经验）
	if event is InputEventMouseButton and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION and not touch_mode:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_start()
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			player.look(event.relative)


func _on_target_changed(target: Interactable) -> void:
	hud.show_prompt(target.prompt() if target else "")
	if target:
		print("IC_TARGET name=%s verb=%s" % [target.display_name, target.verb_now()])
		# 给网页冒烟测试用：触屏交互按钮在窗口里的位置
		if touch_mode and not use_screen_logged:
			use_screen_logged = true
			var c: Vector2 = touch.button_centers().get("interact", Vector2.ZERO) * get_tree().root.content_scale_factor
			print("IC_USE_SCREEN x=%d y=%d" % [c.x, c.y])


func _on_interacted(r: Dictionary) -> void:
	if r.is_empty():
		return
	if r.has("toast"):
		hud.toast(r.toast)
	if r.has("speech"):
		hud.say(r.speech)
	if r.get("kind") == "pickup":
		inventory.append(r.item)
	var t := player.interactor.target
	hud.show_prompt(t.prompt() if t else "")     # 门开了以后提示从「打开」变「关上」
	print("IC_INTERACT kind=%s name=%s" % [r.get("kind", ""), r.get("name", "")])


func _start() -> void:
	if not started:
		started = true
		hint_left = minf(hint_left, 3.0)


func open_pause() -> void:
	if get_tree().paused:
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	lock_seen = false
	pause_menu.open()
	print("IC_PAUSE open=true")


func close_pause() -> void:
	pause_menu.hide()
	get_tree().paused = false
	if not touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED   # 「继续」按钮是一次点击，浏览器允许重新锁定
	print("IC_PAUSE open=false")


func _process(delta: float) -> void:
	# 浏览器用 Esc 释放指针锁定时，游戏收不到 Esc：发现锁定没了就打开暂停菜单
	var locked := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if locked:
		lock_seen = true
	elif lock_seen:
		lock_seen = false
		open_pause()
	if hint_left > 0.0:
		hint_left -= delta
		if hint_left <= 0.0:
			hud.set_hint("")
	var pos := player.global_position
	if not moved_logged and Vector2(pos.x - spawn.x, pos.z - spawn.z).length() > 1.0:
		moved_logged = true
		_start()
		print("IC_MOVED d=%.2f" % Vector2(pos.x - spawn.x, pos.z - spawn.z).length())
	if not look_logged and absf(angle_difference(deg_to_rad(player.yaw_deg()), deg_to_rad(yaw0))) > deg_to_rad(15.0):
		look_logged = true
		print("IC_LOOK yaw=%.1f" % player.yaw_deg())
