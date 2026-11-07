class_name Cutscene
extends Node
## 过场演出（路线图 C.5；所有者 2026-11-07 问「如何加入影之刃零和《燕云十六声》那种游戏剧情」→「做过场系统，先做一个小样」）。
## 关键剧情不只是对话框：镜头自己运镜（每个镜头从一个机位缓缓移到另一个机位、可以推拉焦距），上下黑边、底部字幕（谁说的、说什么），
## 镜头之间淡入淡出或者直接切；人物说话时做说话的动作；随时可以跳过（Esc、E、点右上角「跳过」）。
## 只学手法，不搬别的游戏的剧情和画面（WORLD.md 第九节原创红线）。
##
## 镜头脚本（Array，每个镜头一个字典）：
##   from / to        [机位, 看向的点]（Vector3；to 不写 = 不动）
##   dur              秒
##   fov / fov_to     视野角（默认 50；fov_to 不写 = 不变）
##   cut              true = 直接切进来（默认淡入 0.35 秒）；最后一个镜头结束总是淡出
##   lines            [[开始的秒, 谁, 说什么], …]（谁 = "" 是旁白 / 地名，居中、不带名字）
##   talk             说话的人（Npc 节点）：这个镜头里他在说话
##   on_start         Callable（可选）：镜头开始时调（摆道具之类）
## 播放时：玩家不能动、HUD 藏起来、换到过场自己的相机；结束或跳过后全部还原，发 finished(skipped)。

signal finished(skipped: bool)

const BAR := 0.11                    # 黑边各占画面高度的多少
const FADE := 0.35
const EASE := 2.2                    # 运镜的缓入缓出（越大两头越慢）

var shots: Array = []
var id := ""
var cam: Camera3D
var layer: CanvasLayer
var top_bar: ColorRect
var bottom_bar: ColorRect
var fader: ColorRect
var speaker_label: Label
var text_label: Label
var skip_btn: Button
var index := -1
var t := 0.0
var bars := 0.0                      # 黑边进场 0..1
var done := false
var skipped := false
var restore_cam: Camera3D
var talking: Npc = null
var line_now := ""                   # 现在显示的字幕（测试、截图日志看）


## 在 parent（世界）里播放；prev_cam = 播完切回去的相机
static func play(parent: Node, cut_id: String, script_shots: Array, prev_cam: Camera3D) -> Cutscene:
	var c := Cutscene.new()
	c.name = "Cutscene"
	c.id = cut_id
	c.shots = script_shots
	c.restore_cam = prev_cam
	parent.add_child(c)
	return c


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cam = Camera3D.new()
	cam.name = "CutsceneCamera"
	add_child(cam)
	cam.make_current()
	layer = CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	top_bar = _rect(Color.BLACK)
	bottom_bar = _rect(Color.BLACK)
	fader = _rect(Color.BLACK)
	fader.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fader.color.a = 1.0
	var box := VBoxContainer.new()
	box.name = "Subtitle"
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(box)
	speaker_label = _label(18, Color("e8c88a"))
	text_label = _label(20, Color("ece4d0"))
	box.add_child(speaker_label)
	box.add_child(text_label)
	skip_btn = Button.new()
	skip_btn.name = "Skip"
	skip_btn.text = "跳过 ▸"
	skip_btn.focus_mode = Control.FOCUS_NONE
	skip_btn.flat = true
	skip_btn.add_theme_color_override("font_color", Color(0.85, 0.82, 0.74, 0.75))
	skip_btn.pressed.connect(skip)
	layer.add_child(skip_btn)
	get_viewport().size_changed.connect(_layout)
	_layout()
	print("IC_CUTSCENE start id=%s shots=%d" % [id, shots.size()])
	_next_shot()


func _rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(r)
	return r


func _label(fs: int, c: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	var h := s.y * BAR * bars
	top_bar.position = Vector2.ZERO
	top_bar.size = Vector2(s.x, h)
	bottom_bar.position = Vector2(0, s.y - h)
	bottom_bar.size = Vector2(s.x, h)
	var box := layer.get_node("Subtitle") as Control
	var w := minf(s.x - 40.0, 860.0)
	box.size = Vector2(w, s.y * BAR + 30.0)
	box.position = Vector2((s.x - w) * 0.5, s.y - box.size.y - 6.0)
	for l in [speaker_label, text_label]:
		(l as Label).custom_minimum_size = Vector2(w, 0)
	skip_btn.position = Vector2(s.x - 110.0, 8.0)
	skip_btn.size = Vector2(100, 36)


func _next_shot() -> void:
	index += 1
	t = 0.0
	if talking and is_instance_valid(talking):
		talking.end_talk()
	talking = null
	if index >= shots.size():
		_finish()
		return
	var sh: Dictionary = shots[index]
	if sh.has("on_start"):
		(sh.on_start as Callable).call()
	if sh.get("talk") is Npc and is_instance_valid(sh.talk):
		talking = sh.talk
		talking.begin_talk()
	_pose(0.0)


## 镜头里第 k（0..1）处的机位
func _pose(k: float) -> void:
	var sh: Dictionary = shots[index]
	var a: Array = sh.from
	var b: Array = sh.get("to", sh.from)
	var e := _ease(k)
	var pos: Vector3 = (a[0] as Vector3).lerp(b[0], e)
	var look: Vector3 = (a[1] as Vector3).lerp(b[1], e)
	cam.global_position = pos
	if not pos.is_equal_approx(look):
		cam.look_at(look, Vector3.UP)
	cam.fov = lerpf(float(sh.get("fov", 50.0)), float(sh.get("fov_to", sh.get("fov", 50.0))), e)


static func _ease(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return pow(k, EASE) / (pow(k, EASE) + pow(1.0 - k, EASE))


func _process(delta: float) -> void:
	if done:
		return
	bars = minf(1.0, bars + delta / 0.6)
	_layout()
	if index < 0 or index >= shots.size():
		return
	var sh: Dictionary = shots[index]
	var dur := float(sh.get("dur", 3.0))
	t += delta
	_pose(t / dur)
	# 淡入（第一个镜头、或者不是直接切的镜头）、最后一个镜头淡出
	var fade_in := 1.0 if (index == 0 or not bool(sh.get("cut", false))) else 0.0
	var a := 0.0
	if fade_in > 0.0 and t < FADE:
		a = 1.0 - t / FADE
	if index == shots.size() - 1 and t > dur - FADE * 1.6:
		a = maxf(a, clampf((t - (dur - FADE * 1.6)) / (FADE * 1.6), 0.0, 1.0))
	fader.color.a = a
	# 字幕：这一刻该显示哪一句
	var who := ""
	var what := ""
	for ln: Array in sh.get("lines", []):
		if t >= float(ln[0]):
			who = str(ln[1])
			what = str(ln[2])
	speaker_label.text = who
	speaker_label.visible = who != ""
	text_label.text = what
	if what != line_now:
		line_now = what
		if what != "":
			print("IC_CUTSCENE line shot=%d %s" % [index, what.left(16)])
	if t >= dur:
		_next_shot()


func _unhandled_input(event: InputEvent) -> void:
	if done:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		skip()


func skip() -> void:
	if done:
		return
	skipped = true
	_finish()


func _finish() -> void:
	if done:
		return
	done = true
	if talking and is_instance_valid(talking):
		talking.end_talk()
	if restore_cam and is_instance_valid(restore_cam):
		restore_cam.make_current()
	print("IC_CUTSCENE end id=%s skipped=%s" % [id, skipped])
	finished.emit(skipped)
	queue_free()
