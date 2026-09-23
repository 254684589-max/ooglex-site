extends Node
## 存档系统（自动加载名：SaveSystem）。
## 保存为 JSON：user://construction_worker_save.json
## 网页版的 user:// 由 Godot 映射到浏览器 IndexedDB，关闭页面后仍然保留。
##
## 保存内容：现金、天数与时间、玩家位置、任务进度、人物属性、剧情标记、
## 手上拿着的东西、地上散落的材料、各卸货区已码放的数量。

signal saved(ok: bool)
signal loaded(ok: bool)

const SAVE_PATH := "user://construction_worker_save.json"
const SAVE_VERSION := 1

## 由 main.gd 设置：返回 / 应用世界状态（散落物、卸货区）
var world_provider: Callable = Callable()
var world_applier: Callable = Callable()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) and not read_save().is_empty()


func read_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	if int(data.get("version", 0)) < 1:
		return {}
	return data


func build_save() -> Dictionary:
	var data := {
		"version": SAVE_VERSION,
		"game": "ConstructionWorker",
		"saved_at": Time.get_datetime_string_from_system(),
		"economy": EconomySystem.to_dict(),
		"time": TimeSystem.to_dict(),
		"stats": PlayerStats.to_dict(),
		"tasks": TaskSystem.to_dict(),
		"state": GameState.to_dict(),
	}
	var p := GameState.player
	if p != null and p.has_method("to_save_dict"):
		data["player"] = p.to_save_dict()
	if world_provider.is_valid():
		data["world"] = world_provider.call()
	return data


func save_game() -> bool:
	if not GameState.playing:
		return false
	var data := build_save()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveSystem: 无法写入存档 %s" % error_string(FileAccess.get_open_error()))
		saved.emit(false)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	saved.emit(true)
	return true


## 把存档应用到各个系统。调用前场景（玩家、世界）必须已经创建好。
func apply_save(data: Dictionary) -> bool:
	if data.is_empty():
		loaded.emit(false)
		return false
	EconomySystem.from_dict(data.get("economy", {}))
	TimeSystem.from_dict(data.get("time", {}))
	PlayerStats.from_dict(data.get("stats", {}))
	TaskSystem.from_dict(data.get("tasks", {}))
	GameState.from_dict(data.get("state", {}))
	var p := GameState.player
	if p != null and p.has_method("apply_save_dict"):
		p.apply_save_dict(data.get("player", {}))
	if world_applier.is_valid():
		world_applier.call(data.get("world", {}))
	loaded.emit(true)
	return true


func delete_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove(SAVE_PATH.get_file())


## 存档摘要，用于标题画面「继续游戏」按钮
func describe_save() -> String:
	var d := read_save()
	if d.is_empty():
		return ""
	var t: Dictionary = d.get("time", {})
	var e: Dictionary = d.get("economy", {})
	var minutes := int(float(t.get("minutes", 360.0))) % 1440
	return "第 %d 天 %02d:%02d · ¥%d" % [int(t.get("day", 1)), int(minutes / 60.0), minutes % 60, int(e.get("cash", 0))]
