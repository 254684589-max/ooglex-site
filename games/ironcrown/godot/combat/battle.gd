class_name Battle
extends Node
## 一场军阵战斗（路线图 B.1，D8「中型战斗」；GDD.md 6.4，TECH.md 4.10）。
## 登记各方的兵（Soldier）、管同屏名额（同时活着、在打的兵双方合计 ≤ MAX_ACTIVE，多出来的排队，前面的人倒下、求饶、逃跑后补上）、
## 给每个兵挑对手（pick_target：最近的敌方，被别人盯得越多的目标越「远」，所以会散成一对一、二对一），
## 看哪一方还站着：只剩一方（玩家那一方算上玩家本人）时结束，还站着的兵收手（stand_down），发 ended(winner)。士气、溃逃、胜负旗标在 B.3。
## 60 人以内直接遍历找最近的敌人（每帧约 4 个兵重挑 × 60 次比较），不做空间分格。
## 攻击令牌（每个目标最多 2 个人同时出招）在 CombatDirector；这里只管「谁盯着谁」，用来分散目标。

signal ended(winner: String)

const MAX_ACTIVE := 60            # 同时活着、在打的兵（双方合计，不含玩家）
const CHECK_STEP := 0.25          # 多久检查一次名额与胜负（秒）
const SPREAD := 3.0               # 挑对手时：目标每多一个别人盯着，就当它远 3 米
const STICK := 1.0                # 现在的对手比新找到的最多只「远」这么多米，就不换（免得来回换）

var sides := {}                   # 阵营编号 → 显示名
var player_side := ""             # 玩家站哪一边（"" = 玩家不参战：兵不打玩家，玩家也不算一方）
var roster: Array = []            # 已经上场的兵
var reserve: Array = []           # 等名额的兵：[兵, 父节点]
var max_active := MAX_ACTIVE
var started := false
var finished := false
var winner := ""
var aim_of := {}                  # 兵的 instance id → 它盯着的目标的 instance id
var aimed := {}                   # 目标的 instance id → 被几个兵盯着
var check_t := 0.0
var t_start := 0
var player: FpController


func _ready() -> void:
	add_to_group("battle")


func add_side(id: String, display_name: String) -> void:
	sides[id] = display_name


## 这一边是玩家自己人吗（友军：玩家的剑砍不到，不算「附近有敌人」）
func is_friendly(side: String) -> bool:
	return player_side != "" and side == player_side


## 登记一个兵：有名额就放进场景（parent 下），没名额就排队
func enlist(s: Soldier, parent: Node3D) -> void:
	s.battle = self
	if active_count() < max_active:
		_deploy(s, parent)
	else:
		reserve.append([s, parent])


func _deploy(s: Soldier, parent: Node3D) -> void:
	parent.add_child(s)
	roster.append(s)
	if started:
		s.engage()


func start() -> void:
	if started:
		return
	started = true
	t_start = Time.get_ticks_msec()
	for s in roster:
		s.engage()
	print("IC_BATTLE start %s player=%s reserve=%d" % [_tally(), player_side if player_side != "" else "-", reserve.size()])


func active() -> bool:
	return started and not finished


## 现在场上还在打的兵（不含玩家）
func active_count() -> int:
	var n := 0
	for s in roster:
		if is_instance_valid(s) and s.fighting():
			n += 1
	return n


## 某一方还在打的兵（场上 + 排队的）
func side_count(side: String, with_reserve := true) -> int:
	var n := 0
	for s in roster:
		if is_instance_valid(s) and s.side == side and s.fighting():
			n += 1
	if with_reserve:
		for r in reserve:
			if r[0].side == side:
				n += 1
	return n


func _player() -> FpController:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as FpController
	return player


func _player_fights() -> bool:
	var p := _player()
	return player_side != "" and p != null and not p.melee.down


## 这个目标还能打吗（兵：没倒下、没求饶、没逃；玩家：参战且没倒下）
func can_fight(t: Node) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	if t is Soldier:
		return (t as Soldier).fighting()
	if t is FpController:
		return _player_fights() and t == _player()
	return false


## 给兵挑对手：最近的敌方（另一方的兵，或者站在别一方的玩家）；被别人盯着的目标按每人 SPREAD 米算远；
## 现在的对手还能打、又只比最好的「远」STICK 米以内，就不换
func pick_target(s: Soldier) -> Node3D:
	var best: Node3D = null
	var best_score := INF
	var cur_score := INF
	var pos := s.global_position
	for o in roster:
		if not is_instance_valid(o) or o.side == s.side or not o.fighting():
			continue
		var sc := _score(s, o, pos)
		if o == s.target:
			cur_score = sc
		if sc < best_score:
			best = o
			best_score = sc
	if _player_fights() and s.side != player_side:
		var sc := _score(s, player, pos)
		if player == s.target:
			cur_score = sc
		if sc < best_score:
			best = player
			best_score = sc
	if cur_score < INF and cur_score <= best_score + STICK:
		return s.target
	return best


func _score(s: Soldier, o: Node3D, pos: Vector3) -> float:
	var n := int(aimed.get(o.get_instance_id(), 0))
	if aim_of.get(s.get_instance_id(), 0) == o.get_instance_id():
		n -= 1                                     # 自己盯着它不算「别人」
	var d := Vector2(o.global_position.x - pos.x, o.global_position.z - pos.z).length()
	return d + SPREAD * maxi(n, 0)


## 记下兵 s 现在盯着谁（t = null：不盯了）；可以重复调用
func set_aim(s: Soldier, t: Node3D) -> void:
	var sid := s.get_instance_id()
	var tid := t.get_instance_id() if t != null else 0
	var old: int = aim_of.get(sid, 0)
	if old == tid:
		return
	if old != 0:
		aimed[old] = maxi(int(aimed.get(old, 0)) - 1, 0)
		if aimed[old] == 0:
			aimed.erase(old)
		aim_of.erase(sid)
	if tid != 0:
		aim_of[sid] = tid
		aimed[tid] = int(aimed.get(tid, 0)) + 1


## 有多少个兵盯着这个目标（测试与调试用）
func aimed_at(t: Node) -> int:
	return int(aimed.get(t.get_instance_id(), 0)) if t != null else 0


func _physics_process(delta: float) -> void:
	if not started or finished:
		return
	check_t -= delta
	if check_t > 0.0:
		return
	check_t = CHECK_STEP
	while not reserve.is_empty() and active_count() < max_active:      # 有人倒下、求饶、逃了：排队的补上
		var r: Array = reserve.pop_front()
		_deploy(r[0], r[1])
	var standing := []
	for side in sides:
		if side_count(side) > 0 or (side == player_side and _player_fights()):
			standing.append(side)
	if standing.size() <= 1:
		finished = true
		winner = str(standing[0]) if standing.size() == 1 else ""
		for s in roster:
			if is_instance_valid(s):
				s.stand_down()                 # 赢的一方收手、原地站着
		print("IC_BATTLE end winner=%s %s secs=%.1f" % [winner if winner != "" else "-", _tally(), (Time.get_ticks_msec() - t_start) / 1000.0])
		ended.emit(winner)


func _tally() -> String:
	var parts := []
	for side in sides:
		parts.append("%s:%d" % [side, side_count(side)])
	return " ".join(parts)


## 还在排队、没进场景的兵不归场景树管：战斗释放时一起释放（不然测试退出时报泄漏）
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for r in reserve:
			if is_instance_valid(r[0]) and not r[0].is_inside_tree():
				r[0].free()
		reserve.clear()
