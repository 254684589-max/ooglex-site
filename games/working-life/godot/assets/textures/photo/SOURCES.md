# 照片材质来源与许可

本目录的贴图由 `games/working-life/tools/bake_photo_textures.gd` 从下列照片加工生成（去色、调亮度 / 对比、
烘焙砖缝、由高度生成法线等，改动见脚本注释）。开发环境无法访问素材站本身，这些文件取自在 GitHub 上
转载它们的开源仓库，许可以原始发布者为准。

| 生成的贴图 | 原始照片 | 原始出处与许可 | 取自 |
|---|---|---|---|
| `asphalt_albedo`、`asphalt_normal`、`roof_albedo`（砾石层）、`grass_albedo`（明暗层）、`dirt_albedo` | Rocky Trail（`rocky_trail_diff_1k.jpg`） | Poly Haven，CC0 1.0 | playcanvas/engine `examples/assets/textures` |
| `asphalt_albedo`（龟裂纹理层） | Rock Boulder Cracked（`rock_boulder_cracked_diff_1k.jpg`） | Poly Haven，CC0 1.0 | playcanvas/engine `examples/assets/textures` |
| `stone_albedo`、`stone_normal` | Bricks 076 A（https://ambientcg.com/view?id=Bricks076A） | ambientCG，CC0 1.0 | playcanvas/engine `examples/assets/textures/bricks076a` |
| `concrete_albedo`、`concrete_normal`、`paving_albedo`、`plaster_detail`、`roof_albedo` | `cement_lossy.webp` | Godot 示例项目 truck_town，MIT（见下） | godotengine/godot-demo-projects `3d/truck_town/town/model/textures` |
| `grass_albedo` | `grass_lossy.webp` | Godot 示例项目 truck_town，MIT（见下） | godotengine/godot-demo-projects `3d/truck_town/town/model/textures` |

## Godot 示例项目的 MIT 许可声明

```
Copyright (c) 2014-present Godot Engine contributors.
Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
