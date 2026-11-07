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
	var r := roll + sin(_t * TAU * sway_hz + phase) * sway
	var tilt := Basis(Vector3.RIGHT, pitch * 0.5) * Basis(Vector3.BACK, r * 0.5)
	for b in [NECK, HEAD]:
		var i := sk.find_bone(b)
		if i < 0:
			continue
		var g := sk.get_bone_global_pose(i)
		var p := sk.get_bone_parent(i)
		var parent_basis := sk.get_bone_global_pose(p).basis if p >= 0 else Basis.IDENTITY
		var new_basis := tilt * g.basis
		sk.set_bone_pose_rotation(i, (parent_basis.inverse() * new_basis).get_rotation_quaternion())
