class_name Soldier
extends Enemy
## 军阵战斗的士兵（路线图 B.1，D8「中型战斗」；GDD.md 6.4，TECH.md 4.10）。
## 在 Enemy 上加一个阵营（side）：对手不再固定是玩家，而是军阵（Battle）挑给它的最近的敌方——另一个兵，或者玩家。
## 每 RETARGET 秒（相位错开）重新挑一次；对手倒下、求饶、逃跑时马上换。挑的时候避开已经被很多人盯着的目标，战场散成一对一、二对一。
## 开战即进入战斗，不走潜行感知（对兵不打视线射线）；数值在 data/enemies.json（soldier 剑兵、levy 民兵）。
## 玩家这一边的兵（友军）不在组 enemy、不在可受击层：玩家的剑砍不到自己人，存档、出门的「附近有敌人」也不算它们。
## 普通兵 transient：倒下、求饶不写进存档，不留搜刮点（存不存在 B.3 定）。外观仍是占位胶囊：罩袍按阵营上色，胸前一道白 / 黑布带。

const RETARGET := 0.25            # 多久重新挑一次对手（秒）
const LABEL_NEAR := 6.0           # 敌方的兵离玩家这么近才显示头顶的状态（几十个兵都显示，Label3D 太费绘制调用，画面也乱；友军不显示）
const STUCK_TIME := 2.5           # 拿着攻击令牌却这么久没能出招（被人挡住了）：交回令牌，让别人上

var side := ""                    # 阵营编号（Battle.sides 的键）
var battle: Battle
var target: Node3D                # 现在的对手：另一个 Soldier 或玩家；没有敌人了为空
var faction_id := ""              # 玩家打倒时扣哪个势力的声望（"" = 不扣，例如试验场）
var coat_color := Color("4a5260")
var band_color := Color.WHITE
var retarget_t := 0.0
var approach_t := 0.0             # 拿着令牌往前凑了多久还没出招
var band: MeshInstance3D


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
	if battle and battle.is_friendly(side):
		remove_from_group("enemy")
		remove_from_group("damageable")
		add_to_group("ally")
		collision_layer = 1                   # 不在第 4 层「可受击」：玩家的剑扫不到


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
	super._physics_process(delta)
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
	if s in [State.DEAD, State.YIELD, State.FLEE] and battle:
		battle.set_aim(self, null)            # 不打了：不再占着那个目标的「被盯」名额（逃跑的仍记得 target，好知道躲着谁）
		if s != State.FLEE:
			target = null
