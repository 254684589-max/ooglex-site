class_name Chapter2
extends RefCounted
## 第二章的剧情规则（路线图 5.8；STORY.md 5.5 第 8 步「天亮 · 火还在不在」）：第二夜过去（劫粮 / 护粮打完，或者两手空空熬过去）调 dawn()——
## 粮上了山（ch2_convoy 在 FED 里）第十九烽的火还亮着，ch2_fire = lit；没上来（被打退、一车也没上来、两手空空）火熄了，out。
## 主线推进到「天亮以后」：回烽燧，诺伯特在塔顶火盆边（亮着站着，灭了蹲在冷灰边）说完剩下的话，要带你翻过山脊去看冬井（to_well，5.8b）。

const FED := ["taken", "burned", "delivered", "partial"]
const DAWN_STAGES := ["dawn_after", "to_well", "ch2_end"]


## 天亮了：火亮不亮、主线
static func dawn() -> void:
	GameState.set_flag("ch2_fire", "lit" if str(GameState.get_flag("ch2_convoy", "")) in FED else "out")
	if GameState.quest_active("ch2_main"):
		GameState.set_stage("ch2_main", "dawn_after")


## 天亮以后（诺伯特在塔顶，不在小屋）
static func at_dawn() -> bool:
	return GameState.chapter == 2 and GameState.quest_stage("ch2_main") in DAWN_STAGES


static func fire_out() -> bool:
	return str(GameState.get_flag("ch2_fire", "")) == "out"


## 诺伯特在塔顶火盆边（天亮以后、还没说完；说完了他下去，在山脊背后等你，WinterWell）
static func norbert_on_roof() -> bool:
	return GameState.chapter == 2 and GameState.quest_stage("ch2_main") == "dawn_after"


## 章末的回顾（5.8b）：按这一章的旗标写几句（第一夜、第十八烽、粮、征粮令、火、妮尔、卡斯滕）
static func recap() -> String:
	var out := []
	match str(GameState.get_flag("ch2_first_tide", "")):
		"held":
			out.append("第一夜，栅外那排火把把潮水引开了，营里一个人没少。")
		"lost_one":
			out.append("第一夜，潮水漫进了营地，数麻袋的兵再也没回来。")
	if str(GameState.get_flag("ch2_beacon18", "")) == "lit":
		out.append("你把熄了的第十八烽重新点着了。")
	match str(GameState.get_flag("ch2_convoy", "")):
		"taken":
			out.append("第二夜，你们在盘山路上劫下了洛蒙德家的五车粮。")
		"burned":
			out.append("第二夜，你们劫了洛蒙德家的粮车，可有车着了火。")
		"repelled":
			out.append("第二夜，劫粮的人被押车兵打散了。")
		"delivered":
			out.append("你说动了安塞尔姆，第二夜护着粮车穿过了潮水。")
		"partial":
			out.append("你说动了安塞尔姆，可第二夜只有一车粮翻过了山脊。")
		"lost":
			out.append("你说动了安塞尔姆，可第二夜粮车一车也没能上山。")
		_:
			if str(GameState.get_flag("ch2_aid", "")) == "refused":
				out.append("安塞尔姆不肯，你们两手空空回了烽燧。")
	if GameState.has_flag("ch2_requisition"):
		out.append("罗薇娜的征粮令用上了——洛蒙德家会把这笔账记在厄尔德家头上。")
	if GameState.has_flag("ch2_fire"):
		out.append("天亮时，第十九烽的火还亮着。" if not fire_out() else "天亮时，第十九烽的火熄了。")
	match str(GameState.get_flag("ch2_nell", "")):
		"stopped":
			out.append("妮尔留在了羊脊村。")
		"seen":
			out.append("你告诉妮尔，她父亲走得很稳。她留在了村里。")
		"left":
			out.append("妮尔往北去了。")
	match str(GameState.get_flag("ch2_roll", "")):
		"served":
			out.append("你在名册上那个「逃」字旁边，认下了一个「补」字。")
		"struck":
			out.append("烽誓团的名册上，你的名字被抹成了一团黑。")
		"denied":
			out.append("马蒂亚斯翻开名册，你说他认错了人。")
	match str(GameState.get_flag("ch2_carsten", "")):
		"freed":
			out.append("卡斯滕守满了十年，下山去了。")
		"fled":
			out.append("卡斯滕夜里溜走了。")
		"stayed":
			out.append("卡斯滕又守了一年。")
	return "".join(out)


## 章末的钩子：加冕礼少做的那一步、冬井边的那一圈人、第三章的入口
static func hook() -> String:
	var s := "诺伯特说：加冕礼那一夜，封誓少做了一步；封好的誓瓶本该送进冬井。冰原上，长眠的人围着冬井站成一圈，一动不动，脸都朝着井。"
	if FirstTide.SEEN_NAMES.has(str(GameState.get_flag("ch1_sleeper", ""))):
		s += "芦栈村那个人也站在里面。"
	if str(GameState.get_flag("ch2_nell", "")) == "left":
		s += "妮尔也在。"
	if GameState.clues.has("vigil_page"):
		s += "当年守灵夜跪在老王脚边的那个侍从，去了南边金穗平原的修道院。"
	return s
