extends Node
## 章节资源包加载器（TECH.md 第 5.3 节）。
## 网页上：从同源的 packs/<id>.pck 下载到 user://packs/，再用 ProjectSettings.load_resource_pack() 挂载。
## 桌面 / 无头测试：直接传入本地 .pck 路径。
## 结果通过 pack_loaded 信号返回（成功与否、耗时毫秒、说明）。

signal pack_loaded(id: String, ok: bool, ms: int, detail: String)

var loaded: Dictionary = {}


func pack_url(id: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var base = JavaScriptBridge.eval("new URL('packs/', window.location.href).href", true)
	return str(base) + id + ".pck"


func load_chapter(id: String, local_path: String = "") -> void:
	var t0 := Time.get_ticks_msec()
	if loaded.has(id):
		pack_loaded.emit(id, true, 0, "已加载")
		return
	var path := local_path
	if path == "":
		var url := pack_url(id)
		if url == "":
			pack_loaded.emit(id, false, 0, "不是网页环境，也没有给出本地路径")
			return
		var req := HTTPRequest.new()
		add_child(req)
		var err := req.request(url)
		if err != OK:
			req.queue_free()
			pack_loaded.emit(id, false, Time.get_ticks_msec() - t0, "请求发起失败：%d" % err)
			return
		var res: Array = await req.request_completed
		req.queue_free()
		if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
			pack_loaded.emit(id, false, Time.get_ticks_msec() - t0, "下载失败：result=%d HTTP %d" % [res[0], res[1]])
			return
		DirAccess.make_dir_recursive_absolute("user://packs")
		path = "user://packs/%s.pck" % id
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			pack_loaded.emit(id, false, Time.get_ticks_msec() - t0, "写入 user:// 失败")
			return
		f.store_buffer(res[3])
		f.close()
	# replace_files = false：章节包只增加新资源，不覆盖主包里的同名文件
	var ok := ProjectSettings.load_resource_pack(path, false)
	if ok:
		loaded[id] = path
	pack_loaded.emit(id, ok, Time.get_ticks_msec() - t0, path)
