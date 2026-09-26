class_name Quests
extends RefCounted
## 第一幕的三条任务（P8，移植 V0.1 talk / npcMark / questLog / goFloor / bossDown 里的任务逻辑）。
## 任务状态存在角色存档 sheet.q：{q1, q2, q3}，0 未接、1 进行中、2 可交付、3 已完成（同 V0.1 hero.q）。
##   q1 地窖里的钟声：伊莲给；到达第 2 层变为可交付；奖励生命药水 ×3、法力药水 ×2、120 经验。
##   q2 铁匠的学徒：接了 q1 后格伦给；击败第 3 层的莫格（首领在 P9）变为可交付；奖励稀有武器、400 经验，托比回到镇上。
##   q3 余烬之心：q2 完成或到过第 4 层后伊莲给；击败第 6 层的摩登（P9）变为可交付并播放结局文字；奖励传奇物品、1500 经验。
## 台词在 act1_dialogs.json 的 quest / quest_log；这里只做判断与状态变化，不碰界面。


## 与 NPC 对话时该走的任务分支（V0.1 talk 的判断顺序）；没有任务分支返回 ""（日常对话）
static func branch(npc_id: String, sh: Dictionary) -> String:
	var q: Dictionary = sh.q
	if npc_id == "elin":
		if q.q1 == 0:
			return "elin_q1_offer"
		if q.q1 == 2:
			return "elin_q1_turnin"
		if q.q3 == 0 and (q.q2 == 3 or int(sh.maxFloor) >= 4):
			return "elin_q3_offer"
		if q.q3 == 2:
			return "elin_q3_turnin"
	elif npc_id == "gren":
		if q.q2 == 0 and q.q1 >= 1:
			return "gren_q2_offer"
		if q.q2 == 2:
			return "gren_q2_turnin"
	return ""


## NPC 头顶的标记（V0.1 npcMark）：「!」有新任务，「?」可以交任务
static func mark(npc_id: String, sh: Dictionary) -> String:
	var b := branch(npc_id, sh)
	if b.ends_with("_offer"):
		return "!"
	if b.ends_with("_turnin"):
		return "?"
	return ""


## 伊莲日常对话的第一句（随任务进度变化）
static func elin_idle(sh: Dictionary) -> String:
	var idle: Dictionary = Act1Data.dialogs().elin.idle
	if sh.q.q3 == 1:
		return idle.q3_active
	if sh.q.q2 == 1:
		return idle.q2_active
	if sh.won:
		return idle.won
	return idle.default


## 选了任务分支的主选项：改任务状态、发奖励。
## 返回 {xp: 经验, pots: {hp, mp}, item: 奖励物品或 null, toby: 托比是否回镇, retalk: 是否接着再对话一次, log: 消息}
static func accept(key: String, sh: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var q: Dictionary = sh.q
	var r := {"xp": 0, "pots": {}, "item": null, "toby": false, "retalk": false, "log": String(Act1Data.dialogs().quest[key].get("log", ""))}
	match key:
		"elin_q1_offer":
			q.q1 = 1
		"elin_q1_turnin":
			q.q1 = 3
			sh.pots.hp += 3
			sh.pots.mp += 2
			r.pots = {"hp": 3, "mp": 2}
			r.xp = 120
			r.retalk = true
		"elin_q3_offer":
			q.q3 = 1
		"elin_q3_turnin":
			q.q3 = 3
			sh.won = true
			r.item = ItemGen.generate(rng, maxi(14, int(sh.lvl) + 2), {"rarity": 3})
			r.xp = 1500
		"gren_q2_offer":
			q.q2 = 1
		"gren_q2_turnin":
			q.q2 = 3
			r.item = ItemGen.generate(rng, maxi(8, int(sh.lvl) + 2), {"rarity": 2, "slot": "weapon"})
			r.xp = 400
			r.toby = true
	return r


## 到达第 f 层（V0.1 goFloor）：记录最深到过的层数；q1 进行中且到了第 2 层以下就可交付。返回任务消息或 ""
static func on_floor(sh: Dictionary, f: int) -> String:
	if f > int(sh.maxFloor):
		sh.maxFloor = f
	if sh.q.q1 == 1 and f >= 2:
		sh.q.q1 = 2
		return Act1Data.dialogs().quest_log.q1_update
	return ""


## 首领倒下（V0.1 bossDown，P9 的首领调用）：boss = "mog" / "mordan"。
## 返回 {log: 消息, epilogue: 是否播放结局文字}
static func on_boss_down(sh: Dictionary, boss: String) -> Dictionary:
	var r := {"log": "", "epilogue": false}
	if boss == "mog" and sh.q.q2 < 2:
		sh.q.q2 = 2
		r.log = Act1Data.dialogs().quest_log.q2_update
	elif boss == "mordan" and sh.q.q3 < 2:
		sh.q.q3 = 2
		r.epilogue = true
	return r


## 托比是否在镇上（V0.1：交了 q2 之后）
static func toby_home(sh: Dictionary) -> bool:
	return sh.q.q2 == 3


## 任务日志（V0.1 questLog）：[{title, state, text}]，没接任何任务时为空
static func log_entries(sh: Dictionary) -> Array:
	var L: Dictionary = Act1Data.dialogs().quest_log
	var out: Array = []
	for k in ["q1", "q2", "q3"]:
		var st := int(sh.q[k])
		if st > 0:
			out.append({"id": k, "title": L[k].title, "state": st, "text": L[k][str(st)]})
	return out
