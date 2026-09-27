class_name CharModels
extends RefCounted
## 角色配方（2.6 之三，方案 1）：用 RigBuilder 把每种角色拼成蒙皮网格。同一种角色只生成一次，所有实例共用网格。
## 造型依据 ART.md：头身比约 1:6，肩、手、武器放大 1.2–1.5 倍，剪影优先（缩小后也认得出）。
##   wanderer：主角「流浪者」（V0.1 的可玩角色，D10）。风尘旅人：深红褐长外套、皮胸甲与斜挎带、左肩一块铁肩甲（不对称剪影）、
##     围巾、长靴、右手长剑；左前臂有发光的余烬「灼痕」（ART.md 4.1：灼痕是三职业共用的外观线索）。
##   skeleton：骸骨战士（V0.1）。佝偻的白骨、肋骨一根根分开、眼窝冰蓝的光、一块锈肩甲、破腰布、锈剑与破圆盾。
##   skeleton_archer：骸骨弓手。同一副骨架，换成左手长弓、背后箭袋、兜帽破布。
## 第二批（2.6 之三）：
##   zombie：腐尸（灰尸家族，ART.md 4.2：焦黑干裂、裂缝透出余烬、动作僵硬）。双臂前伸蹒跚，抓挠攻击。
##   ghoul：食尸鬼。灰绿、严重佝偻、长臂长爪、背上一排骨刺、绿眼。
##   knight：堕落骑士。全身板甲、头盔眼缝透红光、破旧暗红罩袍、双手大剑。
##   cultist / priest：邪教术士（紫袍兜帽）/ 灰誓祭司（灰袍、骨白面具；ART.md「教团：灰袍、面具」），拿顶端发光的法杖。
##   brute：焦骨蛮兵（测试区的冲锋怪）。高大魁梧的焦黑壮汉，裂缝透余烬光，头上一对角。

static var _cache := {}
const SWORD_TILT := Basis(Vector3(1, 0, 0), 0.87)     # 约 50°，剑尖朝前下方
const STAFF_TILT := Basis(Vector3(1, 0, 0), 0.75)     # 法杖顶端朝前约 43°：手肘弯曲拿着时正好竖直


static func get_model(id: String) -> Dictionary:
	if not _cache.has(id):
		var t0 := Time.get_ticks_usec()
		var m: Dictionary
		match id:
			"skeleton":
				m = _skeleton(false)
			"skeleton_archer":
				m = _skeleton(true)
			"zombie":
				m = _zombie()
			"ghoul":
				m = _ghoul()
			"knight":
				m = _knight()
			"cultist":
				m = _robed(false)
			"priest":
				m = _robed(true)
			"brute":
				m = _brute()
			_:
				m = _wanderer()
		m.build_ms = (Time.get_ticks_usec() - t0) / 1000.0
		_cache[id] = m
	return _cache[id]


static func ids() -> Array:
	return ["wanderer", "skeleton", "skeleton_archer", "zombie", "ghoul", "knight", "cultist", "priest", "brute"]


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


# ---------------- 第二批 ----------------

## 通用四肢：腿（大腿、小腿、脚）与手臂（上臂、前臂、手），c 里给颜色、粗细、用哪个面、有没有爪子
static func _limbs(rb: RigBuilder, J: Dictionary, B: Dictionary, c: Dictionary) -> void:
	var tr: float = c.get("thigh_r", 0.09)
	var sr: float = c.get("shin_r", 0.07)
	var ar: float = c.get("arm_r", 0.08)
	for side in ["Left", "Right"]:
		var sx := 1.0 if side == "Left" else -1.0
		var ul: Vector3 = J[side + "UpperLeg"]
		var ll: Vector3 = J[side + "LowerLeg"]
		var ft: Vector3 = J[side + "Foot"]
		rb.limb(ul + Vector3(0, 0.03, 0), ll, tr, sr * 1.1, B[side + "UpperLeg"], c.thigh, B[side + "LowerLeg"], c.get("thigh_surf", RigBuilder.BODY), 8, 0.12)
		rb.limb(ll, ft, sr, sr * 0.8, B[side + "LowerLeg"], c.shin, B[side + "Foot"], c.get("shin_surf", RigBuilder.BODY), 8)
		var fs: float = c.get("foot_s", 1.0)
		rb.block(ft + Vector3(0, -0.045, 0.07 * fs), Vector3(0.11, 0.08, 0.25) * fs, B[side + "Foot"], c.foot_col, c.get("shin_surf", RigBuilder.BODY), Basis.IDENTITY, Vector2(0.85, 0.85))
		var ua: Vector3 = J[side + "UpperArm"]
		var la: Vector3 = J[side + "LowerArm"]
		var hd: Vector3 = J[side + "Hand"]
		rb.limb(ua + Vector3(-0.02 * sx, 0.02, 0), la, ar, ar * 0.85, B[side + "UpperArm"], c.upper, B[side + "LowerArm"], c.get("upper_surf", RigBuilder.BODY), 8, 0.12)
		rb.limb(la, hd + Vector3(0, 0.03, 0), ar * 0.82 * float(c.get("cuff", 1.0)), ar * 0.7 * float(c.get("wrist", 1.0)), B[side + "LowerArm"], c.fore, B[side + "Hand"], c.get("fore_surf", RigBuilder.BODY), 8)
		var hs: float = c.get("hand", 1.0)
		rb.ellipsoid(hd + Vector3(0, -0.055 * hs, 0.01), Vector3(0.05, 0.068, 0.047) * hs, B[side + "Hand"], c.hand_col, c.get("hand_surf", RigBuilder.BODY))
		if c.has("claw"):
			for f in 3:
				var base := hd + Vector3((f - 1) * 0.028 * hs, -0.1 * hs, 0.02)
				rb.spike(base, base + Vector3((f - 1) * 0.02, -float(c.get("claw_len", 0.1)), 0.05), 0.014 * hs, B[side + "Hand"], c.claw, RigBuilder.BODY, 4)


## 余烬裂纹：一串斜着的发光小条（灰尸家族的「裂缝透出余烬」）
static func _cracks(rb: RigBuilder, center: Vector3, n: int, spread: Vector3, bone, col: Color, seed_v: int) -> void:
	for k in n:
		var h1 := RigBuilder._hash(seed_v * 31 + k * 7)
		var h2 := RigBuilder._hash(seed_v * 17 + k * 13)
		var h3 := RigBuilder._hash(seed_v * 5 + k * 29)
		var p := center + Vector3((h1 - 0.5) * spread.x, (h2 - 0.5) * spread.y, (h3 - 0.5) * spread.z)
		rb.block(p, Vector3(0.022, 0.1 + h3 * 0.08, 0.022), bone, col, RigBuilder.GLOW, Basis(Vector3.FORWARD, (h1 - 0.5) * 2.2))


static func _finish(rb: RigBuilder, J: Dictionary, glow: Color, style: Dictionary) -> Dictionary:
	var out := rb.commit()
	out.joints = J
	out.glow = glow
	out.style = style
	return out


static func _zombie() -> Dictionary:
	var J := joints({"LeftUpperArm": Vector3(0.23, 1.44, 0), "LeftLowerArm": Vector3(0.25, 1.16, 0.0), "LeftHand": Vector3(0.26, 0.9, 0.02)})
	var B := _idx()
	var rb := RigBuilder.new()
	var char_c := Color(0.22, 0.18, 0.15)
	var ash := Color(0.38, 0.34, 0.3)
	var rag := Color(0.26, 0.2, 0.15)
	var ember := Color(1.0, 0.45, 0.12)
	_limbs(rb, J, B, {"thigh": char_c, "shin": ash.darkened(0.2), "foot_col": char_c, "upper": ash.darkened(0.1), "fore": char_c, "hand_col": char_c,
		"thigh_r": 0.075, "shin_r": 0.058, "arm_r": 0.065, "claw": ash.lightened(0.2), "claw_len": 0.07})
	# 干瘦的躯干（肋骨突出的一圈圈）+ 腰间破布
	rb.tube([Vector3(0, 0.86, 0), Vector3(0, 1.0, 0), Vector3(0, 1.16, 0), Vector3(0, 1.34, 0.01), Vector3(0, 1.47, 0), Vector3(0, 1.52, 0)],
		[Vector2(0.14, 0.1), Vector2(0.15, 0.105), Vector2(0.13, 0.095), Vector2(0.18, 0.12), Vector2(0.2, 0.11), Vector2(0.08, 0.07)],
		[B.Hips, B.Hips, [B.Hips, B.Spine, 0.8], [B.Spine, B.Chest, 0.8], B.Chest, [B.Chest, B.Neck, 0.3]], char_c, RigBuilder.BODY, 9, true, Vector3.BACK)
	for k in 3:
		rb.block(Vector3(0, 1.22 + k * 0.065, 0.1), Vector3(0.26 - k * 0.02, 0.022, 0.04), B.Chest, ash, RigBuilder.BODY)
	rb.block(Vector3(0, 0.84, 0.07), Vector3(0.2, 0.3, 0.03), [B.Hips, B.LeftUpperLeg, 0.35], rag, RigBuilder.BODY, Basis(Vector3.RIGHT, deg_to_rad(-6)), Vector2(1.2, 1.0))
	rb.block(Vector3(0, 0.86, -0.08), Vector3(0.24, 0.26, 0.03), [B.Hips, B.RightUpperLeg, 0.35], rag, RigBuilder.BODY, Basis(Vector3.RIGHT, deg_to_rad(8)), Vector2(1.2, 1.0))
	rb.block(Vector3(-0.12, 1.38, -0.03), Vector3(0.22, 0.3, 0.2), B.Chest, rag.darkened(0.2), RigBuilder.BODY, Basis(Vector3.FORWARD, deg_to_rad(28)), Vector2(0.6, 0.9))   # 挂在一边肩上的破布
	_cracks(rb, Vector3(0.02, 1.3, 0.11), 5, Vector3(0.26, 0.26, 0.0), B.Chest, ember, 3)
	_cracks(rb, Vector3(0, 1.28, -0.11), 4, Vector3(0.26, 0.26, 0.0), B.Chest, ember, 9)
	_cracks(rb, (J.LeftUpperArm as Vector3).lerp(J.LeftLowerArm, 0.5) + Vector3(0.05, 0, 0.03), 2, Vector3(0.0, 0.12, 0.04), B.LeftUpperArm, ember, 5)
	# 头：凹陷的脸、余烬眼、掉下来的下巴
	rb.limb(Vector3(0, 1.5, 0), Vector3(0, 1.63, 0.01), 0.045, 0.045, B.Neck, char_c, B.Head)
	rb.ellipsoid(Vector3(0, 1.73, 0.01), Vector3(0.1, 0.12, 0.115), B.Head, char_c.lightened(0.05), RigBuilder.BODY, Basis.IDENTITY, 6, 10)
	rb.ellipsoid(Vector3(0, 1.79, -0.02), Vector3(0.105, 0.075, 0.11), B.Head, ash.darkened(0.3))
	for sx in [1.0, -1.0]:
		rb.ellipsoid(Vector3(0.04 * sx, 1.74, 0.1), Vector3(0.028, 0.024, 0.02), B.Head, Color(0.06, 0.04, 0.03), RigBuilder.BODY, Basis.IDENTITY, 3, 6)
		rb.ellipsoid(Vector3(0.04 * sx, 1.74, 0.11), Vector3(0.013, 0.013, 0.01), B.Head, ember, RigBuilder.GLOW, Basis.IDENTITY, 3, 5)
	rb.block(Vector3(0, 1.625, 0.08), Vector3(0.11, 0.04, 0.09), B.Head, ash.darkened(0.1), RigBuilder.BODY, Basis(Vector3.RIGHT, deg_to_rad(22)))
	return _finish(rb, J, Color(1.0, 0.45, 0.12), {"scale": 1.08, "stride": 1.0, "walk_ref": 1.6, "arm_swing": 5.0, "idle_arms": 4.0, "hunch": 14.0, "head_tilt": 12.0,
		"carry": {"RightUpperArm": Vector3(-72, 0, 6), "LeftUpperArm": Vector3(-64, 0, -4), "RightLowerArm": Vector3(-10, 0, 0), "LeftLowerArm": Vector3(-16, 0, 0)}})


static func _ghoul() -> Dictionary:
	var J := joints({"LeftUpperArm": Vector3(0.27, 1.42, 0.02), "LeftLowerArm": Vector3(0.31, 1.06, 0.05), "LeftHand": Vector3(0.32, 0.74, 0.08),
		"LeftUpperLeg": Vector3(0.13, 0.9, 0), "LeftLowerLeg": Vector3(0.15, 0.5, 0.08), "LeftFoot": Vector3(0.15, 0.1, -0.02)})
	var B := _idx()
	var rb := RigBuilder.new()
	var skin := Color(0.33, 0.37, 0.3)
	var dark := Color(0.2, 0.23, 0.19)
	var bone := Color(0.78, 0.74, 0.62)
	var eye := Color(0.7, 1.0, 0.3)
	_limbs(rb, J, B, {"thigh": skin, "shin": dark, "foot_col": dark, "upper": skin, "fore": dark, "hand_col": dark,
		"thigh_r": 0.1, "shin_r": 0.07, "arm_r": 0.085, "hand": 1.35, "claw": bone, "claw_len": 0.16})
	rb.tube([Vector3(0, 0.84, 0), Vector3(0, 1.0, 0), Vector3(0, 1.18, 0), Vector3(0, 1.36, 0.02), Vector3(0, 1.48, 0.02), Vector3(0, 1.53, 0.03)],
		[Vector2(0.17, 0.13), Vector2(0.19, 0.14), Vector2(0.2, 0.15), Vector2(0.25, 0.18), Vector2(0.24, 0.16), Vector2(0.1, 0.09)],
		[B.Hips, B.Hips, [B.Hips, B.Spine, 0.8], [B.Spine, B.Chest, 0.8], B.Chest, [B.Chest, B.Neck, 0.3]], skin, RigBuilder.BODY, 10, true, Vector3.BACK)
	rb.block(Vector3(0, 0.82, 0.06), Vector3(0.24, 0.24, 0.04), [B.Hips, B.LeftUpperLeg, 0.3], Color(0.2, 0.16, 0.12), RigBuilder.BODY, Basis.IDENTITY, Vector2(1.2, 1.0))
	# 背上一排骨刺
	for k in 5:
		var y := 1.05 + k * 0.1
		rb.spike(Vector3(0, y, -0.14 - k * 0.01), Vector3(0, y + 0.06, -0.26 - k * 0.012), 0.035, B.Spine if y < 1.2 else B.Chest, bone, RigBuilder.BODY, 5)
	# 大头往前探，张开的下巴与獠牙
	rb.limb(Vector3(0, 1.5, 0.02), Vector3(0, 1.62, 0.06), 0.07, 0.065, B.Neck, skin, B.Head)
	rb.ellipsoid(Vector3(0, 1.72, 0.07), Vector3(0.13, 0.12, 0.15), B.Head, skin, RigBuilder.BODY, Basis.IDENTITY, 6, 10)
	rb.block(Vector3(0, 1.62, 0.15), Vector3(0.18, 0.05, 0.16), B.Head, dark, RigBuilder.BODY, Basis(Vector3.RIGHT, deg_to_rad(25)), Vector2(0.8, 0.9))
	for k in 4:
		var x := -0.06 + k * 0.04
		rb.spike(Vector3(x, 1.66, 0.2), Vector3(x, 1.61, 0.215), 0.012, B.Head, bone, RigBuilder.BODY, 4)
	for sx in [1.0, -1.0]:
		rb.ellipsoid(Vector3(0.055 * sx, 1.75, 0.19), Vector3(0.022, 0.018, 0.012), B.Head, eye, RigBuilder.GLOW, Basis.IDENTITY, 3, 5)
		rb.spike(Vector3(0.09 * sx, 1.8, 0.02), Vector3(0.16 * sx, 1.86, -0.06), 0.02, B.Head, dark, RigBuilder.BODY, 4)   # 尖耳
	return _finish(rb, J, eye, {"scale": 1.08, "stride": 1.35, "walk_ref": 2.6, "arm_swing": 22.0, "idle_arms": 14.0, "hunch": 30.0,
		"carry": {"RightUpperArm": Vector3(-20, 0, -8), "LeftUpperArm": Vector3(-20, 0, 8), "RightLowerArm": Vector3(-20, 0, 0), "LeftLowerArm": Vector3(-20, 0, 0),
			"LeftUpperLeg": Vector3(-14, 0, 0), "RightUpperLeg": Vector3(-14, 0, 0), "LeftLowerLeg": Vector3(22, 0, 0), "RightLowerLeg": Vector3(22, 0, 0)}})


static func _knight() -> Dictionary:
	var J := joints({"LeftUpperArm": Vector3(0.27, 1.47, 0), "LeftLowerArm": Vector3(0.29, 1.18, 0.0), "LeftHand": Vector3(0.3, 0.92, 0.02)})
	var B := _idx()
	var rb := RigBuilder.new()
	var steel := Color(0.4, 0.4, 0.45)
	var dsteel := Color(0.26, 0.26, 0.3)
	var cloth := Color(0.35, 0.08, 0.08)
	var red := Color(1.0, 0.3, 0.15)
	_limbs(rb, J, B, {"thigh": dsteel, "shin": steel, "foot_col": dsteel, "upper": dsteel, "fore": steel, "hand_col": dsteel,
		"thigh_r": 0.1, "shin_r": 0.08, "arm_r": 0.09, "hand": 1.15, "foot_s": 1.1, "thigh_surf": RigBuilder.METAL, "shin_surf": RigBuilder.METAL, "upper_surf": RigBuilder.METAL, "fore_surf": RigBuilder.METAL, "hand_surf": RigBuilder.METAL, "cuff": 1.25})
	# 胸甲（倒三角）、腹甲、腰带
	rb.tube([Vector3(0, 0.88, 0), Vector3(0, 1.02, 0), Vector3(0, 1.18, 0), Vector3(0, 1.36, 0.01), Vector3(0, 1.48, 0), Vector3(0, 1.54, 0)],
		[Vector2(0.19, 0.14), Vector2(0.2, 0.145), Vector2(0.21, 0.15), Vector2(0.27, 0.17), Vector2(0.27, 0.15), Vector2(0.12, 0.1)],
		[B.Hips, B.Hips, [B.Hips, B.Spine, 0.8], [B.Spine, B.Chest, 0.8], B.Chest, [B.Chest, B.Neck, 0.3]], steel, RigBuilder.METAL, 10, true, Vector3.BACK)
	rb.block(Vector3(0, 1.33, 0.155), Vector3(0.04, 0.26, 0.03), B.Chest, dsteel, RigBuilder.METAL)
	rb.tube([Vector3(0, 0.97, 0), Vector3(0, 1.03, 0)], [Vector2(0.215, 0.16), Vector2(0.215, 0.16)], [B.Hips, B.Hips], Color(0.18, 0.12, 0.1), RigBuilder.BODY, 10, false, Vector3.BACK)
	# 破旧暗红罩袍（前后两片，跟着腿摆）
	rb.block(Vector3(0, 0.7, 0.13), Vector3(0.24, 0.52, 0.03), [B.Hips, B.LeftUpperLeg, 0.3], cloth, RigBuilder.BODY, Basis(Vector3.RIGHT, deg_to_rad(-5)), Vector2(1.15, 1.0))
	rb.block(Vector3(0, 0.68, -0.13), Vector3(0.28, 0.58, 0.03), [B.Hips, B.RightUpperLeg, 0.3], cloth, RigBuilder.BODY, Basis(Vector3.RIGHT, deg_to_rad(6)), Vector2(1.1, 1.0))
	rb.block(Vector3(0, 1.3, 0.17), Vector3(0.2, 0.28, 0.02), B.Chest, cloth)
	# 大肩甲（三层）
	for sx in [1.0, -1.0]:
		var side := "Left" if sx > 0 else "Right"
		var sh: Vector3 = J[side + "UpperArm"]
		for k in 3:
			rb.ellipsoid(sh + Vector3((0.03 + k * 0.035) * sx, 0.06 - k * 0.055, 0), Vector3(0.17 - k * 0.02, 0.09, 0.16 - k * 0.015), [B.Chest, B[side + "UpperArm"], 0.5 + k * 0.2], steel if k != 1 else dsteel, RigBuilder.METAL, Basis(Vector3.FORWARD, deg_to_rad(-25 * sx)))
		rb.spike(sh + Vector3(0.04 * sx, 0.13, 0), sh + Vector3(0.1 * sx, 0.28, -0.02), 0.035, [B.Chest, B[side + "UpperArm"], 0.5], dsteel, RigBuilder.METAL, 5)
	# 头盔：圆顶、护颈、眼缝里的红光、顶饰
	rb.limb(Vector3(0, 1.5, 0), Vector3(0, 1.62, 0.01), 0.07, 0.07, B.Neck, dsteel, B.Head, RigBuilder.METAL)
	rb.ellipsoid(Vector3(0, 1.74, 0.01), Vector3(0.13, 0.15, 0.14), B.Head, steel, RigBuilder.METAL, Basis.IDENTITY, 6, 10)
	rb.tube([Vector3(0, 1.6, 0), Vector3(0, 1.68, 0)], [Vector2(0.14, 0.14), Vector2(0.13, 0.13)], [B.Head, B.Head], dsteel, RigBuilder.METAL, 10, false)
	rb.block(Vector3(0, 1.745, 0.13), Vector3(0.17, 0.025, 0.03), B.Head, Color(0.05, 0.03, 0.03))
	rb.block(Vector3(0, 1.745, 0.14), Vector3(0.14, 0.012, 0.012), B.Head, red, RigBuilder.GLOW)
	rb.block(Vector3(0, 1.9, -0.02), Vector3(0.03, 0.08, 0.26), B.Head, cloth, RigBuilder.BODY, Basis.IDENTITY, Vector2(1.0, 0.7))
	# 双手大剑（右手，约 1.4 米）：比单手剑更往下斜（约 75°），走路时剑尖朝前下方，不像端着长枪
	var h: Vector3 = J.RightHand + Vector3(0, -0.07, 0.02)
	var R := Basis(Vector3(1, 0, 0), 1.3)
	rb.block(h + R * Vector3(0, 0, -0.05), Vector3(0.04, 0.04, 0.3), B.RightHand, Color(0.12, 0.08, 0.06), RigBuilder.BODY, R)
	rb.block(h + R * Vector3(0, 0, 0.12), Vector3(0.32, 0.045, 0.05), B.RightHand, dsteel, RigBuilder.METAL, R)
	rb.block(h + R * Vector3(0, 0, 0.72), Vector3(0.1, 0.022, 1.14), B.RightHand, steel.lightened(0.2), RigBuilder.METAL, R, Vector2(0.75, 1.0))
	rb.spike(h + R * Vector3(0, 0, 1.29), h + R * Vector3(0, 0, 1.42), 0.045, B.RightHand, steel.lightened(0.2), RigBuilder.METAL, 4)
	return _finish(rb, J, red, {"scale": 1.15, "stride": 1.5, "walk_ref": 2.4, "arm_swing": 14.0, "idle_arms": 10.0, "hunch": 2.0,
		"carry": {"RightUpperArm": Vector3(-16, 0, -6), "RightLowerArm": Vector3(-30, 0, 0), "LeftUpperArm": Vector3(-6, 0, 6), "LeftLowerArm": Vector3(-20, 0, 0)}})


static func _robed(priest: bool) -> Dictionary:
	var J := joints()
	var B := _idx()
	var rb := RigBuilder.new()
	var robe := Color(0.27, 0.24, 0.24) if priest else Color(0.25, 0.18, 0.31)
	var hood := Color(0.2, 0.18, 0.18) if priest else Color(0.19, 0.14, 0.25)
	var trim := Color(0.45, 0.4, 0.36) if priest else Color(0.42, 0.3, 0.18)
	var skin := Color(0.62, 0.55, 0.5)
	var wood := Color(0.34, 0.24, 0.15)
	var glow := Color(0.69, 0.42, 1.0) if priest else Color(0.62, 0.36, 0.95)
	# 长袍下的腿（大部分被袍子挡住）与宽袖
	_limbs(rb, J, B, {"thigh": robe.darkened(0.3), "shin": robe.darkened(0.4), "foot_col": Color(0.15, 0.12, 0.1), "upper": robe, "fore": robe, "hand_col": skin,
		"thigh_r": 0.07, "shin_r": 0.055, "arm_r": 0.075, "cuff": 1.1, "wrist": 1.7})
	# 钟形长袍：从胸口一直罩到脚踝
	rb.tube([Vector3(0, 1.54, 0), Vector3(0, 1.42, 0), Vector3(0, 1.2, 0.0), Vector3(0, 0.98, 0), Vector3(0, 0.62, 0.01), Vector3(0, 0.3, 0.01), Vector3(0, 0.1, 0.01)],
		[Vector2(0.11, 0.09), Vector2(0.23, 0.14), Vector2(0.2, 0.14), Vector2(0.21, 0.16), Vector2(0.28, 0.23), Vector2(0.34, 0.29), Vector2(0.37, 0.32)],
		[[B.Chest, B.Neck, 0.3], B.Chest, [B.Spine, B.Chest, 0.5], B.Hips, B.Hips, B.Hips, B.Hips], robe, RigBuilder.BODY, 12, true, Vector3.BACK)
	rb.tube([Vector3(0, 0.95, 0), Vector3(0, 1.0, 0)], [Vector2(0.22, 0.17), Vector2(0.22, 0.17)], [B.Hips, B.Hips], trim, RigBuilder.BODY, 10, false, Vector3.BACK)   # 腰绳
	rb.block(Vector3(0, 1.2, 0.15), Vector3(0.06, 0.62, 0.02), [B.Spine, B.Chest, 0.5], trim, RigBuilder.BODY, Basis.IDENTITY, Vector2(1.0, 1.0))        # 前襟饰带
	rb.ellipsoid(Vector3(0, 1.38, 0.155), Vector3(0.035, 0.045, 0.02), B.Chest, glow, RigBuilder.GLOW, Basis.IDENTITY, 3, 6)                              # 胸前护符
	# 兜帽：罩住头，前面开口里是暗影
	rb.limb(Vector3(0, 1.5, 0), Vector3(0, 1.62, 0.01), 0.05, 0.05, B.Neck, skin, B.Head)
	rb.ellipsoid(Vector3(0, 1.74, -0.01), Vector3(0.14, 0.16, 0.15), B.Head, hood, RigBuilder.BODY, Basis(Vector3.RIGHT, deg_to_rad(-10)), 6, 10)
	rb.ellipsoid(Vector3(0, 1.72, 0.09), Vector3(0.095, 0.11, 0.06), B.Head, Color(0.05, 0.04, 0.05))
	rb.ellipsoid(Vector3(0, 1.5, -0.02), Vector3(0.2, 0.08, 0.16), B.Chest, hood)                                                                           # 披肩
	if priest:
		# 骨白面具 + 眼缝
		rb.block(Vector3(0, 1.71, 0.135), Vector3(0.14, 0.18, 0.03), B.Head, Color(0.82, 0.78, 0.7), RigBuilder.BODY, Basis.IDENTITY, Vector2(1.0, 0.8))
		for sx in [1.0, -1.0]:
			rb.block(Vector3(0.035 * sx, 1.745, 0.152), Vector3(0.04, 0.012, 0.01), B.Head, Color(0.08, 0.06, 0.06))
			rb.ellipsoid(Vector3(0.035 * sx, 1.745, 0.155), Vector3(0.01, 0.008, 0.006), B.Head, glow, RigBuilder.GLOW, Basis.IDENTITY, 3, 5)
	else:
		for sx in [1.0, -1.0]:
			rb.ellipsoid(Vector3(0.035 * sx, 1.74, 0.14), Vector3(0.014, 0.012, 0.008), B.Head, glow, RigBuilder.GLOW, Basis.IDENTITY, 3, 5)
	# 右手法杖：杖身、爪形杖头、发光的虚之光
	var h: Vector3 = J.RightHand + Vector3(0, -0.06, 0.01)
	var R := STAFF_TILT
	rb.limb(h + R * Vector3(0, -0.62, 0), h + R * Vector3(0, 1.08, 0), 0.022, 0.026, B.RightHand, wood, -1, RigBuilder.BODY, 6)
	for k in 3:
		var a := TAU * k / 3.0
		rb.spike(h + R * Vector3(0, 1.06, 0), h + R * Vector3(cos(a) * 0.07, 1.26, sin(a) * 0.07), 0.018, B.RightHand, wood.darkened(0.2), RigBuilder.BODY, 4)
	rb.ellipsoid(h + R * Vector3(0, 1.2, 0), Vector3(0.07, 0.07, 0.07), B.RightHand, glow, RigBuilder.GLOW, Basis.IDENTITY, 4, 8)
	return _finish(rb, J, glow, {"scale": 1.08, "stride": 1.1, "walk_ref": 2.2, "arm_swing": 10.0, "idle_arms": 8.0, "hunch": 6.0, "leg_amp": 0.5,
		"carry": {"RightUpperArm": Vector3(-20, 0, -8), "RightLowerArm": Vector3(-43, 0, 0), "LeftUpperArm": Vector3(-14, 0, 4), "LeftLowerArm": Vector3(-50, 0, 0)}})


static func _brute() -> Dictionary:
	var J := joints({"Chest": Vector3(0, 1.32, 0), "Neck": Vector3(0, 1.56, 0.04), "Head": Vector3(0, 1.62, 0.07),
		"LeftUpperArm": Vector3(0.36, 1.48, 0), "LeftLowerArm": Vector3(0.42, 1.15, 0.03), "LeftHand": Vector3(0.44, 0.86, 0.06),
		"LeftUpperLeg": Vector3(0.15, 0.92, 0), "LeftLowerLeg": Vector3(0.17, 0.5, 0.03), "LeftFoot": Vector3(0.17, 0.1, -0.01)})
	var B := _idx()
	var rb := RigBuilder.new()
	var char_c := Color(0.19, 0.16, 0.14)
	var ash := Color(0.32, 0.28, 0.24)
	var horn := Color(0.5, 0.45, 0.4)
	var ember := Color(1.0, 0.45, 0.12)
	_limbs(rb, J, B, {"thigh": char_c, "shin": ash.darkened(0.2), "foot_col": char_c, "upper": char_c, "fore": ash.darkened(0.15), "hand_col": char_c,
		"thigh_r": 0.13, "shin_r": 0.1, "arm_r": 0.13, "hand": 1.7, "foot_s": 1.25})
	# 厚实的躯干：宽胸、驼背
	rb.tube([Vector3(0, 0.84, 0), Vector3(0, 1.0, 0), Vector3(0, 1.16, 0.01), Vector3(0, 1.34, 0.01), Vector3(0, 1.48, -0.02), Vector3(0, 1.58, 0.02)],
		[Vector2(0.24, 0.18), Vector2(0.27, 0.2), Vector2(0.3, 0.22), Vector2(0.38, 0.25), Vector2(0.36, 0.22), Vector2(0.14, 0.12)],
		[B.Hips, B.Hips, [B.Hips, B.Spine, 0.8], [B.Spine, B.Chest, 0.8], B.Chest, [B.Chest, B.Neck, 0.3]], char_c, RigBuilder.BODY, 12, true, Vector3.BACK)
	for sx in [1.0, -1.0]:
		var side := "Left" if sx > 0 else "Right"
		rb.ellipsoid(J[side + "UpperArm"] + Vector3(-0.02 * sx, 0.03, 0), Vector3(0.16, 0.14, 0.15), [B.Chest, B[side + "UpperArm"], 0.5], char_c.lightened(0.05))
	# 余烬裂缝（胸、背、手臂）
	_cracks(rb, Vector3(0, 1.28, 0.2), 7, Vector3(0.5, 0.36, 0.0), B.Chest, ember, 21)
	_cracks(rb, Vector3(0, 1.3, -0.2), 6, Vector3(0.5, 0.4, 0.0), B.Chest, ember, 33)
	_cracks(rb, Vector3(0, 1.02, 0.19), 3, Vector3(0.36, 0.14, 0.0), B.Hips, ember, 41)
	for sx in [1.0, -1.0]:
		var side := "Left" if sx > 0 else "Right"
		_cracks(rb, (J[side + "UpperArm"] as Vector3).lerp(J[side + "LowerArm"], 0.5) + Vector3(0.08 * sx, 0, 0.06), 2, Vector3(0.0, 0.14, 0.05), B[side + "UpperArm"], ember, 50 + int(sx))
	rb.block(Vector3(0, 0.82, 0.12), Vector3(0.3, 0.32, 0.04), [B.Hips, B.LeftUpperLeg, 0.3], Color(0.16, 0.12, 0.1), RigBuilder.BODY, Basis.IDENTITY, Vector2(1.15, 1.0))
	# 小脑袋往前探 + 一对弯角 + 余烬眼
	rb.ellipsoid(Vector3(0, 1.72, 0.12), Vector3(0.14, 0.13, 0.14), B.Head, char_c.lightened(0.04), RigBuilder.BODY, Basis.IDENTITY, 6, 10)
	for sx in [1.0, -1.0]:
		rb.tube([Vector3(0.1 * sx, 1.8, 0.1), Vector3(0.2 * sx, 1.9, 0.12), Vector3(0.25 * sx, 1.98, 0.24), Vector3(0.24 * sx, 1.98, 0.36)],
			[Vector2(0.045, 0.045), Vector2(0.038, 0.038), Vector2(0.026, 0.026), Vector2(0.0, 0.0)], [B.Head, B.Head, B.Head, B.Head], horn, RigBuilder.BODY, 6, true)
		rb.ellipsoid(Vector3(0.05 * sx, 1.73, 0.25), Vector3(0.02, 0.016, 0.01), B.Head, ember, RigBuilder.GLOW, Basis.IDENTITY, 3, 5)
	return _finish(rb, J, ember, {"scale": 1.25, "stride": 1.6, "walk_ref": 3.0, "arm_swing": 20.0, "idle_arms": 16.0, "hunch": 12.0,
		"carry": {"RightUpperArm": Vector3(-14, 0, -6), "LeftUpperArm": Vector3(-14, 0, 6), "RightLowerArm": Vector3(-25, 0, 0), "LeftLowerArm": Vector3(-25, 0, 0)}})
