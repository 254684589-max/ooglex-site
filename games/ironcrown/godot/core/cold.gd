class_name Cold
extends RefCounted
## 寒冷与冻伤（路线图 5.2c；STORY.md 5.7「寒冷与冻伤」；GDD.md 第九节「寒冷值在户外缓慢上升，靠火堆、酒馆、厚衣服降低」从第二章起真正生效）。
## 规则都在这里，状态（GameState.cold、GameState.frostbite）跟着存档走；main 每帧调 tick()。
##   涨：只在冷的户外区域（COLD_AREAS：第二章的余火高地）。白天一百满格约 7 分钟，清晨、黄昏快一些，夜里快一倍；山脊上（高处风口）再快一些；
##       「生存」技能每 10 点慢 5%（最多慢一半）。
##   降：火边（亮着的火：铁匠炉、驿站壁炉，组 light_source、元数据 radius）比涨快得多；屋里慢慢降；喝烈酒一口气降 40（物品 warm）。
##   冻伤：涨满了冻伤——体力上限少三成（GameState.stamina_max），直到在火边连着歇 FIRE_CURE 秒才好；冻伤时寒冷值停在满格。
## 界面：不加新的条（GDD 第十一节 HUD 极简），冷的时候体力条边上一行字（hud.set_cold）；第一次冷到 30 弹教学提示 cold。

const COLD_AREAS := {"highland": 1.0}
const BASE_RATE := 100.0 / 420.0                  # 白天：约 7 分钟满格
const DAYPART_MULT := {"day": 1.0, "dawn": 1.3, "dusk": 1.3, "night": 2.0}
const HIGH_Y := 26.0                              # 高过这个高度（山脊、风口）涨得快
const HIGH_MULT := 1.35
const FIRE_RATE := -12.0                          # 火边每秒降多少
const INDOOR_RATE := -3.0
const FIRE_REACH := 1.6                           # 火的 radius 再放大几倍算「在火边」
const FIRE_CURE := 8.0                            # 冻伤：在火边连着歇几秒才好
const FROSTBITE_STAMINA := 0.7
const LEVELS := [[30.0, "有点冷"], [60.0, "冷得发抖"], [85.0, "快冻僵了"]]
const FROSTBITE_TEXT := "冻伤：体力上限降低（到火边歇一会儿）"
const SURVIVAL_TRAIN := 0.25                      # 在冷里每秒练多少「生存」


## 这个区域冷不冷（户外的冷区域）
static func applies(area: String) -> bool:
	return COLD_AREAS.has(area)


## 每秒寒冷值变多少（正 = 变冷）
static func rate(area: String, daypart: String, y: float, survival: int, near_fire: bool, indoor: bool) -> float:
	if near_fire:
		return FIRE_RATE
	if indoor:
		return INDOOR_RATE
	if not applies(area):
		return 0.0
	var r := BASE_RATE * float(COLD_AREAS[area]) * float(DAYPART_MULT.get(daypart, 1.0))
	if y > HIGH_Y:
		r *= HIGH_MULT
	r *= 1.0 - clampf(survival / 10.0 * 0.05, 0.0, 0.5)
	return r


## 站在哪盏亮着的火边（组 light_source，带 radius 元数据的）
static func near_fire(tree: SceneTree, p: Vector3) -> bool:
	for l in tree.get_nodes_in_group("light_source"):
		if not (l is Node3D) or not l.has_meta("radius") or not (l as Node3D).is_visible_in_tree():
			continue
		if (l as Node3D).global_position.distance_to(p) <= float(l.get_meta("radius")) * FIRE_REACH:
			return true
	return false


## 现在的那一行字（"" = 不冷，不显示）
static func text() -> String:
	if GameState.frostbite:
		return FROSTBITE_TEXT
	var out := ""
	for lv in LEVELS:
		if GameState.cold >= float(lv[0]):
			out = "寒冷：" + str(lv[1])
	return out


## 一帧：涨 / 降寒冷值，满了冻伤，火边歇够了冻伤好。返回发生了什么："" / "frostbite" / "cured"。state 是 main 留着的一点东西（在火边歇了多久）
static func tick(tree: SceneTree, area: String, indoor: bool, daypart: String, p: Vector3, delta: float, state: Dictionary) -> String:
	var fire := near_fire(tree, p)
	var r := rate(area, daypart, p.y, int(GameState.skills.get("survival", 5)), fire, indoor)
	var event := ""
	if GameState.frostbite:
		state["cure"] = float(state.get("cure", 0.0)) + delta if fire else 0.0
		if float(state.cure) >= FIRE_CURE:
			GameState.frostbite = false
			GameState.cold = 0.0
			state["cure"] = 0.0
			event = "cured"
		return event
	GameState.cold = clampf(GameState.cold + r * delta, 0.0, 100.0)
	if r > 0.0:
		GameState.train("survival", SURVIVAL_TRAIN * delta)      # 在冷里待着练「生存」（同潜行：蹲着走练潜行）
	if GameState.cold >= 100.0:
		GameState.frostbite = true
		event = "frostbite"
	return event
