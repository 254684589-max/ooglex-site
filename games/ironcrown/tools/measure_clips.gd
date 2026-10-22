extends SceneTree
## 量动作里手的位置（路线图 A.1b）：出招动作的命中帧（impact = 手最靠前、最快的时刻）、蓄力到顶（wind_peak = 命中前手最高的时刻）、
## 闪避 / 冲刺动作的根骨骼位移，写进 data/character_anims.json 前先量。
##   godot --headless --path games/ironcrown/godot -s ../tools/measure_clips.gd -- <源 ual1|ual2> <动作名> [骨头名，默认 hand_r]
## 模型面朝 +Z：「靠前」看 z。逐 1/60 秒取样，打出每 0.05 秒一行和汇总。

const MAP := "res://data/character_anims.json"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("用法：-- <ual1|ual2> <动作名> [骨头名]")
		quit(1)
		return
	var bone_name := args[2] if args.size() > 2 else "hand_r"
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP))
	var src: Dictionary = map.sources[args[0]]
	var game_dir := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var zr := ZIPReader.new()
	if zr.open(game_dir.path_join(str(src.zip))) != OK:
		printerr("打不开 zip")
		quit(1)
		return
	var tmp := OS.get_temp_dir().path_join("ic_measure.glb")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_buffer(zr.read_file(str(src.member)))
	f.close()
	zr.close()
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(tmp, st)
	var scene := doc.generate_scene(st)
	root.add_child(scene)
	await process_frame
	var ap: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	var sk: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
	var b := sk.find_bone(bone_name)
	var root_b := 0
	if not ap.has_animation(args[1]):
		printerr("没有动作 ", args[1])
		quit(1)
		return
	var a := ap.get_animation(args[1])
	ap.play(args[1])
	var prev := Vector3.INF
	var best_z := -INF
	var best_t := 0.0
	var fast_t := 0.0
	var fast_v := 0.0
	var samples := []
	var n := int(a.length * 60.0)
	for i in range(n + 1):
		var t := i / 60.0
		ap.seek(t, true)
		ap.advance(0.0)
		sk.force_update_all_bone_transforms()
		var p := sk.get_bone_global_pose(b).origin
		var r := sk.get_bone_global_pose(root_b).origin
		var v := 0.0 if prev == Vector3.INF else (p - prev).length() * 60.0
		prev = p
		samples.append([t, p, v, r])
		if p.z > best_z:
			best_z = p.z
			best_t = t
		if v > fast_v:
			fast_v = v
			fast_t = t
	var top_y := -INF
	var top_t := 0.0
	for s in samples:
		if s[0] <= best_t and s[1].y > top_y:
			top_y = s[1].y
			top_t = s[0]
	for s in samples:
		if is_equal_approx(fmod(s[0] * 20.0 + 0.0001, 1.0), 0.0) or fmod(s[0] * 20.0 + 0.001, 1.0) < 0.01:
			print("t=%.2f  %s=(%.2f, %.2f, %.2f)  v=%.1f  root=(%.2f, %.2f, %.2f)" % [s[0], bone_name, s[1].x, s[1].y, s[1].z, s[2], s[3].x, s[3].y, s[3].z])
	print("%s  长 %.2f 秒  最靠前 t=%.2f（z=%.2f）  最快 t=%.2f（%.1f 米/秒）  之前最高 t=%.2f（y=%.2f）" % [args[1], a.length, best_t, best_z, fast_t, fast_v, top_t, top_y])
	scene.free()
	DirAccess.remove_absolute(tmp)
	quit(0)
