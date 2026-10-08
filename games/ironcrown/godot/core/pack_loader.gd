class_name PackLoader
extends Node
## 章节资源包的下载与挂载（路线图 4.1；TECH.md 第六节）。
## 复制自 games/emberfall3d/godot/core/pack_loader.gd（《余烬陷落》1.1：网页上 HTTPRequest 下载 → 写进 user:// →
## ProjectSettings.load_resource_pack，三个宽度实测可行），改了四处：
##   1. 包名带内容哈希：stamp_web_build.py 把「编号 → packs/ic-ch1-<哈希>.pck 和大小」写进页面的 window.IC_PACKS；
##      包一变名字就变，回访的玩家不会拿到旧包（《余烬陷落》是固定的 packs/<编号>.pck）。
##   2. 下载过的包留在 user://packs/（浏览器本地存储），下次直接挂载、不再下载；同一章旧版本的包顺手删掉。
##   3. 内容已经在（编辑器、桌面、无头测试里章节内容本来就在 res://；或者这次已经挂载过）就不下载。
##   4. 下载进度（progress 信号）与中文的失败说明，给 PackPanel 显示。
## 线上 CDN 用 gzip 传输 .pck 时，浏览器交给引擎的已经是解压后的数据，响应头却还带 Content-Encoding: gzip：
## 网页上不让 HTTPRequest 再解压一次（accept_gzip = false），否则报 RESULT_BODY_DECOMPRESS_FAILED（《余烬陷落》1.1 踩过）。

signal progress(id: String, done: int, total: int)

const DIR := "user://packs/"
const TIMEOUT := 120.0            # 秒：手机网络慢，章节包几 MB 到十几 MB

var mounted := {}                 # 编号 → 挂载的文件路径
var busy := ""                    # 正在下载的编号
var busy_total := 0               # 这个包有多大（页面上登记的，字节；0 = 不知道）
var req: HTTPRequest


## 页面上登记的包：{"path": "packs/ic-ch1-xxxxxxxx.pck", "size": 字节数}；没有登记（本地导出没跑 stamp）就按 packs/<编号>.pck 找
func entry_of(id: String) -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var raw := str(JavaScriptBridge.eval("JSON.stringify((window.IC_PACKS||{})[%s]||null)" % JSON.stringify(id), true))
	var e = JSON.parse_string(raw) if raw not in ["", "null"] else null
	if typeof(e) == TYPE_DICTIONARY and e.has("path"):
		return e
	return {"path": "packs/%s.pck" % id, "size": 0}


func url_of(id: String) -> String:
	var e := entry_of(id)
	if e.is_empty():
		return ""
	return str(JavaScriptBridge.eval("new URL(%s, window.location.href).href" % JSON.stringify(str(e.path)), true))


## 这个章节包的内容到了没有
func has_pack(id: String) -> bool:
	if id == "" or mounted.has(id):
		return true
	var probe := Chapters.probe_for_pack(id)
	return probe != "" and ResourceLoader.exists(probe)


## 确保章节包到了。返回 {ok, detail, ms, from}：from = present（本来就在）/ cache（用了上次下载的）/ download（这次下载的）
func ensure(id: String) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	if has_pack(id):
		return _done(id, true, "已经在了", t0, "present")
	if busy != "":
		return _done(id, false, "正在下载别的章节，请稍等", t0, "")
	if not OS.has_feature("web"):
		return _done(id, false, "这一章的内容不在这个版本里", t0, "")
	var url := url_of(id)
	var file := DIR + url.get_file().get_slice("?", 0)
	if FileAccess.file_exists(file):
		if _mount(id, file):
			return _done(id, true, file, t0, "cache")
		DirAccess.remove_absolute(file)           # 存着的那份坏了：删掉重新下载
	busy = id
	busy_total = int(entry_of(id).get("size", 0))
	var r := await _download(url)
	busy = ""
	if not r.ok:
		return _done(id, false, str(r.detail), t0, "")
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f == null:
		return _done(id, false, "下载好了，但浏览器不让存（存储空间不够或隐私模式）", t0, "")
	f.store_buffer(r.body)
	f.close()
	_prune(id, file.get_file())
	if not _mount(id, file):
		DirAccess.remove_absolute(file)
		return _done(id, false, "下载的章节包打不开，请重试", t0, "")
	return _done(id, true, file, t0, "download")


func _done(id: String, ok: bool, detail: String, t0: int, from: String) -> Dictionary:
	var r := {"ok": ok, "detail": detail, "ms": Time.get_ticks_msec() - t0, "from": from}
	print("IC_PACK id=%s ok=%s from=%s ms=%d %s" % [id, ok, from, r.ms, detail])
	return r


## replace_files = false：章节包只增加新资源，不覆盖主包里的同名文件。挂上以后再看一眼探针资源，确认是这一章的包
func _mount(id: String, path: String) -> bool:
	if not ProjectSettings.load_resource_pack(path, false):
		return false
	var probe := Chapters.probe_for_pack(id)
	if probe != "" and not ResourceLoader.exists(probe):
		return false
	mounted[id] = path
	return true


func _download(url: String) -> Dictionary:
	req = HTTPRequest.new()
	req.accept_gzip = not OS.has_feature("web")
	req.timeout = TIMEOUT
	add_child(req)
	var err := req.request(url)
	if err != OK:
		req.queue_free()
		req = null
		return {"ok": false, "detail": "下载没能开始（错误 %d）" % err}
	var res: Array = await req.request_completed
	req.queue_free()
	req = null
	if res[0] == HTTPRequest.RESULT_TIMEOUT:
		return {"ok": false, "detail": "网络太慢，下载超时了"}
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "detail": "网络出错了（%d），请检查网络后重试" % res[0]}
	if res[1] != 200:
		return {"ok": false, "detail": "服务器没给这一章（HTTP %d）" % res[1]}
	return {"ok": true, "body": res[3]}


## 同一章旧版本的包（文件名前缀相同、哈希不同）删掉，不占浏览器的存储
func _prune(id: String, keep: String) -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		if f != keep and (f.begins_with("ic-%s-" % id) or f == "%s.pck" % id):
			d.remove(f)


func _process(_delta: float) -> void:
	if busy != "" and req != null:
		progress.emit(busy, req.get_downloaded_bytes(), busy_total if busy_total > 0 else req.get_body_size())
