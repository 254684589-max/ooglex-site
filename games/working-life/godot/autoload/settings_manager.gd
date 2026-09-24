extends Node
## 游戏设置（自动加载名：SettingsManager），保存在 user://settings.cfg。
## 分辨率、窗口/全屏、音量（总/音乐/音效）、鼠标灵敏度、画质、阴影、抗锯齿、帧率上限。

signal changed

const PATH := "user://settings.cfg"
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const FPS_OPTIONS := [30, 60, 120, 0]
const QUALITY_NAMES := ["低", "中", "高", "超高"]
## 设置格式版本：2 = 新增「超高」画质（电脑浏览器默认开启）
const SETTINGS_REV := 2

var values := {
	"resolution": 0,
	"fullscreen": false,
	"master": 0.9,
	"music": 0.6,
	"sfx": 0.8,
	"ambience": 0.7,
	"sensitivity": 1.0,
	"invert_y": false,
	"quality": 1,
	"shadows": true,
	"msaa": true,
	"fps": 1,
	"show_marker": true,
	"time_speed": 1,
	"rev": SETTINGS_REV,
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	if OS.has_feature("web") or DisplayServer.get_name() == "headless":
		return
	call_deferred("apply_window")


func get_v(key: String, default: Variant = null) -> Variant:
	return values.get(key, default)


func set_v(key: String, v: Variant) -> void:
	values[key] = v
	save_settings()
	apply_runtime()
	if key in ["resolution", "fullscreen"]:
		apply_window()
	changed.emit()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		if OS.has_feature("web") and GameManager.touch_mode:
			values["quality"] = 0
			values["shadows"] = false
			values["msaa"] = false
		elif not GameManager.touch_mode:
			values["quality"] = 3
		return
	for k in values.keys():
		values[k] = cfg.get_value("settings", k, values[k])
	# 老存档的设置：电脑端还停在默认「中」画质的，升级到新的「超高」（只迁移一次；手动选过别的档位的不动）
	if int(cfg.get_value("settings", "rev", 1)) < SETTINGS_REV:
		if not GameManager.touch_mode and int(values["quality"]) == 1:
			values["quality"] = 3
		values["rev"] = SETTINGS_REV
		save_settings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in values:
		cfg.set_value("settings", k, values[k])
	cfg.save(PATH)


func apply_runtime() -> void:
	var fps: int = FPS_OPTIONS[clampi(int(values["fps"]), 0, FPS_OPTIONS.size() - 1)]
	Engine.max_fps = fps
	AudioManager.apply_volumes()


func apply_window() -> void:
	if OS.has_feature("web") or DisplayServer.get_name() == "headless":
		return
	if bool(values["fullscreen"]):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var res: Vector2i = RESOLUTIONS[clampi(int(values["resolution"]), 0, RESOLUTIONS.size() - 1)]
		DisplayServer.window_set_size(res)
		var screen := DisplayServer.screen_get_size()
		DisplayServer.window_set_position((screen - res) / 2)
