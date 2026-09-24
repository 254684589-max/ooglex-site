class_name Conditions
extends RefCounted
## 通用条件判定。任务接取条件、随机事件条件、结局条件、交通解锁都用同一套写法：
##   {"has_job": true, "skill": {"computer": 3}, "liquid_min": 100000, "any": [{...}, {...}]}
## 字典里的每个键都必须满足；"any" 里满足任意一个子条件即可。


static func check(cond: Variant) -> bool:
	if typeof(cond) != TYPE_DICTIONARY:
		return true
	var c: Dictionary = cond
	for key in c:
		if not _check_one(String(key), c[key]):
			return false
	return true


static func _check_one(key: String, v: Variant) -> bool:
	match key:
		"any":
			for sub in v:
				if check(sub):
					return true
			return false
		"all":
			for sub in v:
				if not check(sub):
					return false
			return true
		"has_job":
			return JobManager.has_job() == bool(v)
		"job_id":
			return JobManager.has_job() and JobManager.job_id() == String(v)
		"job_category":
			if not JobManager.has_job():
				return false
			var cat := String(DataDB.job(JobManager.job_id()).get("category", ""))
			if String(v) == "office_any":
				return cat in ["office", "tech", "finance", "manager"]
			return cat == String(v)
		"job_level_min":
			return JobManager.has_job() and JobManager.level() + 1 >= int(v)
		"job_shifts_min":
			return JobManager.has_job() and int(JobManager.current.get("shifts_total", 0)) >= int(v)
		"job_perf_min":
			return JobManager.has_job() and float(JobManager.current.get("perf", 0)) >= float(v)
		"job_perf_max":
			return JobManager.has_job() and float(JobManager.current.get("perf", 0)) <= float(v)
		"skill":
			for s in v:
				if SkillManager.level(String(s)) < int(v[s]):
					return false
			return true
		"cash_min":
			return EconomyManager.cash >= int(v)
		"bank_min":
			return EconomyManager.bank >= int(v)
		"liquid_min":
			return EconomyManager.liquid() >= int(v)
		"networth_min":
			return EconomyManager.networth() >= int(v)
		"passive_income_min":
			return EconomyManager.passive_income_monthly() >= float(v)
		"housing_min":
			return HousingManager.level() >= int(v)
		"housing_max":
			return HousingManager.level() <= int(v)
		"rent_monthly":
			return HousingManager.is_monthly() == bool(v)
		"rep_min":
			return PlayerManager.reputation >= float(v)
		"health_max":
			return PlayerManager.health <= float(v)
		"stress_min":
			return PlayerManager.stress >= float(v)
		"energy_min":
			return PlayerManager.energy >= float(v)
		"rel_min":
			for n in v:
				if NPCManager.relation(String(n)) < int(v[n]):
					return false
			return true
		"friends_min":
			return NPCManager.count_at_least(int(v.get("value", 30))) >= int(v.get("count", 1))
		"has_business":
			return BusinessManager.has_company() == bool(v)
		"business_stage_min":
			return BusinessManager.has_company() and BusinessManager.stage() >= int(v)
		"employees_min":
			return BusinessManager.employee_count() >= int(v)
		"investment_unlocked":
			return InvestmentManager.unlocked() == bool(v)
		"has_item":
			return PlayerManager.has_item(String(v))
		"day_min":
			return TimeManager.day >= int(v)
		"weather":
			return WeatherManager.weather == String(v)
		"cycle_not":
			return InvestmentManager.cycle != String(v)
		"chapter_min":
			return GameManager.chapter >= int(v)
		"flag":
			return GameManager.has_flag(String(v))
		"not_flag":
			return not GameManager.has_flag(String(v))
		"quest_done":
			return QuestManager.is_done(String(v))
	push_warning("Conditions: 未知条件 %s" % key)
	return true


## 把条件翻译成给玩家看的中文（招聘要求、解锁提示用）
static func describe(cond: Variant) -> Array:
	var out: Array = []
	if typeof(cond) != TYPE_DICTIONARY:
		return out
	for key in cond:
		var v = cond[key]
		match String(key):
			"skill":
				for s in v:
					out.append("%s Lv.%d" % [DataDB.skill_name(String(s)), int(v[s])])
			"rep_min":
				out.append("声望 %d" % int(v))
			"liquid_min":
				out.append("现金+存款 ¥%s" % Fmt.money(int(v)))
			"housing_min":
				out.append("住房等级 %d" % int(v))
			"chapter_min":
				out.append("第 %d 章" % int(v))
			"flag":
				out.append("剧情解锁")
			_:
				out.append(String(key))
	return out
