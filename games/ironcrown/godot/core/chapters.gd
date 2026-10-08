class_name Chapters
extends RefCounted
## 章节（路线图 4.1；STORY.md 第一节、第四节；TECH.md 第六节）：第几章、叫什么、内容在哪个章节资源包里、从哪儿开始。
## 序章（0）在主包里；第一章起每章一个章节资源包，进那一章（或读那一章的存档）时才下载，首次加载不变大。
## 章节包只放场景与资源，脚本一律留在主包（《余烬陷落》1.1 实测：包里的脚本 UID 不在主包的表里，加载时报警告）。
## probe：章节包里一定有的一个资源——它在 res:// 里能找到，就说明这一章的内容已经在了（编辑器 / 无头测试里本来就在；网页上挂载了包才在）。

## 做到第几章能玩了：第一章的开场（4.3）做好以前是 0，序章结束画面不出「继续：第一章」（main.playable_chapter 可在测试和 ?preview=1 里改）
const PLAYABLE := 0
const LIST := {
	0: {"name": "序章 · 霜渡镇之夜", "pack": "", "probe": "", "area": "frostford", "spawn": "manor"},
	1: {"name": "第一章 · 黑鹭堡", "pack": "ch1", "probe": "res://chapters/ch1/road_sign.tscn", "area": "frostford", "spawn": "manor"},
}


static func known(n: int) -> bool:
	return LIST.has(n)


static func name_of(n: int) -> String:
	return str(LIST.get(n, {}).get("name", ""))


## 这一章的章节包编号（"" = 在主包里）
static func pack_of(n: int) -> String:
	return str(LIST.get(n, {}).get("pack", ""))


static func probe_of(n: int) -> String:
	return str(LIST.get(n, {}).get("probe", ""))


## 章节包编号 → 用来判断「到没到」的资源
static func probe_for_pack(id: String) -> String:
	for n in LIST:
		if str(LIST[n].pack) == id:
			return str(LIST[n].probe)
	return ""


## 这一章的内容在不在（主包里的章节总在）
static func content_ready(n: int) -> bool:
	var p := probe_of(n)
	return p == "" or ResourceLoader.exists(p)
