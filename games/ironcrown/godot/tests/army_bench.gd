extends Node
## 军队规模压力测试（2026-10-04，路线图 D8「中型战斗」的依据；B.5 复测用）。结果记在 TEST_REPORT.md。
## 在训练场里放 N 个兵，测每帧逻辑耗时与绘制调用。不是自动化测试（test_runner 不跑它）。
##   原生（无头，只测 CPU）：godot --headless --path games/ironcrown/godot --fixed-fps 60 res://tests/army_bench.tscn -- mode=combat model=1
##   网页（WASM）：tools/army_bench_web.sh "mode=combat&model=1&no3d=1"
## 参数：mode=combat|battle|crowd  model=0|1  counts=0,10,25,...  settle=秒  sample=秒  no3d=1（不画 3D，只测逻辑）  q=low|medium|high
## combat：现有 Enemy（完整 AI：感知、导航、令牌、出招、move_and_slide）全部 engage() 冲向玩家——所有人挤成一团，是最坏情况
## battle：B.1 的军阵——N 个 Soldier 分两边（各一半）在军阵试验场里互相打，玩家不参战（目标按人分散，是真实战斗的样子）
## crowd ：只摆人（没有 AI），model=1 时每人一个带骨骼动画的 CharacterModel，model=0 时是现在的占位胶囊
## model=1 时 Enemy 的占位身体藏起来，换成 CharacterModel（模拟 A.2 之后每个兵都是正式人物）
## 输出 ICB 行：frame_ms 是每帧总时间（网页上含软件渲染，不可比）；logic60_ms = 一步物理 + 一帧逻辑（physics_frame → frame_pre_draw），
## 只有画面在画（有 frame_pre_draw）时才有值，无头原生运行看 frame_ms（--fixed-fps 60 时每帧正好一步物理）。

var counts := [0, 10, 25, 50, 100, 150, 200, 300]
var mode := "combat"
var model := false
var settle := 2.0
var sample := 4.0
var main: Node3D
var spawned: Array = []
var battle: Battle
var results: Array = []
# 每帧逻辑耗时：physics_frame（第一帧物理）→ process_frame → frame_pre_draw；网页上 rAF 的空等不算进去
var t_phys := 0
var t_proc := 0
var ticks := 0
var acc_phys := 0.0
var acc_proc := 0.0
var acc_ticks := 0
var acc_frames := 0
var measuring := false
var game_t := 0.0                 # 游戏时间（秒）：settle / sample 按游戏时间算——原生 --fixed-fps 60 一帧就是 1/60 秒，
                                  # 无头每秒跑几千帧，按墙钟算的话军阵早打完了（B.1 实测）


func _on_phys() -> void:
	if t_phys == 0:
		t_phys = Time.get_ticks_usec()
	ticks += 1


func _on_proc() -> void:
	t_proc = Time.get_ticks_usec()


func _on_pre_draw() -> void:
	var now := Time.get_ticks_usec()
	if measuring and t_proc > 0:
		if t_phys > 0:
			acc_phys += t_proc - t_phys
			acc_ticks += ticks
		acc_proc += now - t_proc
		acc_frames += 1
	t_phys = 0
	ticks = 0
	t_proc = 0


func _args() -> Dictionary:
	var d := {}
	var raw: Array = []
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("location.search.substring(1)", true))
		raw = Array(q.split("&", false))
	else:
		raw = Array(OS.get_cmdline_user_args())
	for a in raw:
		var kv := str(a).split("=")
		if kv.size() == 2:
			d[kv[0]] = kv[1]
	return d


func _ready() -> void:
	var a := _args()
	mode = str(a.get("mode", mode))
	model = str(a.get("model", "0")) == "1"
	settle = float(a.get("settle", settle))
	sample = float(a.get("sample", sample))
	if a.has("counts"):
		counts = Array(str(a.counts).split(",")).map(func(s): return int(s))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	if mode == "battle":
		main.area = "battle"                 # 军阵试验场（B.1），不自动开打
		main.battle_autostart = false
	else:
		main.use_arena = true
	add_child(main)
	for i in 5:
		await get_tree().process_frame
	# 原有的兵拿走，只留玩家和场地
	for e in get_tree().get_nodes_in_group("enemy") + get_tree().get_nodes_in_group("soldier"):
		e.queue_free()
	if main.battle:
		main.battle.queue_free()
	await get_tree().process_frame
	get_tree().physics_frame.connect(_on_phys)
	get_tree().process_frame.connect(_on_proc)
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	if str(a.get("no3d", "0")) == "1":
		get_viewport().disable_3d = true
	if a.has("q"):
		main.apply_quality(str(a.q))
	print("ICB_START mode=%s model=%d web=%s renderer=%s no3d=%s q=%s" % [mode, int(model), OS.has_feature("web"), RenderingServer.get_current_rendering_driver_name(), a.get("no3d", "0"), main.quality])
	for n in counts:
		await _run(n)
	print("ICB_DONE")
	get_tree().quit()


func _process(d: float) -> void:
	game_t += d
	if main and main.player and main.player.melee:     # 玩家不死，测试一直打下去
		main.player.melee.health = main.player.melee.health_max()
		main.player.melee.down = false


func _clear() -> void:
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	spawned.clear()
	if battle:
		battle.queue_free()
		battle = null


func _spawn(n: int) -> void:
	if mode == "battle":
		battle = Battle.new()
		battle.add_side("white", "白带")
		battle.add_side("black", "黑带")
		battle.max_active = maxi(n, Battle.MAX_ACTIVE)      # 压力测试要测超过上限的人数：全部进场
		main.world.add_child(battle)
		var half := n / 2
		for i in n:
			var sd := "white" if i < half else "black"
			var k := i if i < half else i - half
			var kind := BattleArena.kind_for(k, half + 1)      # 和试验场同样的兵种搭配（B.4；+1 让最后一个也不是队长）
			var s := Soldier.create(kind, "bench%d" % i, sd, Color(BattleArena.SIDES[sd].coat), Color(BattleArena.SIDES[sd].band))
			s.position = BattleArena.slot(sd, k, maxi(half, n - half))
			s.rotation.y = 0.0 if sd == "white" else PI
			battle.enlist(s, main.world)
			if model:
				s.body.visible = false
				s.model = _add_model(s)           # 远处每 2 帧推进一次动作（B.5，Soldier._lod）
			spawned.append(s)
		await get_tree().process_frame
		battle.start()
		return
	var side := int(ceil(sqrt(float(n))))
	var gap := minf(1.4, 26.0 / maxf(side, 1))
	for i in n:
		var x := -0.5 * gap * (side - 1) + gap * (i % side)
		var z := 6.0 - gap * (i / side)
		var pos := Vector3(x, 0, z)
		if mode == "combat":
			var e := Enemy.make("swordsman" if i % 2 == 0 else "clubber", "bench%d" % i, [pos])
			e.position = pos
			main.world.add_child(e)
			if model:
				e.body.visible = false
				_add_model(e)
			spawned.append(e)
		else:
			var root := Node3D.new()
			root.position = pos
			root.rotation.y = PI      # 面向玩家
			main.world.add_child(root)
			if model:
				_add_model(root)
			else:
				Npc.build_body(root, Color("6a4a3a"))
			spawned.append(root)
	await get_tree().process_frame
	if mode == "combat":
		for e in spawned:
			e.engage()


func _add_model(parent: Node3D) -> CharacterModel:
	var cm := CharacterModel.new()
	cm.rotation.y = PI
	parent.add_child(cm)
	cm.play_loop("idle_armed" if mode == "crowd" else "run", 1.0)
	if cm.loaded:
		cm.anim.seek(randf() * 0.5, true)
	return cm


func _run(n: int) -> void:
	_clear()
	await get_tree().process_frame
	await _spawn(n)
	var g_end := game_t + settle
	while game_t < g_end:
		await get_tree().process_frame
	var frames := 0
	acc_phys = 0.0
	acc_proc = 0.0
	acc_ticks = 0
	acc_frames = 0
	measuring = true
	var dc := 0.0
	var prim := 0.0
	var obj := 0.0
	var worst := 0
	var t0 := Time.get_ticks_usec()
	var last := t0
	var g_stop := game_t + sample
	while game_t < g_stop:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
		frames += 1
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		obj += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	measuring = false
	frames = maxi(frames, 1)
	var wall := float(Time.get_ticks_usec() - t0) / 1000.0 / frames
	# 物理每一步、逻辑每一帧（毫秒）；没有 frame_pre_draw（无头）时为 -1，用 frame_ms
	var phys_tick := acc_phys / maxi(acc_ticks, 1) / 1000.0 if acc_frames > 0 else -1.0
	var proc_frame := acc_proc / maxi(acc_frames, 1) / 1000.0 if acc_frames > 0 else -1.0
	var alive := 0
	var fighting := 0
	if mode != "crowd":
		for e in spawned:
			if is_instance_valid(e) and (e.fighting() if e is Soldier else e.alive()):
				alive += 1
				if e.has_token:
					fighting += 1
	var line := "ICB n=%d mode=%s model=%d frame_ms=%.2f fps=%.1f logic60_ms=%.2f phys_tick_ms=%.2f proc_ms=%.2f worst_ms=%.1f draw_calls=%.0f primitives=%.0f objects=%.0f alive=%d tokens=%d" % [
		n, mode, int(model), wall, 1000.0 / wall, phys_tick + proc_frame, phys_tick, proc_frame, worst / 1000.0, dc / frames, prim / frames, obj / frames, alive, fighting]
	print(line)
	results.append(line)
