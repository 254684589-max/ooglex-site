class_name EmberguardKit
extends RefCounted
## 烬卫的职业规则（TECH.md 第 4.4 节 ClassKit 接口：can_cast / on_cast / on_hit / tick）。
## 资源「誓火」：命中敌人获得，上限 100；脱战 decay_delay_s 秒后按 decay_per_s 衰减（GDD.md 第 5.1 节）。

var cfg: Dictionary
var resource := 0.0
var resource_max := 100.0
var since_hit := 999.0
var cooldowns := {}


func _init() -> void:
	cfg = Balance.data().classes.emberguard
	resource_max = cfg.resource_max


func can_cast(skill_id: String) -> bool:
	var s := Balance.skill(skill_id)
	if cooldowns.get(skill_id, 0.0) > 0.0:
		return false
	return resource >= s.get("cost", 0)


func on_cast(skill_id: String) -> void:
	var s := Balance.skill(skill_id)
	resource -= s.get("cost", 0)
	if s.has("cooldown_s"):
		cooldowns[skill_id] = s.cooldown_s


func on_hit(skill_id: String, hits: int) -> void:
	if hits <= 0:
		return
	since_hit = 0.0
	var s := Balance.skill(skill_id)
	resource = minf(resource_max, resource + s.get("gain", 0) * hits)


func tick(delta: float) -> void:
	since_hit += delta
	if since_hit > cfg.decay_delay_s:
		resource = maxf(0.0, resource - cfg.decay_per_s * delta)
	for k in cooldowns.keys():
		cooldowns[k] = maxf(0.0, cooldowns[k] - delta)
