class_name Minimap
extends Control
## 右上角的圆形小地图（路线图 C.4；所有者 2026-11-07「把地图搬到游戏主页右上角，圆形地图，人物移动，地图实时显示位置，可设定有大地图和小地图，
## 玩家可自行设定，并且该地图玩家可自行设定隐藏或者显示」）。
##   画的是「本地」地图（同一套 AreaMap 规格、同一个 MapPanel.MapCanvas，不写地名），以你为中心、上北下南；你的箭头跟着你转；
##   任务目标（C.2，QuestGuide）在圈里画一个金色菱形，在圈外就贴在圈边上；
##   两档大小（小 / 大）和隐藏：Settings.minimap，暂停菜单里选，N 键轮着换；点一下小地图打开大地图（同「地图」按钮）。
##   没有地图的地方（测试场、训练场）不显示。重画最多每秒 12 次，人没动、没转就不重画。

signal open_map

const SIZES := {"small": 150.0, "large": 230.0}
const PX_PER_M := {"small": 2.4, "large": 2.6}
const REDRAW := 1.0 / 12.0
const RING := Color("c8a440")
const RING_DARK := Color(0.04, 0.06, 0.09, 0.85)
const GOLD := Color("e8c88a")

var mask: Control                    # 画一个实心圆，clip_children 把地图裁成圆
var canvas: MapPanel.MapCanvas
var overlay: Control                 # 圈、「北」、任务目标
var data: MapPanel                   # 不进场景树，只给 MapCanvas 装区域、你的位置和朝向
var area := ""
var diameter := 150.0
var target_xz := Vector2.INF         # 任务目标（世界 XZ；INF = 没有）
var _left := 0.0
var _last := Vector3.INF


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	data = MapPanel.new()
	data.selected_exit = -1
	mask = Control.new()
	mask.name = "Mask"
	mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.draw.connect(func(): mask.draw_circle(mask.size * 0.5, mask.size.x * 0.5, Color.WHITE))
	add_child(mask)
	canvas = MapPanel.MapCanvas.new()
	canvas.name = "MiniCanvas"
	canvas.panel = data
	canvas.mini = true
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.add_child(canvas)
	overlay = Control.new()
	overlay.name = "Ring"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed):
			accept_event()
			open_map.emit())
	apply_size()


func _exit_tree() -> void:
	if data:
		data.free()
		data = null


## 按设置定大小（off = 藏起来）
func apply_size() -> void:
	var s := Settings.minimap
	diameter = float(SIZES.get(s, SIZES.small))
	custom_minimum_size = Vector2(diameter, diameter)
	size = custom_minimum_size
	for c: Control in [mask, canvas, overlay]:
		c.position = Vector2.ZERO
		c.size = size
	canvas.px_per_m = float(PX_PER_M.get(s, PX_PER_M.small))
	_last = Vector3.INF
	_left = 0.0


func shown() -> bool:
	return Settings.minimap != "off" and area != "" and AreaMap.has_map(area)


## 每帧（HUD 调）：你在哪、朝哪；变了就重画（限频）
func track(p_area: String, xz: Vector2, yaw_deg: float, target: Variant, delta: float) -> void:
	if p_area != area:
		area = p_area
		data.area = area
		_last = Vector3.INF
	visible = shown()
	if not visible:
		return
	target_xz = target if target is Vector2 else Vector2.INF
	_left -= delta
	var now := Vector3(xz.x, xz.y, yaw_deg)
	if _left > 0.0 or (now - _last).length() < 0.05:
		return
	_left = REDRAW
	_last = now
	data.player_xz = xz
	data.player_yaw = yaw_deg
	canvas.mode = "local"
	canvas.center = xz
	canvas.queue_redraw()
	mask.queue_redraw()
	overlay.queue_redraw()


func _draw_overlay() -> void:
	var c := size * 0.5
	var r := diameter * 0.5
	if target_xz != Vector2.INF:
		var d := (target_xz - data.player_xz) * canvas.px_per_m
		var lim := r - 9.0
		var p := c + (d if d.length() <= lim else d.normalized() * lim)
		var k := 6.0
		var dia := PackedVector2Array([p + Vector2(0, -k), p + Vector2(k, 0), p + Vector2(0, k), p + Vector2(-k, 0)])
		overlay.draw_colored_polygon(dia, GOLD)
		var o := dia.duplicate()
		o.append(dia[0])
		overlay.draw_polyline(o, RING_DARK, 1.5)
	overlay.draw_arc(c, r - 1.5, 0.0, TAU, 64, RING_DARK, 3.0)
	overlay.draw_arc(c, r - 3.5, 0.0, TAU, 64, RING, 2.0)
	var font := get_theme_default_font()
	var n := c + Vector2(0, -r + 3.0)
	overlay.draw_circle(n + Vector2(0, 7), 10.0, RING_DARK)
	overlay.draw_string(font, n + Vector2(-7, 13), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GOLD)
