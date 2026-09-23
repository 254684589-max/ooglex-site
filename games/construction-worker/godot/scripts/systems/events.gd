extends Node
## 全局事件总线（自动加载名：Events）。
## 系统之间只通过信号通讯，UI 不直接依赖玩法脚本。

## UI 通知条。kind: info / good / warn / bad
signal toast(text: String, kind: String)
## 大字横幅（剧情提示、升级等）
signal banner(title: String, subtitle: String)
## 请求打开对话
signal dialogue_requested(npc_id: String)
## 对话结束（NPC 恢复走动）
signal dialogue_closed(npc_id: String)
## 请求打开商店
signal shop_requested(shop_id: String)
## 请求打开床铺菜单
signal bed_requested()
## 引导目标可能发生了变化
signal objective_changed()
## 新游戏 / 读档完成
signal game_started(from_save: bool)
## 睡觉结算完毕、新的一天开始
signal morning_started(day: int)


func say(text: String, kind := "info") -> void:
	toast.emit(text, kind)
