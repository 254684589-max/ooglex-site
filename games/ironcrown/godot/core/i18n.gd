class_name I18n
extends RefCounted
## 中英文切换（2026-11-08 所有者「加入中英文切换」）。做法：游戏里的字照旧用中文写；data/i18n/en.json 是「中文原句 → 英文」的对照表，
## 启动时装进 TranslationServer（locale = en）。切到英文时：
##   · 界面上的 Label / Button 的字是对照表里的原句 —— Godot 自己换成英文（自动翻译）；
##   · 拼出来的句子（带 %s / %d 的）—— 代码里先 I18n.t(原句) 再填数，对照表里存的是带占位符的原句；
##   · 对话、任务、物品这些数据 —— 显示的地方 I18n.t()。
## 对照表里没有的句子照旧显示中文（不会出空白）。tools/i18n_report.py 列出哪些还没翻。
## 英文表只在英文时挂入；中文时改挂显示还原表，已格式化的旧英文也能即时切回中文。
## （不改 project.godot 的回退语言：一加 [internationalization] 设置，导出时每个包都多带 4.8 MB 的 ICU 数据，实测。）

const LANGS := ["zh", "en"]
const TABLE := "res://data/i18n/en.json"

static var _loaded := false
static var _map := {}
static var _tr: Translation
static var _on := false
static var _zh_tr: Translation
static var _reverse := {}
static var _pieces := [{}, {}]
static var _templates: Array = [[], []]
static var _cache: Array = [{}, {}]
static var _format_re := RegEx.create_from_string("%[-+0 #0-9.]*[sdiouxXfFeEgGc%]")


## 在 Godot 的显示边界翻译；不改对话数据、交互对象名或用于找任务目标的中文。
## 中文表只将已格式化的英文显示串还原，解决切换时保留在 Label 中的英文。
class DisplayTranslation extends Translation:
	var reverse := false

	func _get_message(src_message: StringName, _context: StringName) -> StringName:
		return StringName(I18n.render(str(src_message), reverse))


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
	var tr := DisplayTranslation.new()
	_tr = tr
	tr.locale = "en"
	for k in d:
		if str(k).begins_with("_"):
			continue
		var v := str(d[k])
		if v != "":
			tr.add_message(str(k), v)
			_map[str(k)] = v
			if not _reverse.has(v):
				_reverse[v] = str(k)
	_zh_tr = DisplayTranslation.new()
	_zh_tr.reverse = true
	_zh_tr.locale = "zh"
	_build_display_index(_map, 0)
	_build_display_index(_reverse, 1)


static func apply(lang: String) -> void:
	setup()
	var want := lang == "en"
	if _tr:
		TranslationServer.remove_translation(_tr)
		TranslationServer.remove_translation(_zh_tr)
		TranslationServer.add_translation(_tr if want else _zh_tr)
	_on = want
	TranslationServer.set_locale("en" if want else "zh")


static func en() -> bool:
	return _on


## 照对照表翻；没有的、或者现在是中文，原样返回
static func t(s: String) -> String:
	if not en():
		return s
	return str(_map.get(s, s))


## 有没有这一句的英文（测试、报表用）
static func has(s: String) -> bool:
	setup()
	return _map.has(s)


## 精确原句优先；然后识别已经填入参数的模板；最后翻译拼接的完整片段。
## 索引按首字符分组，避免每次显示遍历全部词表；数字不断变化时缓存最多 2048 项。
static func _build_display_index(table: Dictionary, direction: int) -> void:
	var keys := table.keys()
	keys.sort_custom(func(a, b): return str(a).length() > str(b).length())
	for key: String in keys:
		if key == "":
			continue
		var matches := _format_re.search_all(key)
		if not matches.is_empty():
			var pattern := "^"
			var at := 0
			var count := 0
			for m: RegExMatch in matches:
				pattern += _regex_escape(key.substr(at, m.get_start() - at))
				var token := m.get_string()
				if token == "%%":
					pattern += "%"
				else:
					pattern += "(.*?)" if token.ends_with("s") else "([-+0-9.eE]+)"
					count += 1
				at = m.get_end()
			pattern += _regex_escape(key.substr(at)) + "$"
			if count > 0 and _format_re.sub(key, "", true).strip_edges().length() >= 2:
				var re := RegEx.new()
				if re.compile(pattern) == OK:
					_templates[direction].append({"regex": re, "value": table[key]})
			continue
		var first := key[0]
		if not _pieces[direction].has(first):
			_pieces[direction][first] = []
		_pieces[direction][first].append(key)


static func _regex_escape(s: String) -> String:
	var out := ""
	for c in s:
		if c in "\\.^$|?*+()[]{}":
			out += "\\"
		out += c
	return out


static func render(s: String, reverse := false, depth := 0) -> String:
	var table: Dictionary = _reverse if reverse else _map
	if table.has(s):
		return str(table[s])
	if s == "" or depth > 6:
		return s
	var direction := 1 if reverse else 0
	if _cache[direction].has(s):
		return _cache[direction][s]
	for entry: Dictionary in _templates[direction]:
		var found: RegExMatch = entry.regex.search(s)
		if found:
			var translated: String = entry.value
			var result := ""
			var at := 0
			var group := 1
			for token: RegExMatch in _format_re.search_all(translated):
				result += translated.substr(at, token.get_start() - at)
				if token.get_string() == "%%":
					result += "%"
				else:
					result += render(found.get_string(group), reverse, depth + 1)
					group += 1
				at = token.get_end()
			result += translated.substr(at)
			return _remember(s, result, direction)
	var result := ""
	var i := 0
	while i < s.length():
		var matched := false
		for key: String in _pieces[direction].get(s[i], []):
			if s.substr(i, key.length()) != key:
				continue
			# 英文片段只匹配词边界，避免把 longer 中的 long 拆出来。
			if reverse and ((i > 0 and _latin(s[i - 1]) and _latin(key[0])) or (i + key.length() < s.length() and _latin(s[i + key.length()]) and _latin(key[-1]))):
				continue
			result += str(table[key])
			i += key.length()
			matched = true
			break
		if not matched:
			result += s[i]
			i += 1
	return _remember(s, result, direction)


static func _latin(c: String) -> bool:
	return (c >= "A" and c <= "Z") or (c >= "a" and c <= "z")


static func _remember(source: String, result: String, direction: int) -> String:
	if _cache[direction].size() >= 2048:
		_cache[direction].clear()
	_cache[direction][source] = result
	return result
