extends SceneTree
## 打包人物动画库（路线图 A.1）：从 Quaternius Universal Animation Library 的 zip 里取出 data/character_anims.json 列出的动作，
## 存成 res://assets/characters/anims/ual_core.res（AnimationLibrary）。原包的 glb 里还带着整个人台网格和 40 多个用不上的动作，
## 不进网页导出；只打包用到的，网页包小很多。
##   godot --headless --path games/ironcrown/godot -s ../tools/build_character_anims.gd
## 动作数据不变时重复运行得到同样的结果。zip 放在 games/ironcrown/assets/source/quaternius/（CC0，来源见 assets/SOURCES.md）。

const MAP := "res://data/character_anims.json"
const OUT := "res://assets/characters/anims/ual_core.res"


func _init() -> void:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP))
	var game_dir := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var lib := AnimationLibrary.new()
	var wanted: Dictionary = map.clips
	var failed := false
	for src_id in map.sources.keys():
		var src: Dictionary = map.sources[src_id]
		var zip_path := game_dir.path_join(str(src.zip))
		var zr := ZIPReader.new()
		if zr.open(zip_path) != OK:
			printerr("打不开 ", zip_path)
			quit(1)
			return
		var bytes := zr.read_file(str(src.member))
		zr.close()
		var tmp := OS.get_temp_dir().path_join("ic_%s.glb" % src_id)
		var f := FileAccess.open(tmp, FileAccess.WRITE)
		f.store_buffer(bytes)
		f.close()
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(tmp, st) != OK:
			printerr("读不了 ", tmp)
			quit(1)
			return
		var scene := doc.generate_scene(st)
		var ap: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
		var src_lib := ap.get_animation_library("")
		for clip in wanted.keys():
			if str(wanted[clip].src) != src_id:
				continue
			if not src_lib.has_animation(clip):
				printerr("动作库里没有 ", clip)
				failed = true
				continue
			var a: Animation = src_lib.get_animation(clip).duplicate()
			a.loop_mode = Animation.LOOP_LINEAR if bool(wanted[clip].loop) else Animation.LOOP_NONE
			lib.add_animation(clip, a)
		scene.free()
		DirAccess.remove_absolute(tmp)
	for role in map.roles.keys():
		if not lib.has_animation(str(map.roles[role])):
			printerr("角色 ", role, " 指向的动作不在库里：", map.roles[role])
			failed = true
	if failed:
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	if ResourceSaver.save(lib, OUT) != OK:
		printerr("保存失败 ", OUT)
		quit(1)
		return
	print("已打包 %d 个动作 → %s（%d 字节）" % [lib.get_animation_list().size(), OUT, FileAccess.get_file_as_bytes(OUT).size()])
	quit(0)
