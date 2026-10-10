class_name Daypart
extends RefCounted
## 时段（路线图 4.2；STORY.md 4.9、GDD.md 第九节）：清晨 / 白天 / 黄昏 / 夜四套光照、雾与天色，**按剧情切换**，不是自己走的时钟。
## 时段记在 GameState.daypart（跟着存档走）；main 搭好区域以后调 apply() 把预设套到环境、日月光、贴地雾带、窗户和夜灯上。
## apply() 每一项都是「设成某个值」，可以重复调（对话里剧情推进到黄昏时，不重新载入场景，直接再套一次）。
## 只管室外的剧情区域：室内（酒馆、小教堂）和灰盒测试场、训练场永远按原来的样子，current 记成 "night"。
##
## 夜 = 序章一直用的数值（main._build_environment() 搭的就是夜），所以 night 的预设和那里一字不差，测试会对照。
## 窗户：整栋房子按材质合并成一个网格（house.gd），不能一扇一扇关；白天把亮窗的玻璃换成暗玻璃、光晕藏起来，
## 清晨按房子挑一部分还亮着（有人起得早），黄昏和夜里全按建的时候的样子。
## 夜灯（街灯、墓园的灯、渡口的风灯、桦林门口的风灯）：白天、清晨灭掉，黄昏点上；营火、修士手里的灯笼不算夜灯，一直亮着。
## 灭掉的灯不在组 light_source 里（敌人感知只看亮着的灯，enemy.gd player_lit()）。

const IDS := ["dawn", "day", "dusk", "night"]
const NAMES := {"dawn": "清晨", "day": "白天", "dusk": "黄昏", "night": "夜"}
## 剧情推进到这个时段时上方的提示（main.set_daypart）
const CHANGE_TEXT := {"dawn": "天亮了。", "day": "日头升起来了。", "dusk": "天色暗下来，到黄昏了。", "night": "入夜了。"}
## 时段影响的区域：室外的剧情区域和军阵试验场；其余（室内、灰盒测试场、训练场）不受时段影响
const SKIP_AREAS := ["test_range", "arena"]

## 预设：环境（天色 = 远雾颜色）、日月光（颜色、强度、角度）、贴地雾带（颜色、浓度倍数）、窗户（亮着的房子比例）、夜灯、敌人在暗处的视距（米）。
## 日月光的角度：rotation_degrees，x 是俯角（越负越高），y 是方位：光沿本地 -Z 射出，射向 (-sin y, 0, -cos y)——
## y = 90 光从正东（+X）照过来，y = 60 从东南，18 从南偏东，-50 从西南。霜渡镇的街朝北（-Z）：北境冬天的太阳从东南升起、
## 中午在南边不高的地方、往西南落——清晨从身后右边斜照进街里（正东太低会被街东边一排房子整个挡住，4.2 截图），白天从身后，黄昏从身后左边。
const PRESETS := {
	"night": {
		"sky": Color("22344a"), "ambient": Color("6f8faf"), "ambient_energy": 0.35,
		"fog_begin": 2.0, "fog_end": 36.0, "fog_curve": 0.85, "fog_height": 0.8, "fog_height_density": 0.25,
		"glow": 0.7, "contrast": 1.08, "saturation": 0.85,
		"sun": Color("8fb0d6"), "sun_energy": 0.32, "sun_rot": Vector3(-38, 150, 0),
		"band": Color(0.45, 0.55, 0.66), "band_density": 1.0,
		"windows": 1.0, "lamps": true, "sight_dark": 8.0,
	},
	"dawn": {
		"sky": Color("878b99"), "ambient": Color("aeb6c4"), "ambient_energy": 0.68,
		"fog_begin": 3.0, "fog_end": 58.0, "fog_curve": 1.0, "fog_height": 0.7, "fog_height_density": 0.35,
		"glow": 0.45, "contrast": 1.05, "saturation": 0.82,
		"sun": Color("ffc29a"), "sun_energy": 0.95, "sun_rot": Vector3(-15, 58, 0),
		"band": Color(0.75, 0.74, 0.78), "band_density": 0.85,
		"windows": 0.35, "lamps": false, "sight_dark": 14.0,
	},
	"day": {
		"sky": Color("9ca6b1"), "ambient": Color("c2cbd5"), "ambient_energy": 0.8,
		"fog_begin": 6.0, "fog_end": 85.0, "fog_curve": 1.0, "fog_height": 0.4, "fog_height_density": 0.15,
		"glow": 0.3, "contrast": 1.04, "saturation": 0.9,
		"sun": Color("f1ece2"), "sun_energy": 1.0, "sun_rot": Vector3(-26, 18, 0),
		"band": Color(0.78, 0.8, 0.84), "band_density": 0.45,
		"windows": 0.0, "lamps": false, "sight_dark": 20.0,
	},
	"dusk": {
		"sky": Color("54485a"), "ambient": Color("8c7f96"), "ambient_energy": 0.45,
		"fog_begin": 2.5, "fog_end": 46.0, "fog_curve": 0.9, "fog_height": 0.7, "fog_height_density": 0.3,
		"glow": 0.6, "contrast": 1.06, "saturation": 0.85,
		"sun": Color("ff9c64"), "sun_energy": 0.7, "sun_rot": Vector3(-8, -50, 0),
		"band": Color(0.56, 0.5, 0.58), "band_density": 0.9,
		"windows": 1.0, "lamps": true, "sight_dark": 12.0,
	},
}

## 这个场景实际在用的时段（main 每次搭场景都会设；室内、测试场为 "night"）。敌人感知按它算暗处的视距
static var current := "night"


static func valid(id: String) -> bool:
	return id in IDS


static func display_name(id: String) -> String:
	return str(NAMES.get(id, id))


## 这个区域受不受时段影响：室外的剧情区域（和军阵试验场）受；室内、灰盒测试场、训练场不受
static func affects(area: String) -> bool:
	return not Areas.is_indoor(area) and not area in SKIP_AREAS


## 区域里实际用哪个时段：受影响的区域用存档里的时段（无效时当夜），其余永远是夜
static func effective(area: String, wanted: String) -> String:
	if not affects(area):
		return "night"
	return wanted if valid(wanted) else "night"


## 敌人在暗处（不在亮着的灯下）能看多远：夜 8 米、黄昏 12、清晨 14、白天 20（= 站在灯下的视距 Enemy.SIGHT_LIT）
static func sight_dark() -> float:
	return float(PRESETS[current if valid(current) else "night"].sight_dark)


## 把时段套到 main 的环境与灯上。main 要有 area、env（Environment）、moon（DirectionalLight3D）。
## 不受时段影响的区域（室内、测试场）什么都不改——它们的环境是 main._build_environment() 另外搭的——只把 current 记成夜
static func apply(main: Node, id: String) -> void:
	if not affects(str(main.get("area"))):
		current = "night"
		return
	current = id if valid(id) else "night"
	var p: Dictionary = PRESETS[current]
	var env: Environment = main.env
	env.background_color = p.sky
	env.fog_light_color = p.sky
	env.ambient_light_color = p.ambient
	env.ambient_light_energy = p.ambient_energy
	env.fog_depth_begin = p.fog_begin
	env.fog_depth_end = p.fog_end
	env.fog_depth_curve = p.fog_curve
	env.fog_height = p.fog_height
	env.fog_height_density = p.fog_height_density
	env.glow_intensity = p.glow                    # 开不开泛光归画质（apply_quality），这里只管强度
	env.adjustment_contrast = p.contrast
	env.adjustment_saturation = p.saturation
	var sun: DirectionalLight3D = main.moon
	sun.light_color = p.sun
	sun.light_energy = p.sun_energy
	sun.rotation_degrees = p.sun_rot
	var tree: SceneTree = main.get_tree()
	for g in ["fog_band", "house", "night_light"]:
		for n in tree.get_nodes_in_group(g):
			_apply_node(n, p)


## 后搭的一块（4.4 鹭沼分帧搭建）：只给 root 底下的雾带、房子、夜灯套上这个时段（环境、月光已经在 apply 里套过）。幂等
static func apply_nodes(root: Node, id: String) -> void:
	var p: Dictionary = PRESETS[id if valid(id) else "night"]
	for n in root.find_children("*", "", true, false):
		_apply_node(n, p)


## 一个节点：雾带换颜色和浓度、房子的窗亮 / 灭、夜灯亮 / 灭；别的节点不管
static func _apply_node(n: Node, p: Dictionary) -> void:
	if n.is_in_group("fog_band"):
		var m := (n as MeshInstance3D).material_override as ShaderMaterial
		if m == null:
			return
		if not n.has_meta("base_density"):
			n.set_meta("base_density", float(m.get_shader_parameter("density")))
		m.set_shader_parameter("color", p.band)
		m.set_shader_parameter("density", float(n.get_meta("base_density")) * float(p.band_density))
	elif n.is_in_group("house"):
		set_windows(n, house_lit(n, float(p.windows)))
	elif n.is_in_group("night_light"):
		set_night_light(n, bool(p.lamps))


## 这栋房子在这个时段亮不亮灯：比例 1 = 都按建的时候的样子，0 = 都不亮；中间按房子的种子挑（同一栋房子每次结果一样）
static func house_lit(house: Node, frac: float) -> bool:
	if frac >= 1.0:
		return true
	if frac <= 0.0:
		return false
	var s := int(house.get_meta("seed", 0))
	return float(absi(hash(s * 7919 + 13)) % 1000) / 1000.0 < frac


## 一栋房子的窗户整体亮 / 灭：灭的时候亮窗的玻璃换成暗玻璃、窗外的光晕藏起来（不改共用的材质，用表面覆盖）
static func set_windows(house: Node, on: bool) -> void:
	var mi := house.get_node_or_null("Mesh") as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	var lit := Look.glass_lit()
	var halo := Look.halo(Look.WINDOW_COLOR, 0.32)
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i)
		if m == lit:
			mi.set_surface_override_material(i, null if on else Look.glass_dark())
		elif m == halo:
			mi.set_surface_override_material(i, null if on else Look.hidden())
	house.set_meta("lit_now", on)


## 登记一盏夜灯（区域搭场景时调）：灯本身 + 它的光晕（可以没有）。白天灭掉时连光晕一起藏，也不再算敌人感知的光源
static func mark_night_light(light: Node3D, halo: Node3D = null) -> void:
	light.add_to_group("night_light")
	if halo != null:
		light.set_meta("halo", halo)           # 元数据设成 null 等于删掉，读的时候先看有没有
	light.set_meta("light_source", light.is_in_group("light_source"))


## 一盏夜灯亮 / 灭。StreetLamp 自己会处理灯笼玻璃（set_lit）；其余的灯：灯、光晕显示与否，光源组进出
static func set_night_light(l: Node, on: bool) -> void:
	if l.has_method("set_lit"):
		l.set_lit(on)
		return
	(l as Node3D).visible = on
	if l.has_meta("halo"):
		var halo: Variant = l.get_meta("halo")
		if is_instance_valid(halo) and halo is Node3D:
			(halo as Node3D).visible = on
	if bool(l.get_meta("light_source", false)):
		if on and not l.is_in_group("light_source"):
			l.add_to_group("light_source")
		elif not on and l.is_in_group("light_source"):
			l.remove_from_group("light_source")
