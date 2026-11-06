class_name Chapter3
extends RefCounted
## 第三章的剧情规则（路线图 6.8b；STORY.md 6.5 第 8–9 步「守灵夜」「章末」）：
## 伊格纳兹修士只肯对一个「替穷人做过事」的人开口——poor_deed() 按这一章的旗标看你做没做过（进抄经室时 settle() 记成 ch3_poor_deed）；
## 听完守灵夜（ch3_vigil）晨钟响，第三章完（ch3_done，main._ch3_bell）；章末画面的回顾和钩子按旗标写（EndingPanel.open_chapter3）。


## 这个冬天替挨饿的人做过的事（第一件；"" = 没做过）
static func poor_deed() -> String:
	if GameState.has_flag("ch3_granary_opened"):
		return "opened"
	if str(GameState.get_flag("ch3_evidence_to", "")) == "tenants":
		return "read"
	if str(GameState.get_flag("ch3_soup", "")) == "done":
		return "soup"
	if str(GameState.get_flag("ch3_ida", "")) == "witness":
		return "ida"
	if str(GameState.get_flag("ch3_apprentice", "")) == "freed":
		return "apprentice"
	if GameState.has_flag("ch3_tenants_spared"):
		return "spared"
	return ""


## 进抄经室：做过的记下来（对话的条件只能看旗标）
static func settle() -> void:
	var d := poor_deed()
	if d != "":
		GameState.set_flag("ch3_poor_deed", d)


## 章末的回顾：站哪边、开仓、磨坊、水渠、罪证交给谁、三条支线、院长凭什么放人
static func recap() -> String:
	var out := []
	match str(GameState.get_flag("ch3_side", "")):
		"lomond":
			out.append("那一夜，你替伊莎贝拉守磨坊。")
		"severin":
			out.append("那一夜，你跟着奥迪隆的兵下去「征」磨坊。")
		"tenants":
			out.append("那一夜，你先带麦渡的人撬开了粮仓，" + ("护院撤回了庄园，只有佃农拿着棍棒跟你守。" if GameState.has_flag("ch3_guards_left") else "再跟护院一起守磨坊。"))
	if GameState.has_flag("ch3_flanked"):
		out.append("你的小队顺着水渠绕到缺口外，打在第二拨背后。")
	match str(GameState.get_flag("ch3_mill", "")):
		"held":
			out.append("磨坊守到了天亮。" + ("奥迪隆倒在缺口外的麦茬地里。" if GameState.has_flag("ch3_odilon_down") else ""))
		"lost":
			out.append("磨坊没守住，粮被扛上了砧山。")
		"seized":
			out.append("你们抢下了磨坊，粮车连夜往砧山去了。" + ("老贝恩的人守着第一座仓，你让开了。" if GameState.has_flag("ch3_tenants_spared") else ""))
		"repelled":
			out.append("你们没打进磨坊。")
	var ev := str(GameState.get_flag("south_evidence", ""))
	var what: String = {"lomond": "洛蒙德家的粮仓账本", "severin": "摄政的信", "both": "粮仓账本和摄政的信"}.get(ev, "")
	match str(GameState.get_flag("ch3_evidence_to", "")):
		"abbey":
			if what != "":
				out.append("你把%s交给了院长。" % what)
		"tenants":
			if what != "":
				out.append("你当着麦渡全村念了%s。" % what + ("伊达站出来作证。" if str(GameState.get_flag("ch3_ida", "")) == "witness" and ev != "severin" else ""))
		"kept":
			out.append(("%s还在你手里。" % what) if what != "" else "你什么都没交出去。")
	if str(GameState.get_flag("ch3_soup", "")) == "done":
		out.append("坠星院的粥锅里，第一回立住了勺子。")
	match str(GameState.get_flag("ch3_apprentice", "")):
		"freed":
			out.append("熔炉车上的学徒顺着河溜走了。")
		"handed":
			out.append("你把熔炉车上的学徒交还给了奥迪隆。")
	if str(GameState.get_flag("ch3_monk_freed", "")) == "waited":
		out.append("院长说不动，你在门洞外等了一个上午。")
	return "".join(out)


## 章末的钩子：守灵夜那一夜、誓瓶、第四章的入口
static func hook() -> String:
	var s := "伊格纳兹说：老王咽气前，把铁冠亲手交给了一个从双钥港来的人，那人手上戴着双钥交叉的戒指。"
	if GameState.has_flag("knows_double_key_ring"):
		s += "霜渡镇那个南方人手上，就是这一枚。"
	if GameState.has_flag("ch3_vial_heard"):
		s += "他还说：封誓的誓瓶是空的——诺伯特捧着它走出去，在第十九烽守了三十五年。"
	s += "双钥港在灰鲸河的入海口，所有家族都欠那里的钱。"
	return s
