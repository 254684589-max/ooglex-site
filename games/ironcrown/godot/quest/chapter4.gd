class_name Chapter4
extends RefCounted
## 第四章的章末（路线图 7.8；STORY.md 7.5 第 9 步「画面停在冠城钟楼的黄昏钟里，『第五章 · 冬井　开发中』，按旗标写回顾」）：
## 回顾写这一章怎么把冠弄出来、金库之夜、码头上的打手、三条支线、冬议上拿出来的罪证、冠交给了谁、借据由谁念；钩子接第五章（冬井、星铁坠落处）。


static func recap() -> String:
	var out := []
	match str(GameState.get_flag("ch4_crown_way", "")):
		"bought":
			var who: String = {"severin": "塞弗林家", "lomond": "洛蒙德家", "north": "北境"}.get(str(GameState.get_flag("ch4_buyer", "")), "一家")
			out.append(I18n.t("你在钥楼替%s把账赎了，冠由科尔温带上了冠城。") % I18n.t(who))
		"traded":
			out.append(I18n.t("你拿%s跟科尔温换了冠。") % I18n.t("摄政的信" if str(GameState.get_flag("ch4_traded", "")) == "letter" else "粮仓账本"))
		"stolen":
			match str(GameState.get_flag("ch4_vault", "")):
				"unseen":
					out.append(I18n.t("退潮的夜里，你从北潮沟摸进钥楼的金库，莫德睡着了，你拿走了她的钥匙。"))
				"talked":
					out.append(I18n.t("金库之夜，你跟莫德说伊格纳兹还活着——她自己打开了铁笼。"))
				_:
					out.append(I18n.t("金库之夜，你被看见了，和卡斯韦尔家的雇佣兵打了一架才拿到冠。"))
	match str(GameState.get_flag("ch4_thugs", "")):
		"paid":
			out.append(I18n.t("塞拉斯的人在码头上收走了六十枚银币。"))
		"talked":
			out.append(I18n.t("码头上堵你的人被你说走了。"))
		"beaten":
			out.append(I18n.t("码头上堵你的三个打手，被你打散了。"))
	match str(GameState.get_flag("ch4_ambush", "")):
		"talked":
			out.append(I18n.t("斜街上蒙着脸的人退回了巷子里。"))
		"beaten":
			out.append(I18n.t("斜街上蒙着脸的人倒在巷口，没人知道是谁派来的。"))
	if str(GameState.get_flag("ch4_lighthouse", "")) == "lit":
		out.append(I18n.t("沙嘴外的灯塔亮了。"))
	elif str(GameState.get_flag("ch4_lighthouse", "")) == "dark":
		out.append(I18n.t("灯塔一直没亮，码头外又沉了一条船。"))
	if str(GameState.get_flag("ch4_debtor", "")) != "":
		out.append(I18n.t("约斯特出了债牢，在议事厅的旁听席上喊出了那一句。"))
	if str(GameState.get_flag("ch4_matilda", "")) == "found":
		out.append(I18n.t("米洛回到了玛蒂尔达身边。"))
	match str(GameState.get_flag("ch4_evidence_used", "")):
		"severin":
			out.append(I18n.t("冬议上你拿出了摄政的信，塞弗林家一句话也没再说。"))
		"lomond":
			out.append(I18n.t("冬议上你拿出了粮仓账本，洛蒙德家只能听。"))
		"both":
			out.append(I18n.t("冬议上你拿出了摄政的信和粮仓账本，两家都闭了嘴。"))
	var heir := "伊薇特" if str(GameState.get_flag("valen_heir", "")) == "ivette" else "阿尔里克"
	match str(GameState.get_flag("crown_holder", "")):
		"severin":
			out.append(I18n.t("铁冠交给了塞弗林家：开春，摄政的孙子加冕。"))
		"lomond":
			out.append(I18n.t("铁冠交给了洛蒙德家：伊莎贝拉替王国还了账。"))
		"valen":
			out.append(I18n.t("铁冠交给了瓦伦家，交到了%s手里：北境第一回坐着说话。") % I18n.t(heir))
		"church":
			out.append(I18n.t("铁冠交给了大主祭卢西安，要送回星铁坠落的地方：谁都没拿到它。"))
		"caswell":
			out.append(I18n.t("铁冠回了钥楼的金库：账没清，谁都没得罪，也没有人再信你。"))
		"kept":
			out.append(I18n.t("铁冠还在你怀里。从冬议散了那一刻起，所有人都在找你。"))
	var reader: String = {"edric": "埃德里克", "silas": "塞拉斯", "valen": heir, "you": "你自己"}.get(str(GameState.get_flag("ch4_debt_reader", "")), "")
	if reader != "" and GameState.has_flag("ch4_note_read"):
		out.append(I18n.t("序章那张借据，由%s当众念了出来。") % I18n.t(reader))
	return (" " if I18n.en() else "").join(out)


static func hook() -> String:
	var out := [I18n.t("借据背面那枚星铁冠印，和铁匣封蜡上的一模一样：老王押出去的不只是冠，他拿整个北境的债，担保过烽燧线的每一车粮。")]
	if str(GameState.get_flag("ch4_regent_visitor", "")) == "lucien":
		out.append(I18n.t("冬议前一夜，大主祭的车停在摄政宅子的后门。"))
	if GameState.has_flag("ch3_vial_heard"):
		out.append(I18n.t("封誓的誓瓶是空的——冬井以北，星铁落下的那一处，有人在等。"))
	else:
		out.append(I18n.t("冬井以北，星铁落下的那一处，有人在等。"))
	return (" " if I18n.en() else "").join(out)
