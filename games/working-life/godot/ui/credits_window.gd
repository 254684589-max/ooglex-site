class_name CreditsWindow
extends UIWindow
## 制作人员。


func _init() -> void:
	super("制作人员", Vector2(640, 560))


func _ready() -> void:
	super()
	add_text("《打工》WORKING LIFE", 26, UIKit.CYAN)
	add_text("版本 1.1.0 · Ooglex 游戏中心", 16, UIKit.DIM)
	add_text("策划 / 程序 / 关卡 / 数值 / 测试：Ooglex 与 Claude（AI 编程助手）协作开发", 17)
	add_text("引擎：Godot Engine 4（MIT 许可）· GDScript", 16)
	add_text("字体：思源黑体 Noto Sans SC 子集（SIL Open Font License 1.1）", 16)
	add_text("美术：全部由代码程序化生成（几何体 + 霓虹材质），没有使用第三方模型与贴图。", 16)
	add_text("音乐与音效：由脚本合成（tools/gen_audio.py），没有使用第三方音频素材。", 16)
	add_text("游戏中的城市、公司、人物、投资品均为虚构；投资价格由游戏内部模型生成，与真实市场无关，不构成任何投资建议。", 15, UIKit.WARN)
	add_text("献给每一个拖着行李箱走出火车站的人。", 18, UIKit.MAGENTA)
