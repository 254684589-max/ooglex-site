extends Node
## 界面缩放（修复阶段 1.1 发现的「手机竖屏文字过小」）。
## 工程的拉伸模式是 disabled，由这里按窗口大小设置 content_scale_factor：
##   缩放 = clamp(min(宽 / 480, 高 / 720), 0.75, 2.0)
## 1280×720 → 1.0；1920×1080 → 1.5；手机竖屏 360×740 → 0.75；平板竖屏 768×1024 → 1.42。
## 3D 画面始终按窗口实际分辨率渲染，只有界面按这个比例放大缩小。

const MIN_SCALE := 0.75
const MAX_SCALE := 2.0


func _ready() -> void:
	get_tree().root.size_changed.connect(apply)
	apply()


static func scale_for(size: Vector2) -> float:
	return clampf(minf(size.x / 480.0, size.y / 720.0), MIN_SCALE, MAX_SCALE)


func apply() -> void:
	var w := get_tree().root
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	w.content_scale_factor = scale_for(Vector2(w.size))
