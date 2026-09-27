class_name CharModels
extends RefCounted
## 角色配方（2.6 之三，方案 1）：用 RigBuilder 把每种角色拼成蒙皮网格。同一种角色只生成一次，所有实例共用网格。
## 造型依据 ART.md：头身比约 1:6，肩、手、武器放大 1.2–1.5 倍，剪影优先（缩小后也认得出）。
##   wanderer：主角「流浪者」（V0.1 的可玩角色，D10）。风尘旅人：深红褐长外套、皮胸甲与斜挎带、左肩一块铁肩甲（不对称剪影）、
##     围巾、长靴、右手长剑；左前臂有发光的余烬「灼痕」（ART.md 4.1：灼痕是三职业共用的外观线索）。
##   skeleton：骸骨战士（V0.1）。佝偻的白骨、肋骨一根根分开、眼窝冰蓝的光、一块锈肩甲、破腰布、锈剑与破圆盾。
##   skeleton_archer：骸骨弓手。同一副骨架，换成左手长弓、背后箭袋、兜帽破布。

static var _cache := {}
const SWORD_TILT := Basis(Vector3(1, 0, 0), 0.87)     # 约 50°，剑尖朝前下方


static func get_model(id: String) -> Dictionary:
	if not _cache.has(id):
		var t0 := Time.get_ticks_usec()
		var m: Dictionary
		match id:
			"skeleton":
				m = _skeleton(false)
			"skeleton_archer":
				m = _skeleton(true)
			_:
				m = _wanderer()
		m.build_ms = (Time.get_ticks_usec() - t0) / 1000.0
		_cache[id] = m
	return _cache[id]


static func ids() -> Array:
	return ["wanderer", "skeleton", "skeleton_archer"]


## 关节位置（模型空间，静止姿势：面朝 +Z，手臂下垂；左侧在 +X）。o 里可以覆盖左侧关节，右侧自动镜像。
static func joints(o: Dictionary = {}) -> Dictionary:
	var j := {
		"Hips": Vector3(0, 0.98, 0), "Spine": Vector3(0, 1.12, 0), "Chest": Vector3(0, 1.3, 0),
		"Neck": Vector3(0, 1.52, 0), "Head": Vector3(0, 1.6, 0),
		"LeftUpperArm": Vector3(0.25, 1.47, 0), "LeftLowerArm": Vector3(0.27, 1.18, -0.01), "LeftHand": Vector3(0.28, 0.92, 0.01),
		"LeftUpperLeg": Vector3(0.11, 0.94, 0), "LeftLowerLeg": Vector3(0.12, 0.52, 0.02), "LeftFoot": Vector3(0.12, 0.1, -0.01),
	}
	for k in o:
		j[k] = o[k]
	for side in ["UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot"]:
		var l: Vector3 = j["Left" + side]
		j["Right" + side] = Vector3(-l.x, l.y, l.z)
	return j


static func _idx() -> Dictionary:
	var d := {}
	for i in HumanoidRig.BONES.size():
		d[HumanoidRig.BONES[i][0]] = i
	return d


# ---------------- 主角：流浪者 ----------------

static func _wanderer() -> Dictionary:
	var J := joints()
	var B := _idx()
	var rb := RigBuilder.new()
	var skin := Color(0.8, 0.6, 0.47)
	var hair := Color(0.13, 0.1, 0.09)
	var coat := Color(0.36, 0.17, 0.12)       # 深红褐长外套
	var linen := Color(0.6, 0.53, 0.41)
	var leather := Color(0.38, 0.25, 0.15)
	var dark := Color(0.16, 0.12, 0.1)
	var iron := Color(0.52, 0.52, 0.56)
	var scarf := Color(0.62, 0.36, 0.14)      # 余烬色围巾
	var ember := Color(1.0, 0.5, 0.15)

	for side in ["Left", "Right"]:
		var sx := 1.0 if side == "Left" else -1.0
		var ul: Vector3 = J[side + "UpperLeg"]
		var ll: Vector3 = J[side + "LowerLeg"]
		var ft: Vector3 = J[side + "Foot"]
		# 裤腿（麻布）与长靴（皮）
		rb.limb(ul + Vector3(0, 0.04, 0), ll, 0.095, 0.072, B[side + "UpperLeg"], linen, B[side + "LowerLeg"], RigBuilder.BODY, 8, 0.12)
		rb.limb(ll + Vector3(0, 0.1, 0), ft, 0.078, 0.066, B[side + "LowerLeg"], leather, B[side + "Foot"], RigBuilder.BODY, 8)
		rb.tube([ll + Vector3(0, 0.02, 0), ll + Vector3(0, 0.11, 0)], [Vector2(0.086, 0.086), Vector2(0.09, 0.09)], [B[side + "LowerLeg"], B[side + "LowerLeg"]], dark, RigBuilder.BODY, 8)   # 靴口翻边
		rb.block(ft + Vector3(0, -0.04, 0.07), Vector3(0.12, 0.09, 0.27), B[side + "Foot"], leather, RigBuilder.BODY, Basis.IDENTITY, Vector2(0.9, 0.85))
		# 上臂（外套袖）、前臂（皮护腕）、手
		var ua: Vector3 = J[side + "UpperArm"]
		var la: Vector3 = J[side + "LowerArm"]
		var hd: Vector3 = J[side + "Hand"]
		rb.limb(ua + Vector3(-0.02 * sx, 0.02, 0), la, 0.085, 0.07, B[side + "UpperArm"], coat, B[side + "LowerArm"], RigBuilder.BODY, 8, 0.1)
		rb.limb(la, hd + Vector3(0, 0.03, 0), 0.068, 0.058, B[side + "LowerArm"], leather if side == "Right" else linen, B[side + "Hand"], RigBuilder.BODY, 8)
		rb.ellipsoid(hd + Vector3(0, -0.055, 0.01), Vector3(0.05, 0.068, 0.047), B[side + "Hand"], skin)
		# 外套下摆（前后分开，跟着腿摆）
		rb.block(Vector3(0.1 * sx, 0.74, 0.06), Vector3(0.17, 0.42, 0.05), [B.Hips, B[side + "UpperLeg"], 0.55], coat, RigBuilder.BODY, Basis(Vector3.RIGHT, deg_to_rad(-6)), Vector2(1.05, 1.0))
		rb.block(Vector3(0.1 * sx, 0.72, -0.1), Vector3(0.19, 0.48, 0.05), [B.Hips, B[side + "UpperLeg"], 0.35], coat, RigBuilder.BODY, Basis(Vector3.RIGHT, deg_to_rad(8)), Vector2(1.05, 1.0))
	# 左前臂的余烬灼痕（三道发光的纹路）
	var la_l: Vector3 = J.LeftLowerArm
	for k in 3:
		var y := la_l.y - 0.07 - k * 0.06
		rb.block(Vector3(la_l.x + 0.045, y, la_l.z + 0.035), Vector3(0.02, 0.028, 0.05), B.LeftLowerArm, ember, RigBuilder.GLOW, Basis(Vector3.FORWARD, deg_to_rad(25 + k * 10)))

	# 腰胯、腰带、皮包
	rb.tube([Vector3(0, 0.84, 0), Vector3(0, 0.98, 0), Vector3(0, 1.08, 0)], [Vector2(0.16, 0.12), Vector2(0.19, 0.13), Vector2(0.18, 0.125)], [B.Hips, B.Hips, [B.Hips, B.Spine, 0.4]], coat, RigBuilder.BODY, 9, true, Vector3.BACK)
	rb.tube([Vector3(0, 0.96, 0), Vector3(0, 1.02, 0)], [Vector2(0.2, 0.14), Vector2(0.2, 0.14)], [B.Hips, B.Hips], leather, RigBuilder.BODY, 9, false, Vector3.BACK)
	rb.block(Vector3(0, 0.99, 0.14), Vector3(0.07, 0.06, 0.02), B.Hips, iron, RigBuilder.METAL)
	rb.block(Vector3(-0.17, 0.92, 0.05), Vector3(0.08, 0.11, 0.1), B.Hips, leather)
	# 躯干：外套（胸宽腰窄，倒三角），皮胸甲，斜挎带
	rb.tube([Vector3(0, 1.06, 0), Vector3(0, 1.2, 0), Vector3(0, 1.36, 0.005), Vector3(0, 1.47, 0), Vector3(0, 1.53, 0)],
		[Vector2(0.17, 0.12), Vector2(0.19, 0.125), Vector2(0.23, 0.14), Vector2(0.24, 0.13), Vector2(0.1, 0.085)],
		[[B.Hips, B.Spine, 0.7], B.Spine, [B.Spine, B.Chest, 0.7], B.Chest, [B.Chest, B.Neck, 0.3]], coat, RigBuilder.BODY, 10, false, Vector3.BACK)
	rb.block(Vector3(0, 1.3, 0.1), Vector3(0.34, 0.3, 0.08), B.Chest, leather, RigBuilder.BODY, Basis.IDENTITY, Vector2(1.1, 0.9))
	rb.block(Vector3(0, 1.3, 0.14), Vector3(0.05, 0.5, 0.02), B.Chest, dark, RigBuilder.BODY, Basis(Vector3.FORWARD, deg_to_rad(-38)))
	rb.block(Vector3(0, 1.3, -0.135), Vector3(0.05, 0.5, 0.02), B.Chest, dark, RigBuilder.BODY, Basis(Vector3.FORWARD, deg_to_rad(38)))
	# 左肩铁肩甲（两层）与右肩的外套垫肩
	var sh: Vector3 = J.LeftUpperArm
	rb.ellipsoid(sh + Vector3(0.03, 0.04, 0), Vector3(0.14, 0.085, 0.14), [B.Chest, B.LeftUpperArm, 0.6], iron, RigBuilder.METAL, Basis(Vector3.FORWARD, deg_to_rad(-22)))
	rb.ellipsoid(sh + Vector3(0.07, -0.03, 0), Vector3(0.12, 0.06, 0.125), [B.Chest, B.LeftUpperArm, 0.8], iron.darkened(0.15), RigBuilder.METAL, Basis(Vector3.FORWARD, deg_to_rad(-35)))
	rb.ellipsoid(J.RightUpperArm + Vector3(-0.01, 0.03, 0), Vector3(0.1, 0.07, 0.1), [B.Chest, B.RightUpperArm, 0.5], coat)
	# 围巾 + 背后垂下的兜帽
	rb.tube([Vector3(0, 1.45, 0), Vector3(0, 1.56, 0.005)], [Vector2(0.15, 0.13), Vector2(0.12, 0.11)], [B.Chest, B.Neck], scarf, RigBuilder.BODY, 9)
	rb.ellipsoid(Vector3(0, 1.48, -0.12), Vector3(0.14, 0.1, 0.07), B.Chest, coat.darkened(0.1))
	rb.block(Vector3(0.05, 1.33, 0.14), Vector3(0.07, 0.24, 0.03), B.Chest, scarf, RigBuilder.BODY, Basis(Vector3.FORWARD, deg_to_rad(-8)))
	# 头：脸、头发、眉眼的暗影
	rb.limb(Vector3(0, 1.52, 0), Vector3(0, 1.64, 0.005), 0.052, 0.05, B.Neck, skin, B.Head)
	rb.ellipsoid(Vector3(0, 1.73, 0.012), Vector3(0.105, 0.128, 0.118), B.Head, skin, RigBuilder.BODY, Basis.IDENTITY, 6, 10)
	rb.ellipsoid(Vector3(0, 1.775, -0.02), Vector3(0.118, 0.11, 0.125), B.Head, hair, RigBuilder.BODY, Basis.IDENTITY, 5, 10)
	for sx in [1.0, -1.0]:
		rb.ellipsoid(Vector3(0.04 * sx, 1.735, 0.108), Vector3(0.022, 0.014, 0.012), B.Head, skin.darkened(0.6), RigBuilder.BODY, Basis.IDENTITY, 3, 5)   # 眼窝的暗影
	rb.ellipsoid(Vector3(0, 1.655, 0.07), Vector3(0.085, 0.05, 0.06), B.Head, skin.lerp(hair, 0.45), RigBuilder.BODY, Basis.IDENTITY, 4, 8)            # 短胡茬
	# 右手长剑（放大约 1.3 倍）：柄、护手、剑身、剑尖、配重球
	# 剑在手里朝前下方斜 50°：手肘自然弯曲时剑身正好朝前
	var h: Vector3 = J.RightHand + Vector3(0, -0.06, 0.01)
	var R := SWORD_TILT
	rb.block(h + R * Vector3(0, 0, -0.02), Vector3(0.035, 0.035, 0.17), B.RightHand, dark, RigBuilder.BODY, R)
	rb.block(h + R * Vector3(0, 0, 0.075), Vector3(0.24, 0.035, 0.045), B.RightHand, iron, RigBuilder.METAL, R)
	rb.block(h + R * Vector3(0, 0, 0.53), Vector3(0.07, 0.016, 0.86), B.RightHand, iron.lightened(0.15), RigBuilder.METAL, R, Vector2(0.8, 1.0))
	rb.spike(h + R * Vector3(0, 0, 0.955), h + R * Vector3(0, 0, 1.08), 0.034, B.RightHand, iron.lightened(0.15), RigBuilder.METAL, 4)
	rb.ellipsoid(h + R * Vector3(0, 0, -0.12), Vector3(0.03, 0.03, 0.03), B.RightHand, iron, RigBuilder.METAL, Basis.IDENTITY, 3, 6)
	var out := rb.commit()
	out.joints = J
	out.glow = Color(1.0, 0.48, 0.12)
	# scale：斜俯视镜头下放大一点，剪影更清楚（ART.md「适度夸张」）
	out.style = {"scale": 1.12, "stride": 1.7, "walk_ref": 5.0, "arm_swing": 26.0, "idle_arms": 9.0,
		"carry": {"RightUpperArm": Vector3(-12, 0, -4), "RightLowerArm": Vector3(-28, 0, 0)}}
	return out


# ---------------- 骸骨战士 / 骸骨弓手 ----------------

static func _skeleton(archer: bool) -> Dictionary:
	var J := joints({"LeftUpperArm": Vector3(0.22, 1.45, 0), "LeftLowerArm": Vector3(0.24, 1.17, 0.0), "LeftHand": Vector3(0.25, 0.92, 0.02)})
	var B := _idx()
	var rb := RigBuilder.new()
	var bone := Color(0.82, 0.77, 0.66)
	var old := Color(0.66, 0.6, 0.5)
	var gap := Color(0.14, 0.11, 0.09)
	var rust := Color(0.48, 0.3, 0.19)
	var rag := Color(0.22, 0.2, 0.17)
	var wood := Color(0.42, 0.28, 0.15)

	for side in ["Left", "Right"]:
		var sx := 1.0 if side == "Left" else -1.0
		var ul: Vector3 = J[side + "UpperLeg"]
		var ll: Vector3 = J[side + "LowerLeg"]
		var ft: Vector3 = J[side + "Foot"]
		rb.limb(ul, ll, 0.042, 0.034, B[side + "UpperLeg"], bone, B[side + "LowerLeg"], RigBuilder.BODY, 6)
		rb.ellipsoid(ll + Vector3(0, 0.01, 0.01), Vector3(0.05, 0.045, 0.05), [B[side + "UpperLeg"], B[side + "LowerLeg"], 0.5], old, RigBuilder.BODY, Basis.IDENTITY, 3, 6)
		rb.limb(ll, ft, 0.034, 0.028, B[side + "LowerLeg"], bone, B[side + "Foot"], RigBuilder.BODY, 6)
		rb.limb(ll + Vector3(0.025 * sx, 0, -0.01), ft + Vector3(0.025 * sx, 0.05, -0.01), 0.018, 0.015, B[side + "LowerLeg"], old, -1, RigBuilder.BODY, 5)
		rb.block(ft + Vector3(0, -0.05, 0.07), Vector3(0.09, 0.05, 0.22), B[side + "Foot"], bone, RigBuilder.BODY, Basis.IDENTITY, Vector2(0.8, 0.8))
		var ua: Vector3 = J[side + "UpperArm"]
		var la: Vector3 = J[side + "LowerArm"]
		var hd: Vector3 = J[side + "Hand"]
		rb.ellipsoid(ua, Vector3(0.05, 0.05, 0.05), [B.Chest, B[side + "UpperArm"], 0.7], old, RigBuilder.BODY, Basis.IDENTITY, 3, 6)
		rb.limb(ua, la, 0.034, 0.028, B[side + "UpperArm"], bone, B[side + "LowerArm"], RigBuilder.BODY, 6)
		rb.limb(la, hd, 0.028, 0.024, B[side + "LowerArm"], bone, B[side + "Hand"], RigBuilder.BODY, 6)
		rb.limb(la + Vector3(0.022 * sx, 0, 0.012), hd + Vector3(0.022 * sx, 0.04, 0.012), 0.014, 0.012, B[side + "LowerArm"], old, -1, RigBuilder.BODY, 5)
		# 手：掌骨 + 三根指头
		rb.block(hd + Vector3(0, -0.04, 0.005), Vector3(0.06, 0.07, 0.03), B[side + "Hand"], bone)
		for f in 3:
			rb.limb(hd + Vector3((f - 1) * 0.02, -0.07, 0.01), hd + Vector3((f - 1) * 0.022, -0.13, 0.03), 0.009, 0.007, B[side + "Hand"], bone, -1, RigBuilder.BODY, 4)
	# 骨盆、脊柱（一节节的椎骨）
	rb.block(Vector3(0, 0.95, 0), Vector3(0.28, 0.13, 0.14), B.Hips, old, RigBuilder.BODY, Basis.IDENTITY, Vector2(1.2, 1.0))
	for k in 6:
		var y := 1.01 + k * 0.075
		var bspec = B.Spine if y < 1.2 else B.Chest
		rb.ellipsoid(Vector3(0, y, -0.06), Vector3(0.035, 0.03, 0.035), bspec, bone, RigBuilder.BODY, Basis.IDENTITY, 3, 6)
	# 肋骨：左右各 4 根弧形的骨头，从脊柱绕到胸前，中间有胸骨
	for k in 4:
		var y := 1.42 - k * 0.075
		var w := 0.19 - k * 0.012
		for sx in [1.0, -1.0]:
			var pts := []
			for a in 6:
				var th := lerpf(-PI * 0.5, PI * 0.42, a / 5.0)
				pts.append(Vector3(sx * w * cos(th), y - 0.03 * sin(th + 0.5), 0.12 * sin(th) - 0.01))
			var radii := []
			var bones := []
			for a in 6:
				radii.append(Vector2(0.016, 0.016))
				bones.append(B.Chest)
			rb.tube(pts, radii, bones, bone, RigBuilder.BODY, 5, true)
	rb.block(Vector3(0, 1.32, 0.115), Vector3(0.05, 0.26, 0.03), B.Chest, old)
	rb.tube([Vector3(0, 1.47, 0), Vector3(0, 1.5, 0)], [Vector2(0.2, 0.09), Vector2(0.18, 0.08)], [B.Chest, B.Chest], old, RigBuilder.BODY, 8, true, Vector3.BACK)   # 锁骨
	# 颈椎与头骨：颅顶、脸、下颌、黑眼窝里的冰蓝光
	rb.limb(Vector3(0, 1.5, -0.03), Vector3(0, 1.63, -0.01), 0.03, 0.028, B.Neck, bone, B.Head, RigBuilder.BODY, 6)
	rb.ellipsoid(Vector3(0, 1.75, -0.005), Vector3(0.11, 0.115, 0.125), B.Head, bone, RigBuilder.BODY, Basis.IDENTITY, 6, 10)
	rb.block(Vector3(0, 1.655, 0.055), Vector3(0.12, 0.06, 0.1), B.Head, old, RigBuilder.BODY, Basis.IDENTITY, Vector2(1.1, 1.0))
	for sx in [1.0, -1.0]:
		rb.ellipsoid(Vector3(0.045 * sx, 1.745, 0.1), Vector3(0.034, 0.03, 0.02), B.Head, gap, RigBuilder.BODY, Basis.IDENTITY, 3, 6)
		rb.ellipsoid(Vector3(0.045 * sx, 1.745, 0.112), Vector3(0.014, 0.014, 0.01), B.Head, Color(0.45, 0.85, 1.0), RigBuilder.GLOW, Basis.IDENTITY, 3, 5)
	rb.block(Vector3(0, 1.7, 0.118), Vector3(0.02, 0.035, 0.012), B.Head, gap)          # 鼻孔
	rb.block(Vector3(0, 1.66, 0.105), Vector3(0.08, 0.012, 0.012), B.Head, gap)         # 牙缝
	# 破腰布与一块锈肩甲（右肩）：打破对称，缩小后也看得出是「武装过的骷髅」
	rb.block(Vector3(0, 0.8, 0.09), Vector3(0.16, 0.3, 0.03), [B.Hips, B.LeftUpperLeg, 0.3], rag, RigBuilder.BODY, Basis(Vector3.RIGHT, deg_to_rad(-5)), Vector2(1.2, 1.0))
	rb.block(Vector3(0.02, 0.82, -0.09), Vector3(0.2, 0.26, 0.03), [B.Hips, B.RightUpperLeg, 0.3], rag, RigBuilder.BODY, Basis(Vector3.RIGHT, deg_to_rad(6)), Vector2(1.2, 1.0))
	if archer:
		# 兜帽破布披在肩上
		rb.ellipsoid(Vector3(0, 1.49, -0.07), Vector3(0.2, 0.08, 0.13), B.Chest, rag)
		rb.ellipsoid(Vector3(0, 1.79, -0.03), Vector3(0.125, 0.1, 0.13), B.Head, rag.lightened(0.05), RigBuilder.BODY, Basis(Vector3.RIGHT, deg_to_rad(-12)), 5, 9)
		# 背后箭袋 + 箭羽
		rb.block(Vector3(-0.06, 1.3, -0.16), Vector3(0.1, 0.42, 0.09), B.Chest, wood.darkened(0.2), RigBuilder.BODY, Basis(Vector3.FORWARD, deg_to_rad(20)))
		for k in 3:
			rb.block(Vector3(-0.13 + k * 0.025, 1.55, -0.16), Vector3(0.018, 0.1, 0.03), B.Chest, Color(0.7, 0.2, 0.15), RigBuilder.BODY, Basis(Vector3.FORWARD, deg_to_rad(20)))
		# 左手长弓：竖着握在手里的弧形弓臂 + 弓弦
		var hl: Vector3 = J.LeftHand + Vector3(0, -0.07, 0.03)
		var arc := []
		var radii := []
		var bones := []
		for a in 9:
			var t := lerpf(-1.0, 1.0, a / 8.0)
			arc.append(hl + Vector3(0, t * 0.62, 0.13 - 0.13 * t * t))
			radii.append(Vector2(0.022 - absf(t) * 0.008, 0.022 - absf(t) * 0.008))
			bones.append(B.LeftHand)
		rb.tube(arc, radii, bones, wood, RigBuilder.BODY, 5, true)
		rb.limb(hl + Vector3(0, 0.62, 0.0), hl + Vector3(0, -0.62, 0.0), 0.005, 0.005, B.LeftHand, Color(0.8, 0.75, 0.6), -1, RigBuilder.BODY, 3)
	else:
		# 右肩锈肩甲
		rb.ellipsoid(J.RightUpperArm + Vector3(-0.03, 0.04, 0), Vector3(0.13, 0.075, 0.12), [B.Chest, B.RightUpperArm, 0.6], rust, RigBuilder.METAL, Basis(Vector3.FORWARD, deg_to_rad(20)))
		# 右手锈剑（缺口剑身）
		var h: Vector3 = J.RightHand + Vector3(0, -0.07, 0.02)
		var R := SWORD_TILT
		rb.block(h + R * Vector3(0, 0, -0.01), Vector3(0.03, 0.03, 0.14), B.RightHand, gap, RigBuilder.BODY, R)
		rb.block(h + R * Vector3(0, 0, 0.07), Vector3(0.18, 0.03, 0.035), B.RightHand, rust, RigBuilder.METAL, R)
		rb.block(h + R * Vector3(0, 0, 0.45), Vector3(0.065, 0.016, 0.72), B.RightHand, rust.lightened(0.12), RigBuilder.METAL, R, Vector2(0.75, 1.0))
		rb.spike(h + R * Vector3(0, 0, 0.81), h + R * Vector3(0, 0, 0.92), 0.03, B.RightHand, rust.lightened(0.12), RigBuilder.METAL, 4)
		# 左前臂破圆盾（木板 + 铁箍）
		var sc: Vector3 = J.LeftLowerArm.lerp(J.LeftHand, 0.45) + Vector3(0.06, 0, 0.02)
		var sb := Basis(Vector3.FORWARD, deg_to_rad(90))
		rb.tube([sc + Vector3(-0.02, 0, 0), sc + Vector3(0.03, 0, 0)], [Vector2(0.22, 0.22), Vector2(0.21, 0.21)], [B.LeftLowerArm, B.LeftLowerArm], wood.darkened(0.15), RigBuilder.BODY, 9, true)
		rb.tube([sc + Vector3(0.028, 0, 0), sc + Vector3(0.045, 0, 0)], [Vector2(0.06, 0.06), Vector2(0.045, 0.045)], [B.LeftLowerArm, B.LeftLowerArm], rust, RigBuilder.METAL, 7, true)
		rb.block(sc + Vector3(0.035, 0.12, 0.08), Vector3(0.02, 0.05, 0.2), B.LeftLowerArm, gap, RigBuilder.BODY, sb)     # 缺口
	var out := rb.commit()
	out.joints = J
	out.glow = Color(0.45, 0.85, 1.0)
	var carry := {"RightUpperArm": Vector3(-14, 0, -6), "RightLowerArm": Vector3(-30, 0, 0), "LeftUpperArm": Vector3(-8, 0, 4), "LeftLowerArm": Vector3(-40, 0, 0)}
	if archer:
		carry = {"LeftUpperArm": Vector3(-18, 0, 4), "LeftLowerArm": Vector3(-30, 0, 0)}
	out.style = {"scale": 1.1, "stride": 1.25, "walk_ref": 3.2, "arm_swing": 16.0, "idle_arms": 6.0, "hunch": 11.0, "carry": carry}
	return out
