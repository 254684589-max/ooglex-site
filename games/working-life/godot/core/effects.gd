class_name Effects
extends RefCounted
## 通用效果执行器。任务奖励、随机事件、商品、对话选项都用同一种字典描述效果：
##   {"cash": 200, "mood": 10, "skill_xp": {"computer": 30}, "rel": {"laoli": 5}, "time": 120}
## 金钱一律经过 EconomyManager；属性经过 PlayerManager；其余转给对应系统。
## apply() 返回给玩家看的补充说明（例如谈判结果），可能为空。

const STAT_KEYS := ["energy", "hunger", "mood", "health", "stress"]


static func apply(effects: Variant, source := "奖励", category := "任务奖励") -> Array:
	var notes: Array = []
	if typeof(effects) != TYPE_DICTIONARY:
		return notes
	var e: Dictionary = effects
	var income_cat := String(e.get("income_cat", category))
	for key in e:
		var v = e[key]
		match String(key):
			"cash":
				var amt := int(v)
				if amt >= 0:
					EconomyManager.earn(amt, income_cat, source)
				else:
					EconomyManager.spend(-amt, "其他", source, true)
			"bank":
				if int(v) >= 0:
					EconomyManager.earn(int(v), income_cat, source, true)
			"bank_pct":
				var loss := int(EconomyManager.bank * absf(float(v)))
				if loss > 0:
					EconomyManager.withdraw_to_void(loss, "诈骗损失")
			"energy", "hunger", "mood", "health", "stress":
				PlayerManager.change(String(key), float(v))
			"rep":
				PlayerManager.change_reputation(float(v))
			"perf":
				JobManager.change_perf(float(v))
			"skill_xp":
				for s in v:
					SkillManager.add_xp(String(s), float(v[s]), source)
			"skill_xp_job":
				JobManager.grant_job_xp(float(v))
			"rel":
				for n in v:
					NPCManager.change_relation(String(n), int(v[n]))
			"item":
				for it in v:
					PlayerManager.add_item(String(it), int(v[it]))
			"consume":
				PlayerManager.remove_item(String(v), 1)
			"time":
				TimeManager.advance(float(v), "idle")
			"flag":
				GameManager.set_flag(String(v))
			"start_quest":
				QuestManager.start(String(v))
			"market_shock":
				InvestmentManager.market_shock(v)
			"cycle":
				InvestmentManager.set_cycle(String(v))
			"rent_mult":
				HousingManager.rent_mult *= float(v)
			"negotiate_rent":
				var chance := 0.25 + SkillManager.level("communication") * 0.08
				if randf() < chance:
					notes.append("你据理力争，房东同意维持原价。")
					SkillManager.add_xp("communication", 25, "谈判")
				else:
					HousingManager.rent_mult *= 1.1
					notes.append("房东寸步不让，房租还是涨了 10%。")
			"fire_job":
				if bool(v):
					JobManager.fire("公司裁员")
			"interview_invite":
				var msg := JobManager.invite_from_event(String(v))
				if msg != "":
					notes.append(msg)
			"course_sale":
				GameManager.set_value("course_sale_until", TimeManager.day + int(v))
			"diy_repair":
				if SkillManager.level("technical") >= 3 or randf() < 0.3:
					notes.append("你拆开后盖，换了根线——修好了！")
					SkillManager.add_xp("technical", 40, "修电脑")
				else:
					EconomyManager.spend(800, "其他", "电脑送修", true)
					notes.append("越修越坏，最后还是送修了（¥800）。")
			"cash_salary_days":
				var bonus := int(JobManager.daily_pay() * int(v))
				if bonus > 0:
					EconomyManager.earn(bonus, "奖金", source, JobManager.is_monthly())
					notes.append("获得奖金 %s。" % Fmt.yuan(bonus))
			"pay_bonus":
				var extra := int(JobManager.daily_pay() * float(v))
				if extra > 0:
					EconomyManager.earn(extra, "加班费", source)
					notes.append("加班费 %s。" % Fmt.yuan(extra))
			"delayed_cash":
				EventManager.schedule_delayed(int(v.get("days", 7)), {"cash": int(v.get("amount", 0))}, "朋友还钱")
			"bus_down":
				GameManager.set_value("bus_down_until", TimeManager.day + int(v) - 1)
			"biz_cash":
				BusinessManager.adjust_cash(int(v), source)
			"biz_cash_pct":
				BusinessManager.adjust_cash(int(BusinessManager.company_cash() * float(v)), source)
			"biz_rep":
				BusinessManager.change_rep(float(v))
			"biz_fire_one":
				BusinessManager.lose_employee()
			"take_leave":
				JobManager.take_leave(true)
			"sick_leave_if_late":
				# 生病耽误了上班：自动请病假，不算旷工（放在 time 之后执行）
				if JobManager.sick_leave_if_missed():
					notes.append("已经赶不上今天的班，公司按病假处理（不算旷工）。")
			"lottery":
				var r := randf()
				if r < 0.002:
					EconomyManager.earn(5000000, "彩票", "彩票头奖")
					notes.append("……你中了头奖 ¥5,000,000！！！")
				elif r < 0.05:
					EconomyManager.earn(200, "彩票", "彩票")
					notes.append("中了 ¥200 小奖。")
				else:
					notes.append("没中。")
			"income_cat", "result":
				pass
			_:
				push_warning("Effects: 未知效果 %s" % key)
	return notes


## 效果的简短中文说明：「现金 +¥200 · 心情 +10」
static func describe(effects: Variant) -> String:
	if typeof(effects) != TYPE_DICTIONARY:
		return ""
	var parts: Array = []
	for key in effects:
		var v = effects[key]
		match String(key):
			"cash":
				parts.append("现金 %s" % Fmt.signed_yuan(float(v)))
			"energy":
				parts.append("体力 %+d" % int(v))
			"hunger":
				parts.append("饱腹 %+d" % int(v))
			"mood":
				parts.append("心情 %+d" % int(v))
			"health":
				parts.append("健康 %+d" % int(v))
			"stress":
				parts.append("压力 %+d" % int(v))
			"rep":
				parts.append("声望 %+d" % int(v))
			"perf":
				parts.append("绩效 %+d" % int(v))
			"skill_xp":
				for s in v:
					parts.append("%s经验 +%d" % [DataDB.skill_name(String(s)), int(v[s])])
			"rel":
				for n in v:
					parts.append("%s关系 %+d" % [DataDB.npc_name(String(n)), int(v[n])])
			"time":
				parts.append("耗时 %s" % Fmt.hours_text(float(v)))
			"item":
				for it in v:
					parts.append("获得 %s×%d" % [DataDB.item_name(String(it)), int(v[it])])
	return " · ".join(parts)
