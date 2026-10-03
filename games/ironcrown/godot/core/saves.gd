extends Node
## 存档（路线图 2.8；GDD.md 第十节；TECH.md 4.7）。自动加载为 Saves。
## 栏位：slot1 / slot2 / slot3（手动）、auto（自动）、quick（快速）。每个栏位存两份：当前 + 上一份。
## 网页写浏览器 localStorage（键名 ooglex.ironcrown.v1.<栏位>，上一份是 <栏位>.prev）；其他平台写 user://saves/<栏位>.json。
## 规则：
##   - 写入前先校验，内容不完整就不写（不用空数据覆盖有效存档）；写入时把原来那份挪成「上一份」。
##   - 读档逐版本迁移（MIGRATIONS）；来自更新版本的存档不读；当前这份坏了就退回上一份，并说明。
##   - 设置单独存一份（键名 ooglex.ironcrown.v1.settings），和游戏存档互不影响。
## 存档里只有游戏状态，没有任何账号、密钥或个人信息。

const PREFIX := "ooglex.ironcrown.v1."
const VERSION := 1
const SLOTS := ["slot1", "slot2", "slot3", "auto", "quick"]
const MANUAL := ["slot1", "slot2", "slot3"]
const SLOT_NAMES := {"slot1": "栏位 1", "slot2": "栏位 2", "slot3": "栏位 3", "auto": "自动存档", "quick": "快速存档"}
const SCENE_NAMES := Areas.NAMES          # 存档里的场景 = 区域名（3.1 起由 world/areas.gd 统一登记）

## 版本迁移：旧版本号 → 把字典升到下一版的函数（第一版还没有旧格式；测试里会临时塞一条验证流程）
var migrations := {}
var dir := "user://saves/"        # 非网页平台的存档目录（测试改到别处）
var use_web := OS.has_feature("web")
var last_error := ""


func _init() -> void:
	# 自动化测试用单独的目录，不碰真正的存档和设置（测试开始时清空它）
	for a in OS.get_cmdline_args():
		if str(a).begins_with("res://tests/"):
			dir = "user://test_saves/"


# ---------------- 底层读写 ----------------

func _key(slot: String) -> String:
	return PREFIX + slot


func _read_raw(key: String) -> String:
	if use_web:
		var v = JavaScriptBridge.eval("(function(){try{return localStorage.getItem(%s)}catch(e){return null}})()" % JSON.stringify(key), true)
		return str(v) if v != null else ""
	var path := dir + key + ".json"
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f else ""


func _write_raw(key: String, text: String) -> bool:
	if use_web:
		# 不靠 eval 的返回值判断成没成功（网页里它的类型不一定是布尔，2.8 冒烟测试发现）：写完读回来比一下
		JavaScriptBridge.eval("(function(){try{localStorage.setItem(%s,%s)}catch(e){}})()" % [JSON.stringify(key), JSON.stringify(text)], true)
		return _read_raw(key) == text
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + key + ".json", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	return true


func _remove_raw(key: String) -> void:
	if use_web:
		JavaScriptBridge.eval("(function(){try{localStorage.removeItem(%s)}catch(e){}})()" % JSON.stringify(key), true)
	elif FileAccess.file_exists(dir + key + ".json"):
		DirAccess.remove_absolute(dir + key + ".json")


# ---------------- 校验与迁移 ----------------

## 校验一份存档；返回错误说明（空字符串 = 没问题）
func check_save(d) -> String:
	if typeof(d) != TYPE_DICTIONARY:
		return "不是有效的存档"
	if not d.has("version"):
		return "存档缺少版本号"
	if int(d.version) > VERSION:
		return "这是更新版本的游戏写的存档（版本 %d），当前版本 %d 读不了" % [int(d.version), VERSION]
	for k in ["scene", "player", "state"]:
		if not d.has(k):
			return "存档缺少 %s" % k
	if not SCENE_NAMES.has(str(d.scene)):
		return "存档里的场景不认识"
	var p = d.player
	if typeof(p) != TYPE_DICTIONARY or not p.has("pos") or (p.pos as Array).size() != 3:
		return "存档里的玩家位置不对"
	var s = d.state
	if typeof(s) != TYPE_DICTIONARY or not s.has("inventory") or not s.has("seed"):
		return "存档里的游戏状态不完整"
	return ""


## 逐版本升到当前版本；升不上去返回空字典
func migrate(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	while int(out.get("version", 0)) < VERSION:
		var v := int(out.get("version", 0))
		if not migrations.has(v):
			last_error = "没有从版本 %d 升级的办法" % v
			return {}
		out = (migrations[v] as Callable).call(out)
		out.version = v + 1
	return out


## 不用 JSON.parse_string：解析失败时它会往控制台打引擎报错，坏档是预料之中的情况，自己处理就好
static func _json(text: String):
	var j := JSON.new()
	return j.data if j.parse(text) == OK else null


func _parse(text: String) -> Dictionary:
	if text == "":
		return {}
	var d = _json(text)
	if typeof(d) != TYPE_DICTIONARY:
		return {"_bad": "存档内容损坏（不是有效的 JSON）"}
	if d.has("version") and int(d.version) < VERSION:
		var m := migrate(d)
		if m.is_empty():
			return {"_bad": last_error}
		d = m
	var err := check_save(d)
	if err != "":
		return {"_bad": err}
	return d


# ---------------- 栏位 ----------------

## 写一个栏位：先校验，再把原来那份挪成上一份。返回是否成功（失败原因在 last_error）
func write_slot(slot: String, data: Dictionary) -> bool:
	last_error = ""
	if not slot in SLOTS:
		last_error = "没有这个栏位"
		return false
	var err := check_save(data)
	if err != "":
		last_error = err
		return false
	var old := _read_raw(_key(slot))
	if old != "" and not _parse(old).has("_bad"):
		_write_raw(_key(slot) + ".prev", old)     # 只把有效的旧存档留作上一份
	if not _write_raw(_key(slot), JSON.stringify(data)):
		last_error = "写不进浏览器存储（可能是无痕模式或空间满了）"
		return false
	return true


## 读一个栏位：返回 {data, note}；当前这份坏了退回上一份（note 写明），两份都不行返回 {error}
func read_slot(slot: String) -> Dictionary:
	var cur := _parse(_read_raw(_key(slot)))
	if not cur.is_empty() and not cur.has("_bad"):
		return {"data": cur, "note": ""}
	var prev := _parse(_read_raw(_key(slot) + ".prev"))
	if not prev.is_empty() and not prev.has("_bad"):
		return {"data": prev, "note": "这一份存档坏了（%s），已退回上一份" % cur.get("_bad", "")} if cur.has("_bad") else {"data": prev, "note": ""}
	if cur.has("_bad"):
		return {"error": cur._bad}
	return {}


## 栏位一览（存档面板用）：{slot: {summary, saved_at, note} 或 {error} 或 {}}
func list_slots() -> Dictionary:
	var out := {}
	for s in SLOTS:
		var r := read_slot(s)
		if r.has("data"):
			out[s] = {"summary": describe(r.data), "saved_at": str(r.data.get("saved_at", "")), "note": r.note}
		else:
			out[s] = r
	return out


## 最近一次的有效存档栏位（倒下时「读取最近的存档」）；没有返回空字符串
func latest_slot() -> String:
	var best := ""
	var best_t := ""
	for s in SLOTS:
		var r := read_slot(s)
		if r.has("data") and str(r.data.get("saved_at", "")) > best_t:
			best_t = str(r.data.get("saved_at", ""))
			best = s
	return best


func has_any() -> bool:
	return latest_slot() != ""


func delete_slot(slot: String) -> void:
	_remove_raw(_key(slot))
	_remove_raw(_key(slot) + ".prev")


## 一行说明：「霜渡镇 · 2 级 · 雾里的少爷 · 游戏时间 12 分钟」
func describe(d: Dictionary) -> String:
	var s: Dictionary = d.get("state", {})
	var parts := [str(SCENE_NAMES.get(str(d.get("scene", "")), "?")), "%d 级" % int(s.get("level", 1))]
	var qd := GameState.quest_data()
	for q in s.get("quests", {}):
		if qd.quests.has(q) and str(qd.quests[q].kind) == "main" and not bool(s.quests[q].get("done", false)):
			parts.append(str(qd.quests[q].title))
			break
	parts.append("游戏时间 %d 分钟" % int(float(s.get("playtime", 0.0)) / 60.0))
	return " · ".join(parts)


# ---------------- 设置 ----------------

func save_settings(d: Dictionary) -> void:
	_write_raw(PREFIX + "settings", JSON.stringify(d))


func load_settings() -> Dictionary:
	var t := _read_raw(PREFIX + "settings")
	if t == "":
		return {}
	var d = _json(t)
	return d if typeof(d) == TYPE_DICTIONARY else {}
