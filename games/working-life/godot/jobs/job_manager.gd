extends Node
## 职业系统（自动加载名：JobManager）。所有职业共用一套规则，职业差异全部来自 data/jobs.json：
## 申请 → 面试 → 录用 → 上班（迟到 / 请假 / 旷工）→ 小游戏评分 → 工资 / 奖金 / 绩效 → 升职 / 降职 → 辞职 / 解雇 / 跳槽。

signal invites_changed

const LATE_GRACE_MIN := 10.0
const CLOCK_IN_EARLY_MIN := 60.0
const CLOCK_IN_LATE_MAX_MIN := 120.0
const MONTHLY_SHIFTS := 22.0

## 当前工作（空字典 = 无业）
var current: Dictionary = {}
var history: Array = []
## 面试邀请：[{job, level, expires_day, source}]
var invites: Array = []
## 简历被拒的日期：{job_id: day}
var rejected: Dictionary = {}
var promotions := 0
var interviews_passed := 0
var leave_week_used := -1
## 最近一次班次结果（界面展示用）
var last_result: Dictionary = {}


func _ready() -> void:
	TimeManager.day_changed.connect(_on_day_changed)


func reset() -> void:
	current = {}
	history.clear()
	invites.clear()
	rejected.clear()
	promotions = 0
	interviews_passed = 0
	leave_week_used = -1
	last_result = {}


func has_job() -> bool:
	return not current.is_empty()


func job_id() -> String:
	return String(current.get("id", ""))


func job() -> Dictionary:
	return DataDB.job(job_id())


func level() -> int:
	return int(current.get("level", 0))


func ladder(id := "") -> Array:
	if id == "":
		id = job_id()
	return DataDB.job(id).get("ladder", [])


func title() -> String:
	if not has_job():
		return "无业"
	var l := ladder()
	return String(l[clampi(level(), 0, l.size() - 1)].get("title", ""))


func pay_of(id: String, lvl: int) -> int:
	var l := ladder(id)
	if l.is_empty():
		return 0
	return int(l[clampi(lvl, 0, l.size() - 1)].get("pay", 0))


func is_monthly(id := "") -> bool:
	if id == "":
		id = job_id()
	return String(DataDB.job(id).get("pay_type", "daily")) == "monthly"


## 每个班次的工资（月薪按 22 个班次折算）
func daily_pay() -> float:
	if not has_job():
		return 0.0
	var p := float(pay_of(job_id(), level()))
	return p / MONTHLY_SHIFTS if is_monthly() else p


func pay_text(id: String, lvl: int) -> String:
	var p := pay_of(id, lvl)
	return "%s / 月" % Fmt.yuan(p) if is_monthly(id) else "%s / 天" % Fmt.yuan(p)


func workdays_text(id: String) -> String:
	match String(DataDB.job(id).get("workdays", "weekdays")):
		"all":
			return "每天"
		"six":
			return "周一至周六"
	return "周一至周五"


func hours_text(id: String) -> String:
	var j := DataDB.job(id)
	var s := int(j.get("shift_start", 9))
	return "%02d:00-%02d:00" % [s, s + int(j.get("shift_hours", 8))]


func is_workday(d := -1, id := "") -> bool:
	if id == "":
		id = job_id()
	if d < 0:
		d = TimeManager.day
	var wd := (d - 1) % 7
	match String(DataDB.job(id).get("workdays", "weekdays")):
		"all":
			return true
		"six":
			return wd <= 5
	return wd <= 4


func perf() -> float:
	return float(current.get("perf", 0))


func change_perf(v: float) -> void:
	if not has_job():
		return
	current["perf"] = clampf(perf() + v, 0.0, 100.0)
	Events.stats_changed.emit()


func grant_job_xp(amount: float) -> void:
	if not has_job():
		return
	var sx: Dictionary = job().get("skill_xp", {})
	var total := 0.0
	for s in sx:
		total += float(sx[s])
	if total <= 0.0:
		return
	for s in sx:
		SkillManager.add_xp(String(s), amount * float(sx[s]) / total, "工作")


# ================================================================ 招聘
## 满足要求的最高入职职级（跳槽可以直接以较高职级入职，最多到第 3 级）
func entry_level_for(id: String) -> int:
	var l := ladder(id)
	var best := 0
	if not is_monthly(id):
		return 0
	for i in range(1, mini(3, l.size())):
		var step: Dictionary = l[i]
		if _meets_level(id, i) and PlayerManager.reputation >= float(step.get("rep", 0)):
			best = i
	return best


func _meets_level(id: String, lvl: int) -> bool:
	var j := DataDB.job(id)
	if not SkillManager.meets(j.get("requirements", {})):
		return false
	for i in range(1, lvl + 1):
		var step: Dictionary = ladder(id)[i]
		if not SkillManager.meets(step.get("req", {})):
			return false
	return true


## 招聘 APP 列表
func postings() -> Array:
	var out: Array = []
	for id in DataDB.ids("jobs"):
		var j := DataDB.job(id)
		var lvl := entry_level_for(id)
		var req: Dictionary = j.get("requirements", {}).duplicate()
		if lvl > 0:
			for i in range(1, lvl + 1):
				var r: Dictionary = ladder(id)[i].get("req", {})
				for s in r:
					req[s] = maxi(int(req.get(s, 0)), int(r[s]))
		var missing := SkillManager.missing(req)
		var rep_need := int(j.get("rep", 0))
		if PlayerManager.reputation < rep_need:
			missing.append("声望 %d（当前 %d）" % [rep_need, int(PlayerManager.reputation)])
		var status := ""
		if has_job() and job_id() == id:
			status = "当前工作"
		elif has_invite(id):
			status = "待面试"
		elif int(rejected.get(id, -99)) == TimeManager.day:
			status = "今日已被拒"
		out.append({
			"job": id, "level": lvl, "title": String(ladder(id)[lvl]["title"]), "name": String(j["name"]),
			"company": String(j.get("company", "")), "pay": pay_text(id, lvl), "hours": hours_text(id) + " · " + workdays_text(id),
			"location": String(j.get("workplace", "")), "venue": String(j.get("venue", "")),
			"req": req, "missing": missing, "eligible": missing.is_empty(), "status": status,
			"desc": String(j.get("desc", "")), "grade": lvl + 1,
		})
	return out


func has_invite(id: String) -> bool:
	for inv in invites:
		if String(inv["job"]) == id and int(inv["expires_day"]) >= TimeManager.day:
			return true
	return false


func get_invite(id: String) -> Dictionary:
	for inv in invites:
		if String(inv["job"]) == id and int(inv["expires_day"]) >= TimeManager.day:
			return inv
	return {}


func invites_at(venue: String) -> Array:
	var out: Array = []
	for inv in invites:
		if int(inv["expires_day"]) >= TimeManager.day and String(DataDB.job(String(inv["job"])).get("venue", "")) == venue:
			out.append(inv)
	return out


## 投递简历。返回 {ok, text}
func apply(id: String) -> Dictionary:
	var j := DataDB.job(id)
	if j.is_empty():
		return {"ok": false, "text": "没有这个职位"}
	if has_job() and job_id() == id:
		return {"ok": false, "text": "你已经在做这份工作了"}
	if has_invite(id):
		return {"ok": false, "text": "已经约好面试了，去%s参加面试吧" % DataDB.location_name(String(j.get("venue", "")))}
	if int(rejected.get(id, -99)) == TimeManager.day:
		return {"ok": false, "text": "今天已经被这家拒过了，明天再试"}
	var lvl := entry_level_for(id)
	var p: Dictionary = {}
	for x in postings():
		if String(x["job"]) == id:
			p = x
	if not bool(p.get("eligible", false)):
		return {"ok": false, "text": "不满足要求：" + "、".join(p.get("missing", []))}
	Events.notify("apply_job", {"job": id})
	# 体力活简历必过；写字楼岗位看技能余量与声望
	var chance := 1.0
	if String(j.get("category", "")) != "basic":
		chance = 0.62 + PlayerManager.reputation * 0.004 + PlayerManager.outfit_interview_bonus() * 0.01
		var req: Dictionary = p["req"]
		for s in req:
			chance += float(SkillManager.level(String(s)) - int(req[s])) * 0.08
		chance = clampf(chance, 0.35, 0.97)
	if randf() > chance:
		rejected[id] = TimeManager.day
		return {"ok": false, "text": "%s回复：感谢投递，您的简历暂不匹配。（明天可以再投）" % String(j.get("company", ""))}
	_add_invite(id, lvl, "投递")
	return {"ok": true, "text": "%s 发来面试邀请！请在明天之前到%s参加面试。" % [String(j.get("company", "")), DataDB.location_name(String(j.get("venue", "")))]}


func _add_invite(id: String, lvl: int, source: String) -> void:
	for inv in invites.duplicate():
		if String(inv["job"]) == id:
			invites.erase(inv)
	invites.append({"job": id, "level": lvl, "expires_day": TimeManager.day + 1, "source": source})
	invites_changed.emit()
	Events.world_spawns_changed.emit()


## 随机事件发来的面试邀请
func invite_from_event(kind: String) -> String:
	var best_id := ""
	var best_pay := daily_pay()
	for id in DataDB.ids("jobs"):
		if has_job() and id == job_id():
			continue
		var lvl := entry_level_for(id)
		if not _meets_level(id, lvl):
			continue
		if PlayerManager.reputation < float(DataDB.job(id).get("rep", 0)):
			continue
		var p := float(pay_of(id, lvl))
		if is_monthly(id):
			p /= MONTHLY_SHIFTS
		if kind == "upgrade" and lvl == 0:
			continue
		if p > best_pay:
			best_pay = p
			best_id = id
	if best_id == "":
		return "可惜目前没有比现在更好的岗位适合你。"
	var lvl2 := entry_level_for(best_id)
	_add_invite(best_id, lvl2, "邀请")
	return "邀请你面试：%s · %s（%s）" % [String(DataDB.job(best_id).get("company", "")), String(ladder(best_id)[lvl2]["title"]), pay_text(best_id, lvl2)]


## 面试题
func interview_questions(id: String, n := 3) -> Array:
	var pool_name := String(DataDB.job(id).get("interview_pool", "service"))
	var pool: Array = DataDB.interview.get("_meta", {}).get("pools", {}).get(pool_name, [])
	var ids: Array = pool.duplicate()
	ids.shuffle()
	# 第一题总是自我介绍
	if ids.has("intro"):
		ids.erase("intro")
		ids.push_front("intro")
	var out: Array = []
	for qid in ids.slice(0, n):
		var q: Dictionary = DataDB.interview.get(qid, {})
		if not q.is_empty():
			out.append(q)
	return out


## 面试通过概率（answer_avg：0~10）
func interview_chance(id: String, answer_avg: float) -> float:
	var j := DataDB.job(id)
	var basic := String(j.get("category", "")) == "basic"
	var c := (0.5 if basic else 0.3) + answer_avg / 10.0 * (0.4 if basic else 0.45)
	c += SkillManager.level("communication") * 0.02
	c += PlayerManager.outfit_interview_bonus() * 0.01
	c += (HousingManager.prestige() + VehicleManager.prestige()) * 0.005
	c += PlayerManager.reputation * 0.003
	c += (PlayerManager.mood - 60.0) * 0.002
	c -= maxf(0.0, PlayerManager.stress - 60.0) * 0.004
	c += NPCManager.interview_bonus(id) * 0.01
	if interviews_passed == 0 and basic and answer_avg >= 6.0:
		c = maxf(c, 0.92)
	return clampf(c, 0.05, 0.97)


## 面试结束：返回 {ok, text, chance}
func finish_interview(id: String, answer_avg: float) -> Dictionary:
	var inv := get_invite(id)
	var lvl := int(inv.get("level", entry_level_for(id)))
	var chance := interview_chance(id, answer_avg)
	invites.erase(inv)
	invites_changed.emit()
	Events.world_spawns_changed.emit()
	SkillManager.add_xp("communication", 12, "面试")
	if randf() <= chance:
		interviews_passed += 1
		hire(id, lvl)
		Events.notify("interview_pass", {"job": id})
		return {"ok": true, "chance": chance, "text": "恭喜！你被录用为「%s」。" % String(ladder(id)[lvl]["title"])}
	rejected[id] = TimeManager.day
	PlayerManager.change("mood", -6)
	return {"ok": false, "chance": chance, "text": "面试官：「我们再考虑一下。」——没通过。换一家试试，或者明天再来。"}


## 录用（面试通过 / NPC 直接介绍）
func hire(id: String, lvl := 0) -> void:
	if has_job():
		_leave_current("跳槽")
	current = {
		"id": id, "level": lvl, "perf": 60.0, "xp": 0.0, "shifts_total": 0, "shifts_level": 0, "absences": 0,
		"hired_day": TimeManager.day, "hired_minute": TimeManager.total_minutes, "last_shift_day": -1,
		"pending_pay": 0, "leave_day": -1, "late_count": 0, "boss_rel": 50.0,
	}
	GameManager.set_flag("has_first_job")
	Events.job_changed.emit()
	Events.stats_changed.emit()
	Events.notify("get_job", {"job": id, "pay_type": String(DataDB.job(id).get("pay_type", "daily"))})
	var j := DataDB.job(id)
	Events.phone_message.emit(String(j.get("company", "HR")), "欢迎加入！上班时间 %s（%s），地点：%s。别迟到！" % [hours_text(id), workdays_text(id), DataDB.location_name(String(j.get("workplace", "")))])


func quit_job() -> String:
	if not has_job():
		return "你现在没有工作"
	var t := title()
	_leave_current("辞职")
	return "你辞去了「%s」的工作。" % t


func fire(reason: String) -> void:
	if not has_job():
		return
	var t := title()
	_leave_current(reason)
	PlayerManager.change_reputation(-4)
	Events.phone_message.emit("HR", "很遗憾地通知您：由于%s，公司决定与您解除劳动合同。" % reason)
	Events.say("你被解雇了：「%s」" % t, "bad")


func _leave_current(reason: String) -> void:
	_pay_pending("结清工资")
	history.append({"id": job_id(), "title": title(), "shifts": int(current.get("shifts_total", 0)), "reason": reason, "day": TimeManager.day})
	current = {}
	Events.job_changed.emit()
	Events.stats_changed.emit()


func _pay_pending(note: String) -> void:
	var p := int(current.get("pending_pay", 0))
	if p > 0:
		EconomyManager.earn(p, "工资", note, true)
		current["pending_pay"] = 0


# ================================================================ 上班
## 今天的班次时间（总分钟）
func shift_start_minute(d := -1) -> float:
	if d < 0:
		d = TimeManager.day
	return (d - 1) * 1440.0 + float(job().get("shift_start", 9)) * 60.0


func shift_end_minute(d := -1) -> float:
	return shift_start_minute(d) + float(job().get("shift_hours", 8)) * 60.0


func worked_today() -> bool:
	return int(current.get("last_shift_day", -1)) == TimeManager.day


func on_leave_today() -> bool:
	return int(current.get("leave_day", -1)) == TimeManager.day


## HUD / 手机显示的上班状态
func status_text() -> String:
	if not has_job():
		return "无业 · 打开手机「招聘」找工作"
	var j := job()
	var where := DataDB.location_name(String(j.get("workplace", "")))
	if not is_workday():
		return "今天休息"
	if worked_today():
		return "今天的班已经上完"
	if on_leave_today():
		return "今天请假"
	var now := TimeManager.total_minutes
	var start := shift_start_minute()
	# 入职当天不算旷工：赶得上可以上一班，赶不上就下一个工作日再来
	if hired_today() and (hired_after_shift_today() or now > start + LATE_GRACE_MIN):
		return "今天刚入职 · %s（%s）%s 上班 @ %s" % [_next_workday_text(), TimeManager.weekday_name(next_workday()), Fmt.clock(start), where]
	if now > start + CLOCK_IN_LATE_MAX_MIN:
		return "今天旷工了！"
	if now > start + LATE_GRACE_MIN:
		return "已迟到！快去%s" % where
	return "%s 上班 @ %s" % [Fmt.clock(start), where]


func hired_today() -> bool:
	return has_job() and int(current.get("hired_day", -1)) == TimeManager.day


## 今天入职，而且录用时已经过了今天的上班时间
func hired_after_shift_today() -> bool:
	return hired_today() and float(current.get("hired_minute", 0.0)) > shift_start_minute()


## 明天起第一个工作日
func next_workday() -> int:
	var d := TimeManager.day + 1
	for i in 7:
		if is_workday(d):
			return d
		d += 1
	return TimeManager.day + 1


func _next_workday_text() -> String:
	var d := next_workday()
	return "明天" if d == TimeManager.day + 1 else "%d 天后" % (d - TimeManager.day)


## 能否在工位开始上班。返回 {ok, reason, late}
func can_start_shift(at_job: String) -> Dictionary:
	if not has_job() or job_id() != at_job:
		return {"ok": false, "reason": "你不在这里上班"}
	if not is_workday():
		return {"ok": false, "reason": "今天是休息日"}
	if worked_today():
		return {"ok": false, "reason": "今天的班已经上完了"}
	if on_leave_today():
		return {"ok": false, "reason": "你今天请了假"}
	var now := TimeManager.total_minutes
	var start := shift_start_minute()
	if now < start - CLOCK_IN_EARLY_MIN:
		return {"ok": false, "reason": "还没到上班时间（%s 开始，可提前 1 小时打卡）" % Fmt.clock(start)}
	if now > start + CLOCK_IN_LATE_MAX_MIN:
		return {"ok": false, "reason": "迟到超过 2 小时，今天算旷工了"}
	if PlayerManager.energy < 12.0:
		return {"ok": false, "reason": "太累了，先休息或者喝杯咖啡（体力低于 12）"}
	var late := maxf(0.0, now - start)
	return {"ok": true, "late": late if late > LATE_GRACE_MIN else 0.0}


## 小游戏结束后结算班次。score：0~100（小游戏原始评分）
func finish_shift(raw_score: float, late_minutes := 0.0) -> Dictionary:
	if not has_job():
		return {}
	var j := job()
	var eff := PlayerManager.efficiency()
	if bool(j.get("outdoor", false)):
		eff *= WeatherManager.outdoor_factor() + 0.1
	var score := clampf(raw_score * eff, 0.0, 100.0)
	var base := daily_pay()
	var pay_mult := 1.0 + clampf((score - 70.0) / 150.0, -0.15, 0.2)
	var late := late_minutes > LATE_GRACE_MIN
	if late:
		pay_mult -= 0.1
		current["late_count"] = int(current.get("late_count", 0)) + 1
	var pay := int(round(base * pay_mult))
	var bonus_rain := 0
	if bool(j.get("outdoor", false)) and WeatherManager.is_raining():
		bonus_rain = 40
	var perf_delta := (score - 60.0) / 4.0 - (4.0 if late else 0.0)
	change_perf(perf_delta)
	current["boss_rel"] = clampf(float(current.get("boss_rel", 50)) + (score - 60.0) / 12.0 - (3.0 if late else 0.0), 0.0, 100.0)
	current["xp"] = float(current.get("xp", 0)) + 10.0 + score / 10.0
	current["shifts_total"] = int(current.get("shifts_total", 0)) + 1
	current["shifts_level"] = int(current.get("shifts_level", 0)) + 1
	current["last_shift_day"] = TimeManager.day
	# 技能经验
	var sx: Dictionary = j.get("skill_xp", {})
	var xp_mult := 0.6 + score / 100.0 * 0.6
	for s in sx:
		SkillManager.add_xp(String(s), float(sx[s]) * xp_mult, "工作")
	# 属性
	var fit := SkillManager.level("fitness")
	PlayerManager.change("energy", -float(j.get("energy_cost", 30)) * (1.0 - fit * 0.03))
	PlayerManager.change("hunger", -float(j.get("hunger_cost", 15)))
	PlayerManager.change("stress", float(j.get("stress_gain", 10)) * (1.2 if score < 50 else 1.0) - (4.0 if score >= 85 else 0.0))
	PlayerManager.change("mood", (score - 55.0) / 10.0)
	PlayerManager.change_reputation(0.4 if score >= 70 else 0.0)
	if job_id() == "restaurant":
		PlayerManager.change("hunger", 30)
	# 时间：从现在快进到下班
	var remaining := maxf(30.0, shift_end_minute() - TimeManager.total_minutes)
	TimeManager.advance(remaining, "work")
	# 工资
	if is_monthly():
		current["pending_pay"] = int(current.get("pending_pay", 0)) + pay
	else:
		EconomyManager.earn(pay, "日薪", "%s 日薪" % title())
	if bonus_rain > 0:
		EconomyManager.earn(bonus_rain, "奖金", "雨天补贴")
	EconomyManager.note_work_income(pay)
	var result := {
		"job": job_id(), "title": title(), "raw": raw_score, "score": score, "eff": eff, "pay": pay, "monthly": is_monthly(),
		"late": late, "perf": perf(), "perf_delta": perf_delta, "rain_bonus": bonus_rain, "promoted": "", "demoted": "", "fired": false,
	}
	# 升职 / 降职 / 解雇
	var promo := _check_promotion()
	if promo != "":
		result["promoted"] = promo
	elif perf() < 25.0 and level() > 0 and int(current.get("shifts_level", 0)) >= 5:
		current["level"] = level() - 1
		current["shifts_level"] = 0
		current["perf"] = 45.0
		result["demoted"] = title()
		Events.say("绩效太差，你被降职为「%s」" % title(), "bad")
	elif perf() < 12.0:
		result["fired"] = true
		fire("绩效长期不达标")
	Events.notify("work_shift", {"job": String(result["job"]), "score": score})
	if String(DataDB.job(String(result["job"])).get("minigame", "")) in ["code", "analysis"]:
		Events.notify("practice", {"skill": "computer" if String(result["job"]) == "tech" else "finance"})
	last_result = result
	Events.shift_finished.emit(result)
	Events.stats_changed.emit()
	return result


## 帮忙顶班（任务：不是自己的工作也可以帮一次忙，不发工资，报酬走任务奖励）
func finish_guest_shift(at_job: String, raw_score: float) -> Dictionary:
	var score := clampf(raw_score * PlayerManager.efficiency(), 0.0, 100.0)
	TimeManager.advance(240.0, "work")
	PlayerManager.change("energy", -18)
	PlayerManager.change("hunger", -10)
	var sx: Dictionary = DataDB.job(at_job).get("skill_xp", {})
	for s in sx:
		SkillManager.add_xp(String(s), float(sx[s]) * 0.6, "帮忙")
	Events.notify("work_shift", {"job": at_job, "score": score})
	var r := {"job": at_job, "title": "帮忙", "raw": raw_score, "score": score, "eff": 1.0, "pay": 0, "monthly": false, "late": false,
		"perf": 0.0, "perf_delta": 0.0, "rain_bonus": 0, "promoted": "", "demoted": "", "fired": false, "guest": true}
	last_result = r
	return r


func next_step() -> Dictionary:
	var l := ladder()
	if level() + 1 >= l.size():
		return {}
	return l[level() + 1]


func promotion_days_needed() -> int:
	var nx := next_step()
	if nx.is_empty():
		return 0
	var d := int(nx.get("days", 5))
	if String(job().get("category", "")) in ["office", "manager"]:
		d -= int(NPCManager.perk_value("promotion_boost"))
	return maxi(1, d)


## 升职条件缺什么（手机「人物」页显示）
func promotion_missing() -> Array:
	var nx := next_step()
	if nx.is_empty():
		return []
	var out: Array = SkillManager.missing(nx.get("req", {}))
	if int(current.get("shifts_level", 0)) < promotion_days_needed():
		out.append("本职级出勤 %d / %d 班" % [int(current.get("shifts_level", 0)), promotion_days_needed()])
	if perf() < float(nx.get("perf", 65)):
		out.append("绩效 %d / %d" % [int(perf()), int(nx.get("perf", 65))])
	if PlayerManager.reputation < float(nx.get("rep", 0)):
		out.append("声望 %d / %d" % [int(PlayerManager.reputation), int(nx.get("rep", 0))])
	if float(current.get("boss_rel", 50)) < 40.0:
		out.append("上司评价 %d / 40" % int(current.get("boss_rel", 50)))
	return out


func _check_promotion() -> String:
	if next_step().is_empty() or not promotion_missing().is_empty():
		return ""
	current["level"] = level() + 1
	current["shifts_level"] = 0
	promotions += 1
	PlayerManager.change_reputation(3)
	PlayerManager.change("mood", 12)
	Events.notify("promote", {"job": job_id(), "level": level()})
	Events.banner.emit("升职了！", "%s · %s" % [title(), pay_text(job_id(), level())])
	AudioManager.play_sfx("levelup")
	return title()


## 请假：sick 为真（身体原因 / 事件）时不扣绩效
func take_leave(sick := false) -> String:
	if not has_job():
		return "你现在没有工作"
	if not is_workday():
		return "今天本来就休息"
	if worked_today():
		return "今天的班已经上完了"
	current["leave_day"] = TimeManager.day
	var week := int((TimeManager.day - 1) / 7)
	if sick:
		return "已请病假，好好休息。"
	if NPCManager.has_perk("cover_leave") and leave_week_used != week:
		leave_week_used = week
		return "小张帮你顶了班，这次请假不影响绩效。"
	change_perf(-3)
	return "已请假（绩效 -3）。"


## 生病等原因耽误了今天的班（已经迟到）时自动请病假。返回是否请了假
func sick_leave_if_missed() -> bool:
	if not has_job() or not is_workday() or worked_today() or on_leave_today():
		return false
	if hired_today():
		return false
	if TimeManager.total_minutes <= shift_start_minute() + LATE_GRACE_MIN:
		return false
	take_leave(true)
	return true


## 加班（随机事件）后给的额外时间已经在 Effects 里处理
func _on_day_changed(d: int) -> void:
	# 过期的面试邀请
	for inv in invites.duplicate():
		if int(inv["expires_day"]) < d:
			invites.erase(inv)
	invites_changed.emit()
	if not has_job():
		return
	var y := d - 1
	var hired_day := int(current.get("hired_day", d))
	# 昨天应该上班却没来：旷工（入职当天不算，第二个工作日起才要求出勤）
	if y > hired_day and is_workday(y) and int(current.get("last_shift_day", -1)) != y and int(current.get("leave_day", -1)) != y:
		current["absences"] = int(current.get("absences", 0)) + 1
		change_perf(-12)
		current["boss_rel"] = clampf(float(current.get("boss_rel", 50)) - 10.0, 0.0, 100.0)
		var n := int(current["absences"])
		if n >= 3:
			fire("多次旷工")
			return
		Events.phone_message.emit("上司", "你昨天怎么没来上班？这是第 %d 次旷工了，满 3 次公司会解除合同。" % n)
	# 周五晚上发周薪（进入周六时）
	if (d - 1) % 7 == 5:
		var p := int(current.get("pending_pay", 0))
		if p > 0:
			_pay_pending("本周工资")
			Events.phone_message.emit("新澜银行", "您的工资 %s 已到账。" % Fmt.yuan(p))
	# 月初绩效奖金
	if TimeManager.day_of_month(d) == 1 and perf() >= 80.0 and int(current.get("shifts_total", 0)) >= 5:
		var bonus := int(daily_pay() * (4.4 if is_monthly() else 3.0))
		EconomyManager.earn(bonus, "奖金", "月度绩效奖金", is_monthly())
		Events.phone_message.emit("上司", "上个月表现优秀，发放绩效奖金 %s。" % Fmt.yuan(bonus))


func to_dict() -> Dictionary:
	return {"current": current, "history": history, "invites": invites, "rejected": rejected, "promotions": promotions,
		"interviews_passed": interviews_passed, "leave_week_used": leave_week_used}


func from_dict(d: Dictionary) -> void:
	current = Dictionary(d.get("current", {})).duplicate(true)
	history = Array(d.get("history", [])).duplicate(true)
	invites = Array(d.get("invites", [])).duplicate(true)
	rejected.clear()
	for k in d.get("rejected", {}):
		rejected[String(k)] = int(d["rejected"][k])
	promotions = int(d.get("promotions", 0))
	interviews_passed = int(d.get("interviews_passed", 0))
	leave_week_used = int(d.get("leave_week_used", -1))
	# JSON 读回的数字都是 float，这里把整数字段转回来
	for k in ["level", "shifts_total", "shifts_level", "absences", "hired_day", "last_shift_day", "pending_pay", "leave_day", "late_count"]:
		if current.has(k):
			current[k] = int(current[k])
	Events.job_changed.emit()
