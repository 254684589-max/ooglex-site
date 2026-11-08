class_name I18n
extends RefCounted
## 中英文切换（2026-11-08 所有者「加入中英文切换」）。做法：游戏里的字照旧用中文写；data/i18n/en.json 是「中文原句 → 英文」的对照表，
## 启动时装进 TranslationServer（locale = en）。切到英文时：
##   · 界面上的 Label / Button 的字是对照表里的原句 —— Godot 自己换成英文（自动翻译）；
##   · 拼出来的句子（带 %s / %d 的）—— 代码里先 I18n.t(原句) 再填数，对照表里存的是带占位符的原句；
##   · 对话、任务、物品这些数据 —— 显示的地方 I18n.t()。
## 对照表里没有的句子照旧显示中文（不会出空白）。tools/i18n_report.py 列出哪些还没翻。
## 回退语言设成 zh（project.godot internationalization/locale/fallback），不然中文界面也会被英文对照表换掉。

const LANGS := ["zh", "en"]
const TABLE := "res://data/i18n/en.json"

static var _loaded := false
static var _map := {}


static func setup() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(TABLE, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		push_warning("i18n：对照表读不出来")
		return
	var tr := Translation.new()
	tr.locale = "en"
	for k in d:
		if str(k).begins_with("_"):
			continue
		var v := str(d[k])
		if v != "":
			tr.add_message(str(k), v)
			_map[str(k)] = v
	TranslationServer.add_translation(tr)


static func apply(lang: String) -> void:
	setup()
	TranslationServer.set_locale("en" if lang == "en" else "zh")


static func en() -> bool:
	return TranslationServer.get_locale().begins_with("en")


## 照对照表翻；没有的、或者现在是中文，原样返回
static func t(s: String) -> String:
	if not en():
		return s
	return str(_map.get(s, s))


## 有没有这一句的英文（测试、报表用）
static func has(s: String) -> bool:
	setup()
	return _map.has(s)
