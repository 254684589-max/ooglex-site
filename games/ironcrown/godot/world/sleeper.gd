class_name Sleeper
extends Node3D
## 长眠者第一次露面（路线图 4.10b；STORY.md 4.5 第 9 步、D11「长眠者」）：家主走了以后（主线「去烽燧线」），回到芦栈村——
## 一个你说过话的村民夜里没醒：闭着眼睛站起来，顺着栈道走过你身边，拐上去泥炭场的那条木板路，一直往北，走进北边的芦苇里，叫不醒、拦不住。
## 村里人只说一句「又一个」。是谁：跟你说过信使的渡工（heard_envoy）> 跟你说过堤道和水门的托宾（heard_causeway）> 村口补网的女人（谁都没说过话时）。
## 没被你撞见以前站在栈道上（客栈东边）不动；你走到 TRIGGER_R 以内就开始走（ch1_sleeper = 编号），CHAPTER_END_AFTER 秒后 main 打开章末画面。
## 这个人不再站在原来的地方（Marsh._people 跳过他）；走完了（或者读档时已经走了）就不在了。

const START := Vector3(84.0, MarshLayout.DECK_Y, 30.0)
## 走的路：主栈道往西 → 拐上去泥炭场的木板路往北 → 穿过泥炭场 → 北边的芦苇里
const PATH := [Vector3(66.0, MarshLayout.DECK_Y, 30.0), Vector3(66.0, MarshLayout.DECK_Y, 8.5), Vector3(66.0, MarshLayout.BANK_Y, -5.5), Vector3(66.0, MarshLayout.MUD_Y, -14.0)]
const SPEED := 0.9               # 梦游一样，比走路慢
const TRIGGER_R := 18.0
const CHAPTER_END_AFTER := 14.0
const LINES := ["（眼睛闭着，脚步一点没停。叫不醒。）", "（你拦在前面，他绕过你，接着往北走。）"]

var npc: Npc
var walking := false
var leg := 0
var t := 0.0


## 现在该出现吗：家主走了、还没撞见过
static func due() -> bool:
	return GameState.quest_stage("ch1_main") == "farewell" and not GameState.has_flag("ch1_sleeper")


## 这个人已经走了（或者正要走）：Marsh._people 不在老地方放他
static func gone_id() -> String:
	if GameState.has_flag("ch1_sleeper"):
		return str(GameState.get_flag("ch1_sleeper"))
	return who()[0] if due() else ""


## 是谁：[编号, 名字, 衣服颜色]
static func who() -> Array:
	var pick := "netter"
	if GameState.has_flag("heard_envoy"):
		pick = "boatman"
	elif GameState.has_flag("heard_causeway"):
		pick = "tobin"
	for p: Array in MarshLayout.PEOPLE:
		if str(p[0]) == pick:
			return [pick, str(p[1]), str(p[4])]
	return [pick, "村民", "4a4a4a"]


static func place(world: Node3D) -> Sleeper:
	if not due():
		return null
	var w := who()
	var s := Sleeper.new()
	s.name = "Sleeper"
	world.add_child(s)
	var n := Npc.make(str(w[1]), LINES, Color(str(w[2])))
	n.name = "Npc_sleeper"
	n.position = START
	n.rotation.y = PI / 2                                # 面朝西（栈道往西）
	s.add_child(n)
	s.npc = n
	return s


func near(p: Vector3) -> bool:
	return not walking and npc != null and Vector2(p.x - START.x, p.z - START.z).length() <= TRIGGER_R


## 撞见了：开始走，记下是谁
func wake_walk() -> void:
	walking = true
	GameState.set_flag("ch1_sleeper", who()[0])
	if npc.look_model:
		npc.look_model.play_loop("walk", 0.7, 0.4)
	print("IC_SLEEPER walk id=%s" % who()[0])


func _process(delta: float) -> void:
	if not walking or npc == null or leg >= PATH.size():
		return
	var to: Vector3 = PATH[leg]
	var d := to - npc.position
	var step := SPEED * delta
	if d.length() <= step:
		npc.position = to
		leg += 1
		if leg >= PATH.size():
			npc.visible = false                          # 走进芦苇里，看不见了
			npc.collision_layer = 0
			print("IC_SLEEPER gone")
		return
	npc.position += d.normalized() * step
	npc.rotation.y = atan2(-d.x, -d.z)
