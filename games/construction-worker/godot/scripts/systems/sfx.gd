extends Node
## 音效（自动加载名：Sfx）。音效文件由 tools/gen_sfx.py 合成。
## 用法：Sfx.play("pickup")。常见事件（进账、升级、对话）在这里统一监听。

const SOUNDS := {
	"pickup": preload("res://assets/audio/pickup.wav"),
	"place": preload("res://assets/audio/place.wav"),
	"coin": preload("res://assets/audio/coin.wav"),
	"click": preload("res://assets/audio/click.wav"),
	"levelup": preload("res://assets/audio/levelup.wav"),
	"door": preload("res://assets/audio/door.wav"),
}
const POOL_SIZE := 6

var _players: Array = []
var _next := 0


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	EconomySystem.cash_changed.connect(func(_c, delta, _r):
		if delta > 0:
			play("coin")
		elif delta < 0:
			play("click", -4.0))
	PlayerStats.skill_level_up.connect(func(_s, _l): play("levelup"))
	Events.dialogue_requested.connect(func(_id): play("click", -6.0))
	Events.shop_requested.connect(func(_id): play("click", -6.0))


func play(sound: String, volume_db := 0.0, pitch_jitter := 0.06) -> void:
	var stream: AudioStream = SOUNDS.get(sound)
	if stream == null:
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()
