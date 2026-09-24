class_name ViewWindow
extends UIWindow
## 承载一个「视图构建函数」的窗口：builder.call(body, refresh)。背包、任务、人物页都用它。

var builder: Callable


func _init(p_title: String, p_builder: Callable, p_size := Vector2(760, 600), id := "") -> void:
	builder = p_builder
	super(p_title, p_size)
	window_id = id


func _ready() -> void:
	super()
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	clear_body()
	builder.call(body, refresh)
