extends SceneTree
## 语法 / 编译检查：加载工程里的每一个 .gd 脚本（自动加载已就绪），有错误时退出码为 1。
##   godot --headless --path games/working-life/godot -s res://tests/parse_all.gd

var failed: Array = []


func _initialize() -> void:
	_scan("res://")
	if failed.is_empty():
		print("PARSE OK")
		quit(0)
	else:
		print("PARSE FAILED: ", failed)
		quit(1)


func _scan(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			var path := dir.path_join(f)
			var s = load(path)
			if s == null or not (s as GDScript).can_instantiate():
				failed.append(path)
	for sub in d.get_directories():
		if sub.begins_with("."):
			continue
		_scan(dir.path_join(sub))
