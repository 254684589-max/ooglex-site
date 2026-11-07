class_name HorseKit
## 一匹马（2026-11-07 所有者「马匹也是，方块化，不真实」）：原来塞弗林营地的四匹马是几根 6–10 边的圆台、渡口马棚那匹是几个方块拼的。
## 换成同一套更像马的搭法——一节一节接起来的圆身子（臀高、腰细、胸深）、往上拱的脖子、额头宽口鼻窄的头和两只耳朵、
## 每条腿分大腿 / 前臂、膝（飞节）、管骨、球节、系部、蹄子，前腿直、后腿带弯；一条往下垂、末端散开的尾巴；脖子上沿一条鬃毛。
## 本地坐标：-Z 是马头，+Y 朝上，原点在四条腿中间的地面上。材质键：coat（毛色）、mane（鬃尾、蹄子）；cloth = true 时披马衣（red / gold）。

const SIDES := 16


static func build(kit: MeshKit, o: Vector3, b: Basis, coat: String, grazing := false, cloth := false) -> void:
	var P := func(x: float, y: float, z: float) -> Vector3: return o + b * Vector3(x, y, z)
	# 身子：从尾根到胸前一节一节接（z, y, 半径）
	var body := [[0.95, 1.27, 0.1], [0.86, 1.32, 0.24], [0.66, 1.3, 0.32], [0.38, 1.24, 0.33], [0.05, 1.2, 0.33], [-0.3, 1.22, 0.35], [-0.58, 1.26, 0.33], [-0.78, 1.22, 0.27], [-0.9, 1.15, 0.16]]
	for i in body.size() - 1:
		var a: Array = body[i]
		var c: Array = body[i + 1]
		kit.tube(coat, P.call(0, a[1], a[0]), P.call(0, c[1], c[0]), a[2], c[2], SIDES)
	# 脖子和头：吃草的把头低到地上
	var neck := [[0.0, 1.42, -0.7, 0.24], [0.0, 1.62, -0.92, 0.19], [0.0, 1.8, -1.08, 0.15], [0.0, 1.9, -1.18, 0.12]]
	var head := [[0.0, 1.9, -1.2, 0.12], [0.0, 1.72, -1.4, 0.1], [0.0, 1.52, -1.55, 0.08], [0.0, 1.44, -1.6, 0.065]]
	if grazing:
		neck = [[0.0, 1.38, -0.72, 0.24], [0.0, 1.18, -0.98, 0.19], [0.0, 0.9, -1.2, 0.15], [0.0, 0.62, -1.34, 0.12]]
		head = [[0.0, 0.62, -1.36, 0.12], [0.0, 0.4, -1.46, 0.1], [0.0, 0.2, -1.52, 0.08], [0.0, 0.12, -1.54, 0.065]]
	for seq in [neck, head]:
		for i in seq.size() - 1:
			var a: Array = seq[i]
			var c: Array = seq[i + 1]
			kit.tube(coat, P.call(a[0], a[1], a[2]), P.call(c[0], c[1], c[2]), a[3], c[3], SIDES - 4)
	var poll: Array = head[0]
	var muzzle: Array = head[head.size() - 1]
	kit.tube("mane", P.call(0, muzzle[1], muzzle[2]), P.call(0, muzzle[1] - 0.02, muzzle[2] - 0.035), 0.06, 0.045, 10)      # 口鼻：颜色深一点
	for s in [-1.0, 1.0]:                                                                                                   # 耳朵：两只竖着的小尖
		var e0: Vector3 = P.call(s * 0.06, poll[1] + 0.06, poll[2] + 0.03)
		kit.tube(coat, e0, e0 + b * Vector3(s * 0.03, 0.16, 0.03), 0.035, 0.008, 6)
	for i in neck.size() - 1:                                                                                              # 鬃毛：沿脖子上沿
		var a: Array = neck[i]
		var c: Array = neck[i + 1]
		var up_a: Vector3 = b * Vector3(0, a[3] * 0.85, a[3] * 0.4)
		var up_c: Vector3 = b * Vector3(0, c[3] * 0.85, c[3] * 0.4)
		kit.tube("mane", P.call(0, a[1], a[2]) + up_a, P.call(0, c[1], c[2]) + up_c, 0.045, 0.04, 6)
	# 腿：[x, z, 前腿?]
	for sx in [-0.16, 0.16]:
		for front in [true, false]:
			var z := -0.6 if front else 0.62
			var pts: Array
			if front:     # 肩 → 肘 → 膝 → 球节 → 系部 → 蹄（前腿直）
				pts = [[1.22, z, 0.13], [0.95, z + 0.02, 0.1], [0.56, z, 0.06], [0.2, z - 0.01, 0.045], [0.1, z - 0.05, 0.05], [0.0, z - 0.06, 0.06]]
			else:         # 髋 → 膝（往前）→ 飞节（往后）→ 球节 → 系部 → 蹄
				pts = [[1.24, z, 0.16], [0.9, z - 0.12, 0.12], [0.56, z + 0.1, 0.06], [0.2, z + 0.04, 0.045], [0.1, z, 0.05], [0.0, z - 0.01, 0.06]]
			for i in pts.size() - 1:
				var a: Array = pts[i]
				var c: Array = pts[i + 1]
				var key := "mane" if i == pts.size() - 2 else coat
				kit.tube(key, P.call(sx, a[0], a[1]), P.call(sx, c[0], c[1]), a[2], c[2], 12 if i < 2 else 10)
	# 尾巴：从尾根往下垂，末端散开
	var tail := [[1.3, 0.95, 0.045], [1.12, 1.04, 0.055], [0.88, 1.09, 0.065], [0.62, 1.1, 0.06], [0.48, 1.08, 0.02]]
	for i in tail.size() - 1:
		var a: Array = tail[i]
		var c: Array = tail[i + 1]
		kit.tube("mane", P.call(0, a[0], a[1]), P.call(0, c[0], c[1]), a[2], c[2], 10)
	if cloth:      # 马衣：搭在背上、两边垂下来，金边
		for s in [-1.0, 1.0]:
			var n := (b * Vector3(s, 0.6, 0)).normalized()
			kit.quad("red", [P.call(s * 0.06, 1.57, -0.45), P.call(s * 0.06, 1.56, 0.5), P.call(s * 0.37, 0.95, 0.52), P.call(s * 0.38, 0.97, -0.46)], n, [1.0, 1.0, 0.7, 0.7])
			kit.quad("gold", [P.call(s * 0.38, 0.97, -0.46), P.call(s * 0.37, 0.95, 0.52), P.call(s * 0.38, 0.89, 0.52), P.call(s * 0.39, 0.91, -0.46)], b * Vector3(s, 0, 0))
