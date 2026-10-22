extends SceneTree
## 开发工具（路线图 A.1）：把人物摆在几个动作的某一刻、从几个角度渲染成一张拼图 PNG，用来校准拿剑的位置、检查动作。
## 需要能渲染：Linux 上用 xvfb + Mesa 软件渲染（本环境实测可用，不需要显卡）：
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path games/ironcrown/godot --rendering-driver opengl3 \
##     -s ../tools/character_sheet.gd -- out=/tmp/sheet.png [grip=px,py,pz,rx,ry,rz] [jobs="动作@秒@相机偏角;动作@秒@相机偏角"]
## 例：jobs="Sword_Idle@0@20;Sword_Attack@0.33@30;Sword_Block@0.17@30"（动作名见 data/character_anims.json；none = 不播动作，看 T 姿势）
## A.2b：prop=lantern|torch|axe|cup|none 换手里的东西（默认剑）。A.2：parts=Outfit_Male_Peasant,Head_Male,Hair_Beard 换装预览；look='{"tint":{"MI_Peasant":"#8a9cb0"}}' 换颜色。
## A.2b：hide=Male_Ranger_Head_Hood 藏部件；cape=#5e2420 背上披风（actors/cape.gd，每个镜头前先让布垂一会儿）。player=1 直接用 looks.json 里主角的打扮和披风。
## grip= 临时覆盖 data/character_anims.json 里的拿剑位置与朝向（米 / 度），满意了再写回 JSON。

var character: CharacterModel
var sword: Node3D
var cam: Camera3D
var jobs: Array = []
var tiles: Array = []
var idx := 0
var wait := 0
var out := "/tmp/viewer.png"
const TILE := Vector2i(360, 480)


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	out = args.get("out", out)
	for j in str(args.get("jobs", "Sword_Idle@0@0;Sword_Idle@0@90;Sword_Attack@0.33@30;Sword_Attack@0.4@30;Sword_Attack@0.45@60;Sword_Block@0.17@30")).split(";"):
		jobs.append(j.split("@"))
	root.size = TILE
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.2, 0.26)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.58, 0.65)
	root.add_child(env)
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-35, 35, 0)
	l.light_energy = 1.1
	root.add_child(l)
	cam = Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	character = CharacterModel.new()
	var parts := str(args.get("parts", ""))         # A.2：parts=服装,头,头发（assets/characters/outfits/ 下的文件名，不带 .gltf）
	if parts != "":
		for p in parts.split(","):
			character.parts.append("res://assets/characters/outfits/%s.gltf" % p)
	var lk := str(args.get("look", ""))             # A.2：look={"tex": {...}, "tint": {...}}（JSON）
	if lk != "":
		character.look = JSON.parse_string(lk)
	var hide := str(args.get("hide", "")).split(",", false)
	var cape_col := str(args.get("cape", ""))
	if args.get("player", "") == "1":
		var s := Looks.spec_of(Looks.player())
		character.parts = s.parts
		character.look = s.look
		hide = PackedStringArray(s.hide)
		cape_col = str(Looks.player().get("cape", ""))
	character.set_meta("hide", Array(hide))
	root.add_child(character)
	await process_frame
	await process_frame
	if not character.loaded:
		printerr("人物没加载成功")
		quit(1)
		return
	Looks.hide_parts(character)
	if cape_col != "":
		root.add_child(Cape.make(character, Color(cape_col)))
	var g := str(args.get("grip", ""))
	if g != "":
		var v := g.split(",")
		character.grip.position = Vector3(float(v[0]), float(v[1]), float(v[2]))
		character.grip.rotation_degrees = Vector3(float(v[3]), float(v[4]), float(v[5]))
	var kit := MeshKit.new()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("b4bcc6")
	steel.metallic = 0.35
	steel.roughness = 0.4
	steel.vertex_color_use_as_albedo = true
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("6a4a30")
	wood.vertex_color_use_as_albedo = true
	kit.box("steel", Vector3(0, 0.42, 0), Vector3(0.045, 0.62, 0.01))
	kit.box("wood", Vector3(0, 0.08, 0), Vector3(0.18, 0.025, 0.03))
	kit.box("wood", Vector3(0, -0.01, 0), Vector3(0.032, 0.16, 0.032))
	sword = kit.build({"steel": steel, "wood": wood})
	var prop := str(args.get("prop", ""))           # A.2b：prop=lantern / torch / axe / cup / none 换手里的东西
	if prop != "":
		sword = Props.make(prop)
	if sword != null:
		character.hold_prop(sword, prop in Props.LEFT_HAND)
	_next()


func _next() -> void:
	if idx >= jobs.size():
		_finish()
		return
	var j: Array = jobs[idx]
	if str(j[0]) != "none":
		character.hold(str(j[0]), float(j[1]), 0.0)
	var yaw := deg_to_rad(float(j[2]))
	# 人物面朝 +Z；相机绕着转
	cam.position = Vector3(sin(yaw) * 3.4, 1.15, cos(yaw) * 3.4)
	cam.look_at_from_position(cam.position, Vector3(0, 0.95, 0))
	wait = 40 if idx == 0 else 25             # 披风垂下来、晃停要一会儿


func _process(_d: float) -> bool:
	if wait > 0:
		wait -= 1
		if wait == 0:
			var img := root.get_texture().get_image()
			var h := img.get_height()
			var w := int(h * 0.75)
			var crop := img.get_region(Rect2i((img.get_width() - w) / 2, 0, w, h))
			crop.resize(TILE.x, TILE.y, Image.INTERPOLATE_BILINEAR)
			tiles.append(crop)
			idx += 1
			_next()
	return false


func _finish() -> void:
	var cols := mini(tiles.size(), 3)
	var rows := int(ceil(tiles.size() / float(cols)))
	var sheet := Image.create(TILE.x * cols, TILE.y * rows, false, Image.FORMAT_RGBA8)
	for i in range(tiles.size()):
		var t: Image = tiles[i]
		t.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(t, Rect2i(Vector2i.ZERO, TILE), Vector2i((i % cols) * TILE.x, (i / cols) * TILE.y))
	sheet.save_png(out)
	print("saved ", out, " ", sheet.get_size())
	quit()
