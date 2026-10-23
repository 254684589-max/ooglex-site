class_name Chapter1
extends RefCounted
## 第一章的剧情规则（路线图 4.8a；STORY.md 4.5 第 6 步「抉择」、4.7b 的水门表）：家主把印戒交给你，你交给阿尔里克或伊薇特（valen_heir），
## 另一位当场离堡，入夜前带着自己的人回来夺门。GameState.set_flag 设 valen_heir 时调 heir_chosen：
## 按婚事支线的结果算水门（ch1_water_gate），走了的那位托你的支线、埃德里克的婚事就此收尾（阶段 left）。
## 谁走了：gone(编号)——区域脚本（hall.gd、barracks.gd）不放、作息（Schedule）不摆、对话关上时 main 当场拿掉（remove_departed）。

## 选了这位继承人，另一位带走的人（NPC 编号）
const LEAVES_WITH := {
	"alric": ["ivette", "sergeant", "dice_soldier", "rack_soldier", "stove_soldier", "barracks_soldier"],      # 伊薇特带着兵营里她的人走（连兵营门口那个）
	"ivette": ["alric", "envoy"],                                                          # 阿尔里克带着塞弗林家的信使走
}
## 走了的那位托你的支线（还没做完的就此收尾）
const QUESTS_OF := {"alric": ["ch1_ledger"], "ivette": ["ch1_outlaws"]}


static func gone(id: String) -> bool:
	var h := str(GameState.get_flag("valen_heir", ""))
	return LEAVES_WITH.has(h) and id in LEAVES_WITH[h]


static func other_heir(h: String) -> String:
	return "ivette" if h == "alric" else "alric"


## 印戒交出去了：算水门、收尾支线
static func heir_chosen(h: String) -> void:
	if not h in ["alric", "ivette"]:
		return
	GameState.set_flag("ch1_water_gate", water_gate(h))
	for q in QUESTS_OF[other_heir(h)] + ["ch1_wedding"]:       # 婚事：水门已经按它的结果算了，之后不再变（做完，埃德里克、阿尔里克那里不再能了结它，4.8a 审查）
		if GameState.quest_active(q):
			GameState.set_stage(q, "left")
			GameState.complete_quest(q)
	if h == "alric":
		GameState.take_item("grain_writ")                      # 伊薇特走了，她的粮单用不上了


## 水门（STORY.md 4.7b 的表）：warned 埃德里克提醒过你（4.8b 能派两名卫兵先守）/ opened 他会给另一边开门（入夜后口才说得动就不开）/ unknown
static func water_gate(h: String) -> String:
	var edric := str(GameState.get_flag("ch1_edric", ""))
	if h == "ivette":
		return {"helped": "warned", "reported": "opened"}.get(edric, "unknown")
	if edric == "helped":
		return "opened"
	if edric == "" and str(GameState.get_flag("prologue_edric", "")) == "deliver":
		return "opened"
	return "unknown"


## 第一章的时段只往前走（4.8a 审查）：旅行地图的路线写着「到了是白天」，黄昏以后回霜渡镇再回来，不该又回到白天
const ORDER := ["dawn", "day", "dusk", "night"]


static func later_daypart(now: String, arrive: String) -> String:
	return arrive if ORDER.find(arrive) > ORDER.find(now) else now


## 对话关上时：走了的人当场拿掉；返回拿掉了几个
static func remove_departed(world: Node) -> int:
	var n := 0
	for id: String in LEAVES_WITH.get(str(GameState.get_flag("valen_heir", "")), []):
		var node := world.find_child("Npc_" + id, true, false)
		if node != null:
			node.get_parent().remove_child(node)
			node.queue_free()
			n += 1
	return n


## 章末的回顾（4.10b）：按这一章的旗标写几句（印戒、堤道、潜入、无旗者、账册、白芦根）
static func recap() -> String:
	var heir := str(GameState.get_flag("valen_heir", ""))
	var name := "阿尔里克" if heir == "alric" else "伊薇特"
	var other := "伊薇特" if heir == "alric" else "阿尔里克"
	var out := []
	if heir != "":
		out.append("你把家主的印戒交给了%s，%s带着自己的人离开了黑鹭堡。" % [name, other])
	match str(GameState.get_flag("ch1_causeway", "")):
		"held":
			out.append("那一夜，堤道守住了，%s的人退回了沼地。" % other)
		"lost":
			if str(GameState.get_flag("ch1_sneak", "")) == "caught":
				out.append("堤道丢了，%s入主黑鹭堡。你被押进病房——新家主从此不信你。" % other)
			else:
				out.append("堤道丢了，%s入主黑鹭堡。天亮时你从水门摸了进去，没人看见。" % other)
	match str(GameState.get_flag("ch1_outlaws", "")):
		"ally":
			out.append("奥弗那伙人从芦苇里杀出来，站在了瓦伦家这边。")
		"driven":
			out.append("你把无旗者赶出了鹭沼。")
		"beaten":
			out.append("你打散了沼地里的无旗者。")
	match str(GameState.get_flag("ch1_ledger", "")):
		"alric":
			out.append("皮毛税账册去了南边塞弗林家的信使手里。")
		"ivette":
			out.append("皮毛税账册烧在了兵营的炉子里。")
		"kept":
			out.append("皮毛税账册还在你身上。")
	return "".join(out)


## 章末的钩子：家主临终的话；喝过白芦根汤的多一句双钥港
static func hook() -> String:
	var s := "家主临终说：铁冠没有被偷，是老王自己交出去的。"
	if GameState.has_flag("ch1_herb"):
		s += "交给了一户靠海的人家——双钥港。"
	s += "当年守在门外的另一个侍从还活着，在北边的烽燧线上。"
	if GameState.has_flag("ch1_sleeper"):
		s += "天亮以后，芦栈村又有一个人没有醒来，闭着眼睛往北走了。"
	return s
