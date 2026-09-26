class_name Layers
extends RefCounted
## 物理碰撞层位值（与 project.godot 的 layer_names 一致）。

const WORLD := 1        # 第 1 层：墙体、柱子等不可穿越的世界几何
const OCCLUDER := 2     # 第 2 层：会挡住视线、需要半透明的物体
const GROUND := 4       # 第 3 层：地面（点击拾取、导航解析）
const PLAYER := 8       # 第 4 层：玩家
const ENEMY := 16       # 第 5 层：敌人
