class_name BowAim
extends SkeletonModifier3D
## 弓手拉弓（路线图 B.6b）：动作库里没有拉弓的动作，用骨骼修改器在动作播完以后把两条胳膊摆过去——
## 左臂（拿弓）伸直指向前方，右臂抬平、小臂折回来把弦拉到下巴边。influence 0 = 照动作，1 = 拉满（SoldierLook 按兵的状态推）。
## 方向在骨架空间写（模型面朝 +Z、人的左手在 +X，同 actors/gear.gd）。

## 骨头 → 要指的方向（从这根骨头指向下一根）
const AIM := [
	["upperarm_l", "lowerarm_l", Vector3(0.18, 0.12, 1.0)],
	["lowerarm_l", "hand_l", Vector3(0.12, 0.12, 1.0)],
	["upperarm_r", "lowerarm_r", Vector3(-0.75, 0.15, 0.55)],
	["lowerarm_r", "hand_r", Vector3(0.85, 0.2, -0.15)],
]


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for a in AIM:
		var i := sk.find_bone(str(a[0]))
		var c := sk.find_bone(str(a[1]))
		if i < 0 or c < 0:
			continue
		var g := sk.get_bone_global_pose(i)
		var cur := sk.get_bone_global_pose(c).origin - g.origin
		if cur.length() < 0.001:
			continue
		var want := (a[2] as Vector3).normalized()
		var q := Quaternion(cur.normalized(), want)
		var new_basis := Basis(q) * g.basis
		var p := sk.get_bone_parent(i)
		var parent_basis := sk.get_bone_global_pose(p).basis if p >= 0 else Basis.IDENTITY
		sk.set_bone_pose_rotation(i, (parent_basis.inverse() * new_basis).get_rotation_quaternion())
