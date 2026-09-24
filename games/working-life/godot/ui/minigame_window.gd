class_name MinigameWindow
extends UIWindow
## 承载工作小游戏的窗口。小游戏结束后发出 finished(score)。

signal finished(score: float)

var game: MinigameBase


func _init(g: MinigameBase) -> void:
	game = g
	super("上班中", Vector2(900, 640), false)
	window_id = "minigame"
	set_closable(false)


func _ready() -> void:
	super()
	body.add_child(game)
	game.finished.connect(func(s):
		finished.emit(s)
		force_close())
	var quit := UIKit.small_button("提前下班（按当前成绩结算）", func(): game.finish())
	footer.add_child(quit)
