class_name SleeperSlump
extends SkeletonModifier3D
## 长眠者的头（2026-11-07 所有者「长眠者做的不恐怖，能再恐怖些吗」→「先设计一下形象」）：
## 动作库里走路的动作是活人的——抬着头、看着前面。长眠者在动作播完以后把头垂下去：脖子往前低、头歪向一边，
## 再随着脚步极慢地左右晃一点（像睡着的人站着打盹），每个人歪的方向、角度、快慢都不一样。
## 方向在骨架空间写（模型面朝 +Z，同 actors/bow_aim.gd）。CharacterModel 看到 look.slump 就挂上（SleeperCrowd.chill 设）。

const NECK := "neck_01"
const HEAD := "Head"

var pitch := 0.42            # 往前低（弧度，约 24°），脖子和头各分一半
var roll := 0.22             # 歪向一边（正 = 往人的左边）
var sway := 0.05             # 慢慢晃的幅度
var sway_hz := 0.18
var phase := 0.0
var _t := 0.0
var glance_w := 0.0          # 0 = 照常垂着头，1 = 脸转向你

## 一起转头（2026-11-07 按建议）：你走到哪个长眠者 GLANCE_TRIGGER 米以内，附近 GLANCE_RANGE 米里的长眠者同时把脸转向你（眼睛还闭着），
## 停 GLANCE_HOLD 秒再转回去；之后 GLANCE_COOLDOWN 秒内不再转。不攻击。几个人共用一个时钟（Time），所以是同时转的。
const GLANCE_TRIGGER := 3.2
const GLANCE_RANGE := 14.0
const GLANCE_HOLD := 1.8
const GLANCE_COOLDOWN := 9.0
const GLANCE_TURN := 0.55    # 转过去、转回来各用多少秒
const GLANCE_MAX_YAW := 1.2  # 最多扭多少（弧度，约 70°）
static var glance_at := -1000.0     # 只放一个数（不放对象，测试退出时脚本才释放得干净）


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


## 现在转头转到几成（同一个时钟：大家一样）
static func glance_level() -> float:
	var t := now() - glance_at
	if t < 0.0 or t > GLANCE_TURN * 2.0 + GLANCE_HOLD:
		return 0.0
	if t < GLANCE_TURN:
		return smoothstep(0.0, 1.0, t / GLANCE_TURN)
	if t < GLANCE_TURN + GLANCE_HOLD:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (t - GLANCE_TURN - GLANCE_HOLD) / GLANCE_TURN)


static func attach(sk: Skeleton3D, seed: int) -> SleeperSlump:
	var m := SleeperSlump.new()
	m.name = "SleeperSlump"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	m.pitch = rng.randf_range(0.32, 0.55)
	m.roll = rng.randf_range(0.12, 0.3) * (1.0 if rng.randf() < 0.5 else -1.0)
	m.sway_hz = rng.randf_range(0.12, 0.24)
	m.phase = rng.randf() * TAU
	sk.add_child(m)
	return m


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	_t += delta
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var yaw := 0.0
	glance_w = 0.0
	if cam and sk.is_visible_in_tree():
		var head_i := sk.find_bone(HEAD)
		var head_w := sk.global_transform * (sk.get_bone_global_pose(head_i).origin if head_i >= 0 else Vector3(0, 1.6, 0))
		var d := Vector2(cam.global_position.x - head_w.x, cam.global_position.z - head_w.z).length()
		if d < GLANCE_TRIGGER and now() - glance_at > GLANCE_TURN * 2.0 + GLANCE_HOLD + GLANCE_COOLDOWN:
			glance_at = now()
		if d < GLANCE_RANGE:
			glance_w = glance_level()
			if glance_w > 0.0:
				var local := sk.global_transform.affine_inverse() * cam.global_position
				var hp := sk.get_bone_global_pose(head_i).origin if head_i >= 0 else Vector3(0, 1.6, 0)
				yaw = clampf(atan2(local.x - hp.x, local.z - hp.z), -GLANCE_MAX_YAW, GLANCE_MAX_YAW) * glance_w
	var r := (roll + sin(_t * TAU * sway_hz + phase) * sway) * (1.0 - glance_w * 0.7)
	var pt := pitch * (1.0 - glance_w * 0.75)            # 转过来的时候头也抬起来一点：闭着眼睛「看」着你
	var tilt := Basis(Vector3.UP, yaw * 0.5) * Basis(Vector3.RIGHT, pt * 0.5) * Basis(Vector3.BACK, r * 0.5)
	for b in [NECK, HEAD]:
		var i := sk.find_bone(b)
		if i < 0:
			continue
		var g := sk.get_bone_global_pose(i)
		var par := sk.get_bone_parent(i)
		var parent_basis := sk.get_bone_global_pose(par).basis if par >= 0 else Basis.IDENTITY
		var new_basis := tilt * g.basis
		sk.set_bone_pose_rotation(i, (parent_basis.inverse() * new_basis).get_rotation_quaternion())
