class_name RoadSign
extends Node3D
## 路牌（路线图 4.1）：一根木桩、一块钉在桩前的木板，板上写着往哪儿去。脸朝本地 -Z（字从 -Z 那边读）；
## 从正面看，木板伸向桩的右边（本地 -X）——立在路的左边时，木板朝着路中间。
## 第一章章节包里的第一件东西：场景 res://chapters/ch1/road_sign.tscn 只在章节包里（脚本留在主包，Chapters 的约定），
## 网页上看得到它，就说明章节包下载、挂载成功了。4.3 起它是霜渡镇宅邸门口去鹭沼的路口。

@export var text := "往鹭沼 · 黑鹭堡"


func _ready() -> void:
	var wood := Look.mat("timber")
	Blocks.box(self, Vector3(0.12, 2.0, 0.12), Vector3(0, 1.0, 0), wood)
	Blocks.box(self, Vector3(1.5, 0.34, 0.06), Vector3(-0.45, 1.72, -0.09), wood, false)      # 钉在木桩前面（4.1 截图：板和桩在同一个面上，桩挡住了字）
	var l := Label3D.new()
	l.name = "Text"
	l.text = text
	l.font = load(Blocks.FONT_PATH)
	l.font_size = 32                    # 8 个字约 1.3 米，比板窄一点
	l.pixel_size = 0.0052
	l.modulate = Color("e8dcc0")
	l.outline_size = 6
	l.position = Vector3(-0.45, 1.72, -0.125)
	l.rotation_degrees = Vector3(0, 180, 0)
	add_child(l)
