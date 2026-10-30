class_name Chapter2
extends RefCounted
## 第二章的剧情规则（路线图 5.8；STORY.md 5.5 第 8 步「天亮 · 火还在不在」）：第二夜过去（劫粮 / 护粮打完，或者两手空空熬过去）调 dawn()——
## 粮上了山（ch2_convoy 在 FED 里）第十九烽的火还亮着，ch2_fire = lit；没上来（被打退、一车也没上来、两手空空）火熄了，out。
## 主线推进到「天亮以后」：回烽燧，诺伯特在塔顶火盆边（亮着站着，灭了蹲在冷灰边）说完剩下的话，要带你翻过山脊去看冬井（to_well，5.8b）。

const FED := ["taken", "burned", "delivered", "partial"]
const DAWN_STAGES := ["dawn_after", "to_well"]


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
