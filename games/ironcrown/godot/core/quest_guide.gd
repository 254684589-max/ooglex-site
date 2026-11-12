class_name QuestGuide
extends RefCounted
## 任务指引（路线图 C.2；所有者 2026-11-07「完成以后找不到诺伯特去哪里了，建议在所有任务里加入距离目标显示有多少米」
## 「不知道该如何指引下一步，建议在左上角显示任务，执行完的打勾，未执行的显示执行中」）。
##   跟踪哪个任务（tracked）：正在做的主线里章节最靠后的那条；没有主线在做就跟最近推进过的支线（GameState.last_quest）。
##   步骤（steps）：做过的步骤打勾（GameState.quests[id].log 记着走过的步骤，最多列最近两步），当前这一步「进行中」。
##   目标（target）：当前这一步的说明里提到了谁、什么东西——这一带里名字出现在说明里的可交互物（人、能看能用的东西、门、路牌）就是目标，
##     提到好几个就指最近的那个；data/quest_targets.json 可以按「任务 / 步骤」直接写目标的位置（说明里没有名字的那些步骤）。
##     这一带里没有：说明里提到了别的区域（「金穗平原」「冬井底」……），就写「在 ××」，不画标记。

const TARGETS_PATH := "res://data/quest_targets.json"
const SKIP_NAMES := ["门", "路牌", "梯子", "木桩假人"]    # 太泛的名字不拿来对（说明里「进门」「路牌」到处都是）

static var _targets := {}
static var _loaded := false


## 现在跟踪的任务（"" = 没有）
static func tracked() -> String:
	var best := ""
	var best_ch := -1
	var data: Dictionary = GameState.quest_data().get("quests", {})
	for id: String in GameState.quests.keys():
		if not GameState.quest_active(id):
			continue
		var q: Dictionary = data.get(id, {})
		if str(q.get("kind", "")) != "main":
			continue
		var ch := _chapter_of(id)
		if ch > best_ch:
			best_ch = ch
			best = id
	if best != "":
		return best
	var last := str(GameState.last_quest)
	if last != "" and GameState.quest_active(last):
		return last
	for id: String in GameState.quests.keys():
		if GameState.quest_active(id):
			return id
	return ""


static func _chapter_of(id: String) -> int:
	if id == "edric_missing":
		return 0
	var m := RegEx.create_from_string("^ch(\\d)").search(id)
	return int(m.get_string(1)) if m else 0


static func title_of(id: String) -> String:
	return I18n.t(str(GameState.quest_data().get("quests", {}).get(id, {}).get("title", id)))


static func objective(id: String, stage: String) -> String:
	var st: Dictionary = GameState.quest_data().get("quests", {}).get(id, {}).get("stages", {}).get(stage, {})
	if GameState.quest_stage(id) == stage:
		for o: Dictionary in st.get("objective_if", []):                 # 同一步里做完了一半，说明跟着变（2026-11-07：开仓那一步，护院头目说过以后指向粮仓的门）
			if GameState.has_flag(str(o.get("flag", ""))):
				return I18n.t(str(o.get("text", "")))
	return I18n.t(str(st.get("objective", "")))


## 步骤：[[文字, 做完了没有], …]，最后一条是现在这一步
static func steps(id: String, keep_done := 2) -> Array:
	if id == "" or not GameState.quests.has(id):
		return []
	var q: Dictionary = GameState.quests[id]
	var out := []
	var log: Array = q.get("log", [])
	for s in log.slice(maxi(0, log.size() - keep_done)):
		out.append([short(objective(id, str(s))), true])
	out.append([objective(id, str(q.stage)), bool(q.done)])
	return out


## 做完的那一步只留第一句（左上角地方小）
static func short(text: String) -> String:
	for sep in ["。", "：", "；", ". ", ": ", "; "]:
		var i := text.find(sep)
		if i > 0 and i < 40:
			return text.substr(0, i)
	return text.substr(0, 36) + ("…" if text.length() > 36 else "")


## 现在这一步的目标：{"node": Node3D} 或 {"pos": Vector3, "label": 名字} 或 {"elsewhere": 区域名} 或 {}
static func target(world: Node, from: Vector3, id: String, area: String) -> Dictionary:
	if id == "" or not GameState.quest_active(id):
		return {}
	var stage := GameState.quest_stage(id)
	var fixed: Dictionary = _target_data().get(id, {}).get(stage, {})
	if not fixed.is_empty():
		if str(fixed.get("area", area)) == area and fixed.has("at"):
			var a: Array = fixed.at
			return {"pos": Vector3(float(a[0]), float(a[1]), float(a[2])), "label": str(fixed.get("label", ""))}
		if str(fixed.get("area", "")) != "" and str(fixed.area) != area:
			return {"elsewhere": Areas.display_name(str(fixed.area))}
	var text := objective(id, stage)
	var best: Node3D = null
	var best_d := INF
	var best_len := 0
	for n in world.find_children("*", "Interactable", true, false):
		var nm := str((n as Interactable).display_name)
		if nm.length() < 2 or nm in SKIP_NAMES or not text.contains(nm) or not (n as Node3D).is_visible_in_tree():
			continue
		var d := (n as Node3D).global_position.distance_to(from)
		if nm.length() > best_len or (nm.length() == best_len and d < best_d):   # 名字更具体的优先（「第一座粮仓的门」胜过「粮仓的门」），一样具体的取近的
			best_len = nm.length()
			best_d = d
			best = n
	if best:
		return {"node": best, "label": (best as Interactable).display_name}
	for a: String in Areas.NAMES.keys():
		if a != area and text.contains(str(Areas.NAMES[a])):
			return {"elsewhere": str(Areas.NAMES[a])}
	return {}


## 距离怎么写：500 米以上按 50 米、100 米以上按 10 米、再近按 5 米，5 米以内写「就在附近」
static func distance_text(d: float) -> String:
	if d < 5.0:
		return I18n.t("就在附近")
	var step := 50.0 if d >= 500.0 else (10.0 if d >= 100.0 else 5.0)
	return I18n.t("%d 米") % int(roundf(d / step) * step)


static func _target_data() -> Dictionary:
	if not _loaded:
		_loaded = true
		var f := FileAccess.open(TARGETS_PATH, FileAccess.READ)
		var d: Variant = JSON.parse_string(f.get_as_text()) if f else null
		_targets = d if d is Dictionary else {}
	return _targets
