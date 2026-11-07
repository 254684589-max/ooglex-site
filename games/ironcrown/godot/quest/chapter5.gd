class_name Chapter5
extends RefCounted
## 第五章的结局（路线图 8.5；STORY.md 第一节「三种结局」、8.5 第 7 步「井口外的雪停了（或者没有停）。结局画面按 oath_taker 写，回顾从序章写到第五章」）：
## 结局画面的标题（新王 / 无冠之春 / 长冬）、结局正文（按 oath_taker 和封誓的结果分变体）、一路走来的回顾（每一章一两句，按那一章的关键旗标写）。


static func ending() -> String:
	var e := str(GameState.get_flag("ending", ""))
	return e if e in ["new_king", "crownless_spring", "long_winter"] else "long_winter"


static func title() -> String:
	return {"new_king": "新王", "crownless_spring": "无冠之春", "long_winter": "长冬"}[ending()]


static func heir_name() -> String:
	match str(GameState.get_flag("ch5_companion", "")):
		"young_bertrand":
			return "小贝尔特兰"
		"isabella":
			return "伊莎贝拉"
		"ivette":
			return "伊薇特"
		"alric":
			return "阿尔里克"
	var c := Winter5.companion()                          # 没到高地就封了（截图、测试的捷径）：按冠在谁手里
	return str(c[1]) if not c.is_empty() and str(c[0]) != "lucien" else "新王"


## 结局正文
static func text() -> String:
	var taker := str(GameState.get_flag("oath_taker", "none"))
	match ending():
		"new_king":
			var s := "冰壁上那片空着的冰里，浮出了%s的名字。开春，%s在冠城加冕；第一个解冻的早上，灰鲸河的冰面裂开了一道缝。" % [heir_name(), heir_name()]
			s += "可每年入冬，新王都要一个人往北走，回到那口井边守一夜。王国欠下的一百一十七张借据还在钥楼里，一张也没少——春天回来了，账也回来了。"
			return s
		"crownless_spring":
			match taker:
				"norbert":
					return "冰壁上那片空着的冰里，浮出了诺伯特的名字。三十五年前那只空誓瓶，终于是满的回到了井里。春天回来了，铁冠熔在冰里，再也拔不出来；冠城的议事厅里五张椅子还在，王座空着——王国改由那五张椅子治理。每年入冬，有人看见一个老人一个人往山脊那边走。"
				"lucien":
					return "冰壁上那片空着的冰里，浮出了大主祭卢西安的名字。春天回来了，星铁教会重新主持加冕礼——可这一回，加冕礼的最后一步写在了经书的第一页。铁冠留在井底，教会每年派人北上守井。各家都说，冠回到了坠星的地方；没有人说清楚，它回到了谁手里。"
			return "冰壁上那片空着的冰里，浮出了你的名字。春天回来了，没有人知道是你做的：冠城说是星铁教会的祷告，北境说是烽燧线的火，钥楼说是账终于还清了。铁冠熔在冰里，再也拔不出来；王国改由议事厅里那五张椅子治理。每年入冬，你一个人往北走。"
	if str(GameState.get_flag("ch5_oath", "")) == "failed":
		return "火盆一个接一个暗了下去。长眠的人走下石阶，围住了石台，誓瓶还是空的。你们从井里爬出来的时候，山脊上又多了一圈人。冬天没有退。各家在冠城里接着争那顶冠——到了第四个没有春天的年份，烽燧线上最后一座火熄灭了。"
	return "你把冠和誓瓶收了起来，顺着石阶往上走。冰壁上那片空着的冰还空着。冬天没有退。各家在冠城里接着争那顶冠——到了第四个没有春天的年份，烽燧线上最后一座火熄灭了。"


## 一路走来：每一章一两句
static func recap() -> String:
	var out := []
	match str(GameState.get_flag("prologue_edric", "")):
		"deliver":
			out.append("霜渡镇那一夜，你把埃德里克和借据交回了瓦伦家。")
		"release":
			out.append("霜渡镇那一夜，你放埃德里克带着借据坐船南下。")
		"extort":
			out.append("霜渡镇那一夜，你扣下了借据，收了塞拉斯的银币。")
	match str(GameState.get_flag("valen_heir", "")):
		"alric":
			out.append("黑鹭堡的印戒交到了阿尔里克手里。")
		"ivette":
			out.append("黑鹭堡的印戒交到了伊薇特手里。")
	match str(GameState.get_flag("ch2_fire", "")):
		"lit":
			out.append("第十九烽的火，靠你送上山的粮一直亮着。")
		"out":
			out.append("第十九烽的火，那个冬天熄了。")
	match str(GameState.get_flag("ch3_evidence_to", "")):
		"abbey":
			out.append("金穗平原的罪证，你交给了坠星院。")
		"tenants":
			out.append("金穗平原的罪证，你当着麦渡全村念了出来。")
		"kept":
			out.append("金穗平原的罪证，你一直揣在怀里。")
	var holder: String = {"severin": "塞弗林家", "lomond": "洛蒙德家", "valen": "瓦伦家", "church": "星铁教会", "caswell": "钥楼", "kept": "你自己"}.get(str(GameState.get_flag("crown_holder", "")), "")
	if holder != "":
		out.append("冬议上，铁冠交给了%s。" % holder)
	if str(GameState.get_flag("ch5_nell", "")) == "woke" and str(GameState.get_flag("ch5_oath", "")) == "sealed":
		out.append("妮尔醒过来，跟着诺伯特下了山。")
	elif str(GameState.get_flag("ch2_nell", "")) == "left" and str(GameState.get_flag("ch5_oath", "")) != "sealed":
		out.append("妮尔走进了白寂。")
	if GameState.has_flag("ch5_watch21"):
		out.append("第二十一烽的人，被你和马蒂亚斯举着火把引开了。")
	return "".join(out)
