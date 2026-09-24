extends Node
## 全局信号总线（自动加载名：Events）。
## 各系统之间只通过这里的信号互相通知，避免直接引用对方的节点。

# ---- 提示与通知
signal toast(text: String, kind: String)
signal banner(title: String, subtitle: String)
signal phone_message(sender: String, text: String)

# ---- 界面请求（由 UIRoot 响应）
signal dialogue_requested(npc_id: String)
signal shop_requested(shop_id: String)
signal panel_requested(panel_id: String, args: Dictionary)
signal minigame_requested(kind: String, args: Dictionary)
signal event_popup_requested(event_data: Dictionary)
signal interview_requested(job_id: String)

# ---- 玩法事件（任务系统据此推进）
signal quest_event(kind: String, data: Dictionary)
signal location_entered(location_id: String)
signal stats_changed
signal skill_level_up(skill_id: String, level: int)
signal job_changed
signal shift_finished(result: Dictionary)
signal money_changed
signal housing_changed
signal relationship_changed(npc_id: String, value: int)
signal chapter_changed(chapter: int)
signal ending_reached(ending_id: String)
signal world_spawns_changed


func say(text: String, kind := "info") -> void:
	toast.emit(text, kind)


## 通知任务系统：发生了一件玩法事件（拜访地点、购买、上班……）
func notify(kind: String, data := {}) -> void:
	quest_event.emit(kind, data)
