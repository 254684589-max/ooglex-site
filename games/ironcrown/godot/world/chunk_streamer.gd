class_name ChunkStreamer
extends Node
## 连片地图的分块搭建与显示（路线图 4.4，D10-B；TECH.md 4.15）。网页版没有线程，一次搭完一整张图会卡住，所以：
##   1. 碰撞一次建完（区域脚本在搭场景时就建好，这里不管）：读档、出生点、传送、?cam 落在哪儿脚下都有地，不会掉下去；
##   2. 画面按块排成一串小活（一块的地面网格、一栋房子、一片芦苇……），每帧做到 BUDGET 微秒为止（至少一件），先做离主角近的块；
##      一块的活全做完才显示（不会看见房子一栋栋冒出来），并发 chunk_built：main 给它补上时段（窗、夜灯、雾带）和画质（雾带减半、芦苇疏密）；
##   3. 每 CHECK 秒按主角到每块的距离显示 / 隐藏整块（只改块的根节点，块里的东西各管各的 visible）：雾在 view_dist 米外吞没一切，
##      离得比 view_dist + SHOW_PAD 近就显示，比 view_dist + HIDE_PAD 远才隐藏（来回走几步不闪）。不卸载：块搭好就一直在。
## 只管画面，不碰碰撞（碰撞体不能放进会停掉处理的节点下面：CollisionObject3D 默认停用时从物理世界里拿掉，TECH.md 4.15）。

signal chunk_built(root: Node3D)
signal all_built

const BUDGET_USEC := 6000            # 每帧最多花多少时间搭（电脑）
const BUDGET_TOUCH_USEC := 4000      # 触屏（手机慢）
const CHECK := 0.25
const SHOW_PAD := 4.0
const HIDE_PAD := 16.0
const REACH := 10.0                  # 块里的东西可能伸出方格几米（房子、堤道的石坡）：量距离时把方格放大这么多

var target: Node3D                   # 按谁量距离（主角）；没有时用 focus
var focus := Vector3.ZERO
var view_dist := 85.0                # 雾在几米外吞没（main 按时段改）
var budget := BUDGET_USEC
var host: Node3D                     # 块的根节点挂在哪（world）
var builder: RefCounted              # 活（Callable）所属的对象：Callable 不替对象保活，这里拿着它（不然搭完同步部分就被释放了）
var chunks := {}                     # 块编号 → {rect, jobs, next, root, done}
var stats := {"jobs": 0, "max_job_ms": 0.0, "total_ms": 0.0, "built": 0}
var check_left := 0.0
var primed := 0                      # 载入时同步搭好了几块（其余分帧搭）
var reported := false


## 登记一块：方格范围、要做的活（Callable，调用时传入这块的根节点）
func add_chunk(id: String, rect: Rect2, jobs: Array) -> void:
	chunks[id] = {"rect": rect, "jobs": jobs, "next": 0, "root": null, "done": jobs.is_empty()}


func is_done() -> bool:
	for id in chunks:
		if not chunks[id].done:
			return false
	return true


func root_of(id: String) -> Node3D:
	return chunks[id].root if chunks.has(id) else null


## 现在显示着的块
func visible_ids() -> Array:
	var out := []
	for id in chunks:
		var r: Node3D = chunks[id].root
		if r != null and r.visible:
			out.append(id)
	return out


func _pos() -> Vector3:
	return target.global_position if target != null and is_instance_valid(target) and target.is_inside_tree() else focus


## 点到这块（放大 REACH）的水平距离
func distance_to(id: String, p: Vector3) -> float:
	var r: Rect2 = (chunks[id].rect as Rect2).grow(REACH)
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.z, r.position.y, r.end.y))
	return q.distance_to(Vector2(p.x, p.z))


## 同步搭好 p 附近（radius 米以内）的块：载入时（黑屏还没淡开）、换固定机位、?cam 时用
func prime(p: Vector3, radius := 24.0) -> void:
	focus = p
	var ids := chunks.keys().filter(func(id): return not chunks[id].done and distance_to(id, p) <= radius)
	ids.sort_custom(func(a, b): return distance_to(a, p) < distance_to(b, p))
	for id in ids:
		while not chunks[id].done:
			_run_one(id)
	primed = stats.built
	update_visibility(true)
	if is_done():
		_report()                                      # 换机位时正好把最后几块搭完：_process 不会再报（审查）


## 全部搭完（测试用）
func build_all() -> void:
	for id in chunks:
		while not chunks[id].done:
			_run_one(id)
	update_visibility(true)
	_report()


func _process(delta: float) -> void:
	if not is_done():
		var t0 := Time.get_ticks_usec()
		var p := _pos()
		while true:
			var id := _nearest_pending(p)
			if id == "":
				break
			_run_one(id)
			if Time.get_ticks_usec() - t0 >= budget:
				break
		if is_done():
			update_visibility(true)
			_report()
	check_left -= delta
	if check_left <= 0.0:
		check_left = CHECK
		update_visibility()


func _nearest_pending(p: Vector3) -> String:
	var best := ""
	var bd := INF
	for id in chunks:
		if chunks[id].done:
			continue
		var d := distance_to(id, p)
		if d < bd:
			bd = d
			best = id
	return best


func _run_one(id: String) -> void:
	var c: Dictionary = chunks[id]
	if c.root == null:
		var root := Node3D.new()
		root.name = "Chunk_" + id
		root.visible = false                     # 活没做完不显示
		host.add_child(root)
		c.root = root
	var jobs: Array = c.jobs
	if c.next < jobs.size():
		var t0 := Time.get_ticks_usec()
		(jobs[c.next] as Callable).call(c.root)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		stats.jobs += 1
		stats.total_ms += ms
		stats.max_job_ms = maxf(stats.max_job_ms, ms)
		c.next += 1
	if c.next >= jobs.size():
		c.done = true
		stats.built += 1
		chunk_built.emit(c.root)
		print("IC_CHUNK id=%s jobs=%d" % [id, jobs.size()])


func _report() -> void:
	if reported:
		return
	reported = true
	print("IC_CHUNKS ready n=%d jobs=%d max_job_ms=%.1f total_ms=%.0f" % [stats.built, stats.jobs, stats.max_job_ms, stats.total_ms])
	all_built.emit()


## 按距离显示 / 隐藏搭好的块（force：不管上一次的状态，直接按「显示」的门槛定）
func update_visibility(force := false) -> void:
	var p := _pos()
	for id in chunks:
		var c: Dictionary = chunks[id]
		if not c.done or c.root == null:
			continue
		var d := distance_to(id, p)
		var r: Node3D = c.root
		if d <= view_dist + SHOW_PAD:
			r.visible = true
		elif force or d > view_dist + HIDE_PAD:
			r.visible = false
