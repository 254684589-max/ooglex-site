class_name FloatText
extends Label3D
## 飘字（2.4 木桩的伤害数字，2.5 起敌人也用）：从 pos 往上飘 RISE 米、渐隐后自己删掉。总在最上层，不被身体挡住。

const TIME := 0.9
const RISE := 0.4

var left := TIME
var y0 := 0.0


static func spawn(parent: Node3D, text_value: String, pos: Vector3, color := Color("f2e6c8"), size := 30) -> FloatText:
	var l := FloatText.new()
	l.text = text_value
	l.font = load(Blocks.FONT_PATH)
	l.font_size = size
	l.pixel_size = 0.0026
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.outline_size = 8
	l.modulate = color
	l.no_depth_test = true
	l.render_priority = 1
	l.position = pos
	l.y0 = pos.y
	parent.add_child(l)
	return l


func _process(delta: float) -> void:
	left -= delta
	position.y = y0 + RISE * (1.0 - left / TIME)
	modulate.a = clampf(left / (TIME * 0.4), 0.0, 1.0)
	if left <= 0.0:
		queue_free()
