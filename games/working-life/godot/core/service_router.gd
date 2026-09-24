class_name ServiceRouter
extends RefCounted
## 交互点的行为表：根据 ServicePoint.kind 决定屏幕提示与按键后的动作。
## 简单动作（看病、健身、休息）直接在这里结算；需要界面的动作通过 Events.panel_requested 交给 UIRoot。

const TREATMENT_FEE := 200
const GYM_FEE := 30
const RELAX_FEE := 15


static func _open(sp: ServicePoint) -> bool:
	if bool(sp.args.get("always_open", false)):
		return true
	if sp.args.has("hours"):
		return LocationNode.hours_open(sp.args["hours"], TimeManager.hour_f())
	var loc := sp.location()
	return loc == null or loc.is_open()


static func _closed_label(sp: ServicePoint) -> String:
	var loc := sp.location()
	if sp.args.has("hours"):
		var h: Array = sp.args["hours"]
		return "已收摊（营业 %02d:00-%02d:00）" % [int(h[0]), int(h[1]) % 24]
	return "已打烊（%s）" % (loc.hours_text() if loc != null else "")


static func actions_for(sp: ServicePoint) -> Array:
	var key := sp.key
	if not _open(sp):
		return [Interactable.action(key, _closed_label(sp), false)]
	match sp.kind:
		"workstation":
			var job_id := String(sp.args.get("job", ""))
			if JobManager.has_job() and JobManager.job_id() == job_id:
				var chk := JobManager.can_start_shift(job_id)
				if bool(chk.get("ok", false)):
					var late := float(chk.get("late", 0.0))
					return [Interactable.action(key, "开始上班%s" % ("（迟到 %d 分钟）" % int(late) if late > 0 else ""))]
				return [Interactable.action(key, String(chk.get("reason", "")), false)]
			if guest_shift_available(job_id):
				return [Interactable.action(key, "帮忙顶班（任务）")]
			return [Interactable.action(key, "%s的工位（需要先被录用）" % String(DataDB.job(job_id).get("name", "")), false)]
		"interview":
			var venue := String(sp.args.get("venue", sp.loc_id))
			var inv := JobManager.invites_at(venue)
			if inv.is_empty():
				return [Interactable.action(key, "面试间（先在招聘 APP 投简历，拿到面试邀请）", false)]
			var j := String(inv[0]["job"])
			return [Interactable.action(key, "参加面试：%s" % String(JobManager.ladder(j)[int(inv[0]["level"])]["title"]))]
		"transit":
			var mode := String(sp.args.get("mode", "bus"))
			if not TransportManager.unlocked(mode):
				return [Interactable.action(key, String(TransportManager.mode(mode).get("unlock_text", "尚未开通")), false)]
			if mode == "bus" and TransportManager.bus_down():
				return [Interactable.action(key, "公交今天故障停运", false)]
			return [Interactable.action(key, sp.label_text)]
		"hotel_desk":
			return [Interactable.action(key, "前台：办理入住（%s / 晚）" % Fmt.yuan(HousingManager.rent_of("hotel")))]
		"incubator":
			if BusinessManager.has_company():
				return [Interactable.action(key, "管理公司「%s」" % String(BusinessManager.company.get("name", "")))]
			return [Interactable.action(key, "创业孵化中心：注册公司")]
		"bench":
			var acts := [Interactable.action(key, "坐下休息（30 分钟）")]
			var h := TimeManager.hour_f()
			if (h >= 21.0 or h < 5.0) and HousingManager.home_id() == "":
				acts = [Interactable.action(key, "在长椅上过夜（没有住处）")]
			return acts
		"gym":
			var fee_text := "会员免费" if PlayerManager.gym_member() else "单次 %s" % Fmt.yuan(GYM_FEE)
			return [Interactable.action(key, "健身锻炼 1 小时（%s）" % fee_text)]
		"hospital":
			return [Interactable.action(key, "挂号看病（%s）" % Fmt.yuan(treatment_fee()))]
		"relax":
			return [Interactable.action(key, "点杯饮品坐一会儿（%s，45 分钟）" % Fmt.yuan(RELAX_FEE))]
		"bed":
			return [Interactable.action(key, "床：睡觉 / 保存")]
	return [Interactable.action(key, sp.label_text)]


static func guest_shift_available(job_id: String) -> bool:
	if JobManager.has_job() and JobManager.job_id() == job_id:
		return false
	for id in QuestManager.active_ids():
		for i in QuestManager.open_indices(id):
			var o: Dictionary = QuestManager.objectives(id)[i]
			if String(o.get("type", "")) == "work_shift" and String(o.get("job", "")) == job_id:
				return true
	return false


static func treatment_fee() -> int:
	return int(TREATMENT_FEE * (1.0 - NPCManager.perk_value("clinic_discount")))


static func run(sp: ServicePoint, _action_key: String) -> void:
	if not _open(sp):
		return
	match sp.kind:
		"shop":
			Events.shop_requested.emit(String(sp.args.get("shop", "")))
		"workstation":
			Events.panel_requested.emit("shift", {"job": String(sp.args.get("job", ""))})
		"interview":
			var inv := JobManager.invites_at(String(sp.args.get("venue", sp.loc_id)))
			if not inv.is_empty():
				Events.interview_requested.emit(String(inv[0]["job"]))
		"jobboard":
			Events.panel_requested.emit("phone", {"app": "jobs"})
		"course":
			Events.panel_requested.emit("courses", {})
		"bank_counter", "atm":
			Events.panel_requested.emit("phone", {"app": "bank"})
		"hotel_desk":
			Events.panel_requested.emit("hotel", {})
		"lease":
			Events.panel_requested.emit("phone", {"app": "housing"})
		"incubator":
			if BusinessManager.has_company():
				Events.panel_requested.emit("manage_company", {})
			else:
				Events.panel_requested.emit("phone", {"app": "business"})
		"transit":
			Events.panel_requested.emit("travel", {"mode": String(sp.args.get("mode", "bus"))})
		"bed":
			Events.panel_requested.emit("sleep", {"home": String(sp.args.get("home", ""))})
		"wardrobe":
			Events.panel_requested.emit("wardrobe", {})
		"computer":
			Events.panel_requested.emit("computer", {})
		"rooftop":
			Events.panel_requested.emit("rooftop", {})
		"hospital":
			_treatment()
		"gym":
			_workout()
		"bench":
			var h := TimeManager.hour_f()
			if (h >= 21.0 or h < 5.0) and HousingManager.home_id() == "":
				Events.panel_requested.emit("sleep", {"home": "", "bench": true})
			else:
				TimeManager.advance(30, "idle")
				PlayerManager.change("energy", 8)
				PlayerManager.change("stress", -6)
				PlayerManager.change("mood", 3)
				Events.say("在长椅上坐了半小时（体力 +8 压力 -6 心情 +3）", "good")
		"relax":
			if not EconomyManager.spend(RELAX_FEE, "娱乐", "咖啡馆小坐"):
				Events.say("钱不够", "warn")
				return
			TimeManager.advance(45, "idle")
			PlayerManager.change("mood", 7)
			PlayerManager.change("stress", -9)
			PlayerManager.change("energy", 4)
			Events.say("窗外霓虹闪烁，你喝完了一杯拿铁（心情 +7 压力 -9）", "good")


static func _treatment() -> void:
	var fee := treatment_fee()
	if not EconomyManager.spend(fee, "医疗", "门诊"):
		Events.say("看病需要 %s，钱不够" % Fmt.yuan(fee), "warn")
		return
	TimeManager.advance(90, "idle")
	PlayerManager.change("health", 40)
	PlayerManager.change("stress", -5)
	PlayerManager.change("energy", 5)
	Events.notify("treatment", {})
	Events.say("许医生给你开了药，叮嘱你按时吃饭（健康 +40）", "good")


static func _workout() -> void:
	if PlayerManager.energy < 20.0:
		Events.say("体力不足 20，练不动了", "warn")
		return
	if not PlayerManager.gym_member():
		if not EconomyManager.spend(GYM_FEE, "娱乐", "健身单次"):
			Events.say("钱不够", "warn")
			return
	TimeManager.advance(60, "study")
	var bonus := 1.0 + NPCManager.perk_value("workout_bonus")
	SkillManager.add_xp("fitness", 35.0 * bonus * PlayerManager.efficiency(), "健身")
	PlayerManager.change("energy", -18)
	PlayerManager.change("health", 5)
	PlayerManager.change("mood", 5)
	PlayerManager.change("stress", -10)
	Events.notify("workout", {})
	AudioManager.play_sfx("levelup", -8.0)
	Events.say("练了一小时（体能经验 +%d，健康 +5，压力 -10）" % int(35.0 * bonus * PlayerManager.efficiency()), "good")
