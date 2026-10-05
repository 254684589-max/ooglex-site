class_name Soldier
extends Enemy
## 军阵战斗的士兵（路线图 B.1，D8「中型战斗」；GDD.md 6.4，TECH.md 4.10）。
## 在 Enemy 上加一个阵营（side）：对手不再固定是玩家，而是军阵（Battle）挑给它的最近的敌方——另一个兵，或者玩家。
## 每 RETARGET 秒（相位错开）重新挑一次；对手倒下、求饶、逃跑时马上换。挑的时候避开已经被很多人盯着的目标，战场散成一对一、二对一。
## 开战即进入战斗，不走潜行感知（对兵不打视线射线）；数值在 data/enemies.json（soldier 剑兵、levy 民兵）。
## 玩家这一边的兵（友军）不在组 enemy、不在可受击层：玩家的剑砍不到自己人，存档、出门的「附近有敌人」也不算它们。
## 普通兵 transient：倒下、求饶不写进存档，不留搜刮点（存不存在 B.3 定）。外观仍是占位胶囊：罩袍按阵营上色，胸前一道白 / 黑布带。
## B.2：编进玩家小队的兵头顶有金色 ◆；跟随 / 坚守时只挑拴绳范围里的对手（Battle.leash），没有对手时走到自己的位置（Battle.post_of）站好。
## B.3：士气 morale（剑兵 70、民兵 55、队长 100，最多再涨 20）：规则在 Battle（on_fall、morale_tick），掉到 MORALE_BREAK 以下就逃跑或求饶（break_rank）。
## 队长（kind = captain）背上插一面小旗（阵营布带的颜色），隔着人群也看得见。

const RETARGET := 0.25            # 多久重新挑一次对手（秒）
const LABEL_NEAR := 6.0           # 敌方的兵离玩家这么近才显示头顶的状态（几十个兵都显示，Label3D 太费绘制调用，画面也乱；友军不显示）
const STUCK_TIME := 2.5           # 拿着攻击令牌却这么久没能出招（被人挡住了）：交回令牌，让别人上
const BLOCKED_TIME := 0.25        # 走向自己的位置时这么久几乎没挪动（迎面撞上人）：往旁边绕一下（B.2 实测：正对着玩家或别的兵会卡住不动）
const DODGE_TIME := 0.7
const DODGE_ANGLE := 75.0
const MORALE_START := {"soldier": 70.0, "levy": 55.0, "captain": 100.0}
const MORALE_BREAK := 15.0        # 士气掉到这里就撑不住了
const MORALE_TICK := 1.0          # 多久看一次身边（秒，相位错开）

var side := ""                    # 阵营编号（Battle.sides 的键）
var battle: Battle
var target: Node3D                # 现在的对手：另一个 Soldier 或玩家；没有敌人了为空
var faction_id := ""              # 玩家打倒时扣哪个势力的声望（"" = 不扣，例如试验场）
var coat_color := Color("4a5260")
var band_color := Color.WHITE
var retarget_t := 0.0
var approach_t := 0.0             # 拿着令牌往前凑了多久还没出招
var band: MeshInstance3D
var in_squad := false             # 归玩家指挥（B.2）
var order := ""                   # 小队命令：follow / hold / charge（不在小队为空）
var slot := 0                     # 小队里的序号（排队形用）
var anchor := Vector3.INF         # 坚守点
var marker: Label3D               # 头顶的 ◆
var want_speed := 0.0             # 这一帧想走多快（走向位置时）
var blocked_t := 0.0
var dodge_t := 0.0
var dodge_dir := 1.0
var last_pos := Vector3.INF
var morale := 70.0
var morale_max := 90.0
var morale_t := 0.0
var is_captain := false
var counted_fall := false         # 倒下 / 求饶 / 逃跑已经报给军阵了（只算一次）
var broke := false                # 是被吓跑的（士气崩了），不是被打倒的：对同伴的影响减半
var pennant: Node3D


static func create(kind_id: String, id: String, side_id: String, coat: Color, band_c: Color) -> Soldier:
	var s := Soldier.new()
	s.kind = kind_id
	s.enemy_id = id
	s.side = side_id
	s.coat_color = coat
	s.band_color = band_c
	return s


func _ready() -> void:
	super._ready()
	transient = true
	drops_loot = false
	add_to_group("soldier")
	coat_mat.albedo_color = coat_color
	_build_band()
	name_label.visible = false
	status_label.visible = false
	retarget_t = randf() * RETARGET           # 相位错开：不让所有兵在同一帧挑对手
	is_captain = kind == "captain"
	morale = float(MORALE_START.get(kind, 70.0))
	morale_max = minf(morale + 20.0, 100.0)
	morale_t = randf() * MORALE_TICK
	if is_captain:
		_build_pennant()
	if battle and battle.is_friendly(side):
		remove_from_group("enemy")
		remove_from_group("damageable")
		add_to_group("ally")
		collision_layer = 1                   # 不在第 4 层「可受击」：玩家的剑扫不到
	if in_squad:
		_build_marker()


## 编进玩家的小队（Battle.add_to_squad 调用；进场景之前之后都行）
func set_squad(i: int) -> void:
	in_squad = true
	slot = i
	if is_inside_tree():
		_build_marker()


## 队长背上的小旗：一根细杆 + 一面布带颜色的旗（挂在身子上，倒下时跟着倒）
func _build_pennant() -> void:
	pennant = Node3D.new()
	pennant.name = "Pennant"
	pennant.position = Vector3(-0.12, 0.0, 0.22)
	body.add_child(pennant)
	var pole := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.03, 1.1, 0.03)
	pm.material = Look.mat("timber")
	pole.mesh = pm
	pole.position.y = 1.65
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pennant.add_child(pole)
	var flag := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.02, 0.26, 0.4)
	fm.material = Blocks.mat(band_color)
	flag.mesh = fm
	flag.position = Vector3(0.0, 2.05, 0.2)
	flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pennant.add_child(flag)


## 士气变化（B.3）；掉到 MORALE_BREAK 以下就撑不住了
func shake(d: float) -> void:
	if not fighting() or d == 0.0:
		return
	morale = clampf(morale + d, 0.0, morale_max)
	if morale <= MORALE_BREAK and battle and battle.active():
		break_rank()


## 撑不住了：逃跑，或者（看性子）原地跪地求饶；全军溃逃时也走这里
func break_rank() -> void:
	if not fighting():
		return
	morale = 0.0
	broke = true
	_enter(State.YIELD if rng.randf() < float(data.yield_chance) * 0.5 else State.FLEE)
	if _near_player(12.0):
		FloatText.spawn(self, "撤！" if state == State.FLEE else "别打了！", Vector3(0, 1.9, 0), Color("ffcf6a"), 26)


func _build_marker() -> void:
	if marker != null:
		return
	marker = Blocks.label(self, "◆", Vector3(0, 2.3, 0), 30, 0.0012)
	marker.fixed_size = true
	marker.modulate = Color("e8c060")
	marker.visible = fighting()


## 胸前一道布带（白 / 黑），隔着一段距离也认得出是哪一边
func _build_band() -> void:
	band = MeshInstance3D.new()
	band.name = "Band"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.315
	cm.bottom_radius = 0.315
	cm.height = 0.16
	cm.radial_segments = 12
	cm.rings = 1
	cm.material = Blocks.mat(band_color)
	band.mesh = cm
	band.position.y = 1.05
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(band)


func foe() -> Node3D:
	return target if target != null and is_instance_valid(target) else null


func rep_faction() -> String:
	return faction_id


## 还在打（活着、没求饶、没逃）：军阵用它算谁还能当对手
func fighting() -> bool:
	return state not in [State.DEAD, State.YIELD, State.FLEE]


## 军阵里不潜行：开战就知道对手在哪，也不对兵打视线射线
func _perceive(_dt: float) -> void:
	if not fighting():
		return
	var f := foe()
	sees_foe = f != null
	sees_player = f == player
	if f:
		last_known = f.global_position
		since_seen = 0.0


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if battle and battle.active() and fighting():
		retarget_t -= delta
		var lost := target != null and not battle.can_fight(target)
		if lost or (retarget_t <= 0.0 and action not in ["windup", "strike", "recover", "block"]):
			retarget_t = RETARGET
			_retarget(lost)
	if battle and battle.active() and fighting():
		morale_t -= delta
		if morale_t <= 0.0:
			morale_t = MORALE_TICK
			battle.morale_tick(self, MORALE_TICK)
	want_speed = 0.0
	super._physics_process(delta)
	_check_blocked(delta)
	# 挤在人堆里够不着对手：别一直占着令牌（试验场里实测会互相卡死）
	if has_token and action not in ["windup", "strike", "recover", "block"]:
		approach_t += delta
		if approach_t >= STUCK_TIME:
			_release_token()
			token_cd = rng.randf_range(0.5, 1.0)
			approach_t = 0.0
			retarget_t = 0.0
	else:
		approach_t = 0.0


## 挑对手（Battle.pick_target）；换了人就先把手里的攻击令牌交回
func _retarget(force: bool) -> void:
	var t := battle.pick_target(self)
	if t != target:
		if has_token:
			_release_token()
		if force:
			action = ""
			action_t = 0.0
		battle.set_aim(self, t)
		target = t
		nav_target = Vector3.INF
	status_label.visible = not (battle and battle.is_friendly(side)) and _near_player(LABEL_NEAR)


## 小队的兵该站的位置（B.2）；没有就是 null（冲锋、不在小队）
func post() -> Variant:
	return battle.post_of(self) if battle and in_squad else null


## 走到自己的位置；到了就面朝队形的方向站好
func _go_post(delta: float, p: Vector3) -> Vector3:
	var d := _flat(p - global_position).length()
	if d <= 0.6:
		_face(global_position + battle.post_facing(self), delta)
		return Vector3.ZERO
	var v := _steer(p, float(data.run) if d > 1.5 else float(data.walk), 0.5)      # 离位置远就跑，最后一两步走
	if dodge_t > 0.0:                    # 正被人挡着：往旁边偏着走一会儿
		dodge_t -= delta
		v = v.rotated(Vector3.UP, deg_to_rad(DODGE_ANGLE) * dodge_dir)
		move_dir = v.normalized()
	want_speed = v.length()
	if move_dir != Vector3.ZERO:
		_face(global_position + move_dir, delta)
	return v


## 想走却几乎没挪动（迎面撞上玩家或别的兵，滑不开）：往左或往右绕一下
func _check_blocked(delta: float) -> void:
	var moved := _flat(global_position - last_pos).length() if last_pos != Vector3.INF else 0.0
	last_pos = global_position
	if want_speed < 0.5 or dodge_t > 0.0:
		blocked_t = 0.0
		return
	if moved < want_speed * delta * 0.3:
		blocked_t += delta
		if blocked_t >= BLOCKED_TIME:
			blocked_t = 0.0
			dodge_t = DODGE_TIME
			dodge_dir = 1.0 if rng.randf() < 0.5 else -1.0
	else:
		blocked_t = 0.0


## 没开打（或打完收手）时：小队跟随 / 坚守就去自己的位置，否则照常站岗
func _patrol(delta: float) -> Vector3:
	var p: Variant = post()
	if p != null:
		return _go_post(delta, p)
	return super._patrol(delta)


## 打着仗但拴绳范围里没有对手：回到自己的位置
func _combat(delta: float) -> Vector3:
	if foe() == null:
		var p: Variant = post()
		if p != null:
			return _go_post(delta, p)
	return super._combat(delta)


## 仗打完了：还站着的人收手，原地站着（不再算「附近有敌人在和你打」）
func stand_down() -> void:
	if not fighting():
		return
	if has_token:
		_release_token()
	if battle:
		battle.set_aim(self, null)
	target = null
	waypoints = [global_position]
	wp_index = 0
	_enter(State.PATROL)


func _enter(s: State) -> void:
	super._enter(s)
	if s == State.YIELD:
		collision_layer = 0                   # 跪地求饶的不挡路（试验场里实测：跪着的人堆在中间，两边都挤不过去）
	if marker:
		marker.visible = s not in [State.DEAD, State.YIELD, State.FLEE]
	if s in [State.DEAD, State.YIELD, State.FLEE] and battle:
		battle.set_aim(self, null)            # 不打了：不再占着那个目标的「被盯」名额（逃跑的仍记得 target，好知道躲着谁）
		if s != State.FLEE:
			target = null
		if not counted_fall:
			counted_fall = true
			battle.on_fall(self)              # 士气与溃逃（B.3）
