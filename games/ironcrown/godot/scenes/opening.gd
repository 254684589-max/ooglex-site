class_name Opening
extends Node
## 开场（路线图 3.8；STORY.md 第三节第 1 步「夜，钟声。玩家在宅邸门口被管家叫住」）。只在新游戏时播一次：
##   1. 站在领主宅邸门口、背对大门望着雾里的街道，标题卡「序章 · 霜渡镇之夜」，等玩家第一次点击 / 按键 / 触屏
##      （网页要有一次用户操作才能出声；电脑上这一下同时锁定鼠标）；标题卡显示的时候先把钟声合成好；
##   2. 钟敲三下，字幕「（镇上的钟敲响了。入夜了。）」，标题卡淡出，底部出走动与转视角的教学提示；
##   3. 钟声落下，身后的管家喊「誓剑大人！请留步——」，提示转身对准他说话；设旗标 opening_done（存档里记着，读档不再播）。
## 是否播放由 main 决定（Opening.wanted）；自动化测试里默认跳过，opening 组单独测。

signal called                       # 管家喊人了

const TOLLS := 3
const TOLL_GAP := 2.4               # 两下钟声之间（秒）
const CALL_AT := 6.6                # 开始后几秒管家喊人（第三下钟声快落下时）
const CALL_LINE := "管家：誓剑大人！请留步——"
const BELL_LINE := "（镇上的钟敲响了。入夜了。）"
const SKIP_QUERY := ["view", "area", "test", "ending", "brawl", "perf", "daypart"]   # 网址带这些参数是截图 / 测试 / 基准用的，不播开场

var main: Node3D
var card: TitleCard
var bell: AudioStreamPlayer
var stage := ""                     # card（等玩家开始）→ bell（钟声）→ called（管家喊过了）
var t := 0.0
var tolls := 0
var frames_waited := 0


## 新游戏才播：不是读档 / 换区域进来的、在主街、网址没带截图测试参数、这一局还没播过；测试里由 Engine 元数据关掉
static func wanted(main_node: Node3D, pending: Dictionary, query: Callable) -> bool:
	if Engine.get_meta("ic_skip_opening", false) or not pending.is_empty() or main_node.area != "frostford":
		return false
	if main_node.use_test_range or main_node.use_arena or GameState.has_flag("opening_done"):
		return false
	for k in SKIP_QUERY:
		if str(query.call(k)) != "":
			return false
	return true


func _ready() -> void:
	bell = AudioStreamPlayer.new()
	bell.volume_db = -6.0
	bell.max_polyphony = TOLLS          # 三下钟声的余音叠在一起
	add_child(bell)


func start(c: TitleCard, touch: bool) -> void:
	card = c
	card.setup(touch)
	card.show()
	stage = "card"
	print("IC_OPENING card")


## 玩家第一次操作：钟声响起、标题卡淡出
func begin() -> void:
	if stage != "card":
		return
	stage = "bell"
	t = 0.0
	if bell.stream == null and Settings.sound:
		bell.stream = Bell.make_stream()
	card.dismiss(Settings.reduced_motion)
	main.hud.say(BELL_LINE, CALL_AT)
	main.show_tip("move", true)
	_toll()
	print("IC_OPENING begin")


## 标题卡在等玩家第一次操作：点击、按键、触屏都算，而且不吞掉这次输入（点击照样锁定鼠标，按键照样生效）。
## 开场节点是主场景最后加进去的，比触屏按钮先收到输入（触屏按钮会把触摸标成已处理）
func _input(event: InputEvent) -> void:
	if stage != "card":
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed):
		begin()


func _process(delta: float) -> void:
	match stage:
		"card":
			# 标题卡显示两帧之后再合成钟声（先把画面画出来）
			frames_waited += 1
			if frames_waited == 3 and bell.stream == null and Settings.sound:
				var t0 := Time.get_ticks_usec()
				bell.stream = Bell.make_stream()
				print("IC_BELL_SYNTH ms=%.0f" % ((Time.get_ticks_usec() - t0) / 1000.0))
		"bell":
			t += delta
			while tolls < TOLLS and t >= tolls * TOLL_GAP:
				_toll()
			if t >= CALL_AT:
				_call()


func _toll() -> void:
	tolls += 1
	if Settings.sound and bell.stream != null:
		bell.play()
	print("IC_BELL toll=%d" % tolls)


func _call() -> void:
	stage = "called"
	GameState.set_flag("opening_done")
	main.hud.say(CALL_LINE, 5.0)
	main.show_tip("talk", true)
	called.emit()
	print("IC_OPENING call")
