class_name GroundItem
extends Node3D
## 地上的掉落物（P5，对应 V0.1 dropItemAt / drawGroundItem / pickUp）：金币、药水、装备。
## 头顶一直显示名字（颜色 = 品质，V0.1：普通白、魔法蓝、稀有金、传奇橙）；点它（点名字或物品本身）走过去拾取。
## 外观是占位几何体。

const RARITY_COLORS := [Color(0.91, 0.89, 0.84), Color(0.49, 0.55, 1.0), Color(0.95, 0.83, 0.29), Color(0.91, 0.52, 0.23)]
const GOLD_COLOR := Color(0.79, 0.64, 0.35)
const POT_NAMES := {"hp": "生命药水", "mp": "法力药水", "tp": "回城卷轴"}
const POT_COLORS := {"hp": Color(0.9, 0.2, 0.15), "mp": Color(0.25, 0.4, 1.0), "tp": Color(0.5, 0.85, 1.0)}
const PICK_RANGE := 1.3

var data: Dictionary            # {gold: n} / {pot: "hp"} / {item: 物品字典}
var label: Label3D
var _t := 0.0
var _gem: Node3D


static func make(d: Dictionary) -> GroundItem:
	var g := GroundItem.new()
	g.data = d
	return g


func title() -> String:
	if data.has("gold"):
		return "%d 金币" % data.gold
	if data.has("pot"):
		return POT_NAMES.get(data.pot, "药水")
	return data.item.name


func color() -> Color:
	if data.has("gold"):
		return GOLD_COLOR
	if data.has("pot"):
		return Color(0.91, 0.86, 0.78)
	return RARITY_COLORS[int(data.item.rarity)]


func _ready() -> void:
	add_to_group("ground_item")
	_t = randf() * 6.0
	_gem = Node3D.new()
	add_child(_gem)
	if data.has("gold"):
		for i in 3:
			var c := MeshInstance3D.new()
			c.mesh = LowPoly.cylinder(0.12, 0.12, 0.04)
			c.material_override = _mat(Color(0.95, 0.78, 0.3), 0.6)
			c.position = Vector3((i - 1) * 0.12, 0.03 + i * 0.04, 0)
			_gem.add_child(c)
	elif data.has("pot"):
		var b := MeshInstance3D.new()
		b.mesh = LowPoly.sphere(0.13)
		b.material_override = _mat(POT_COLORS.get(data.pot, Color.WHITE), 1.2)
		b.position.y = 0.14
		_gem.add_child(b)
	else:
		var r := int(data.item.rarity)
		var g := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 0.22, 0.22)
		g.mesh = bm
		g.rotation_degrees = Vector3(45, 0, 45)
		g.material_override = _mat(RARITY_COLORS[r], 0.4 + r * 0.8)
		g.position.y = 0.35
		_gem.add_child(g)
		if r >= 2:
			# 稀有 / 传奇：一道竖直光柱，远处也看得见
			var beam := MeshInstance3D.new()
			beam.mesh = LowPoly.cylinder(0.05, 0.05, 2.4)
			var bmat := _mat(RARITY_COLORS[r], 2.0)
			bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			bmat.albedo_color.a = 0.35
			beam.material_override = bmat
			beam.position.y = 1.2
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(beam)
	label = Label3D.new()
	label.text = title()
	label.modulate = color()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.001
	label.font_size = 30
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.position.y = 0.8
	add_child(label)


func _mat(c: Color, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = glow
	return m


func _process(delta: float) -> void:
	_t += delta
	_gem.rotation.y = _t * 1.6
