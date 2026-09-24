class_name TaskCatalog
extends RefCounted
## 任务目录（数据）。新增任务 = 在 TASKS 里追加一条字典。
##
## 字段说明：
##   id / title / summary        任务标识、标题、一句话说明
##   reward / reputation         报酬（元）与完成后增加的声望
##   min_day / min_reputation    解锁条件：第几天起、声望多少起
##   requires                    需要先至少完成过一次的任务 id
##   daily_limit                 每天最多接几次
##   grants_meal_ticket          接活时发一张饭票（「管一顿饭」）
##   objectives                  目标列表，见 task_definition.gd

const TASKS := [
	{
		"id": "haul_bricks",
		"title": "搬砖",
		"summary": "把砖块堆放区的红砖搬到施工楼一层的砌筑作业面。",
		"reward": 280,
		"reputation": 1,
		"grants_meal_ticket": true,
		"objectives": [
			{"type": "deliver", "item": "brick", "zone": "brick_zone", "count": 20},
		],
		"accept_line": "砖块堆放区的红砖，搬 20 块到施工楼一层的砌筑作业面。干完了钱直接转你手机上。",
		"complete_line": "砖码得挺齐！280 块转你了，注意查收。",
	},
	{
		"id": "haul_cement",
		"title": "搬水泥",
		"summary": "搅拌站等着下料：从水泥库扛 8 袋水泥过去。一袋 25 公斤，量力而行。",
		"reward": 160,
		"reputation": 1,
		"requires": ["haul_bricks"],
		"objectives": [
			{"type": "deliver", "item": "cement", "zone": "cement_zone", "count": 8},
		],
		"accept_line": "搅拌站那边等着下料，水泥库扛 8 袋过去。一袋 25 公斤，别逞强，累了就歇会儿。",
		"complete_line": "行，搅拌站能开机了。160，拿着。",
	},
	{
		"id": "haul_rebar",
		"title": "搬钢筋",
		"summary": "钢筋堆场的成捆钢筋，搬 10 捆到施工楼西侧的钢筋绑扎区。",
		"reward": 200,
		"reputation": 1,
		"min_day": 2,
		"requires": ["haul_bricks"],
		"objectives": [
			{"type": "deliver", "item": "rebar", "zone": "rebar_zone", "count": 10},
		],
		"accept_line": "钢筋绑扎区缺料，去西边钢筋堆场搬 10 捆过去。钢筋长，拐弯的时候看着点人。",
		"complete_line": "钢筋工那边说够用了。200 转你了。",
	},
]


static func build() -> Array:
	var out: Array = []
	for d in TASKS:
		out.append(TaskDefinition.from_dict(d))
	return out
