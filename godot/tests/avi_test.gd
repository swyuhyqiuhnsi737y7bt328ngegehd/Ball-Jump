extends SceneTree

## AVI 结构自检：递归遍历 chunk 树
## 之前那个版本只找 movi/00dc/idx1，结果漏掉了 LIST('hdrl' 'hdrl' ...) 这种
## 「多包了一层」的错误 —— 文件看着没问题，VLC / ffmpeg 直接拒绝。

var fails := 0
var data := PackedByteArray()

func _initialize() -> void:
	print("=== AVI 写入器自检 ===")
	var w := AviWriter.new(64, 48, 30, 0.8)
	for i in 6:
		var img := Image.create_empty(64, 48, false, Image.FORMAT_RGB8)
		img.fill(Color(0.05, 0.08, 0.16))
		for y in 48:
			for x in 64:
				if x >= i * 8 and x < i * 8 + 10 and y >= 16 and y < 32:
					img.set_pixel(x, y, Color(1, 0.84, 0.37))
		w.add_image(img)
	var path := "user://avi_selftest.avi"
	check("写出成功", w.save_to(path), true)
	data = FileAccess.get_file_as_bytes(path)
	print("  文件大小 %.1f KB" % (data.size() / 1024.0))

	check("RIFF 头", _str(0, 4), "RIFF")
	check("form 类型", _str(8, 4), "AVI ")
	check("RIFF 长度 = 文件长-8", _u32(4) + 8, data.size())

	# 递归遍历顶层
	var top := _walk(12, data.size(), 0)
	check("顶层块数（hdrl/movi/idx1）", top.size(), 3)
	if top.size() == 3:
		check("顶层顺序", ",".join([str(top[0]["id"]), str(top[1]["id"]), str(top[2]["id"])]), "LIST,LIST,idx1")
		# hdrl
		var hdrl: Dictionary = top[0]
		check("hdrl 的 kind", hdrl.get("kind", ""), "hdrl")
		var hk: Array = hdrl.get("kids", [])
		check("hdrl 直接子块数（avih + LIST strl）", hk.size(), 2)
		if hk.size() == 2:
			check("hdrl 第一个子块是 avih", hk[0]["id"], "avih")
			check("avih 长度", hk[0]["size"], 56)
			check("hdrl 第二个子块是 LIST strl", hk[1].get("kind", ""), "strl")
			var sk: Array = hk[1].get("kids", [])
			check("strl 子块数", sk.size(), 2)
			if sk.size() == 2:
				check("strl[0] = strh(56)", sk[0]["id"] + "/" + str(sk[0]["size"]), "strh/56")
				check("strl[1] = strf(40)", sk[1]["id"] + "/" + str(sk[1]["size"]), "strf/40")
		# movi
		var movi: Dictionary = top[1]
		check("movi 的 kind", movi.get("kind", ""), "movi")
		var mk: Array = movi.get("kids", [])
		check("movi 里的帧数", mk.size(), 6)
		var all_dc := true
		for k in mk:
			if k["id"] != "00dc":
				all_dc = false
		check("movi 里全是 00dc", all_dc, true)
		# idx1
		check("idx1 长度 = 16 字节 x 帧数", top[2]["size"], 16 * 6)

	# 关键：索引里的偏移必须真的指到对应的帧
	var idx_ok := true
	if top.size() == 3:
		var movi_start: int = top[1]["pos"]      # 'LIST' 的位置
		for i in 6:
			var off := _u32(top[2]["pos"] + 8 + i * 16 + 8)
			var at := movi_start + 8 + off       # movi 数据从 kind 之后开始
			if _str(at, 4) != "00dc":
				idx_ok = false
	check("idx1 偏移都指向真实的 00dc", idx_ok, true)

	check("空写入器拒绝写出", AviWriter.new().save_to("user://nope.avi"), false)
	print("")
	print("失败 %d 项 ❌" % fails if fails > 0 else "AVI 写入器自检全部通过 ✅")
	quit()

func _str(off: int, n: int) -> String:
	return data.slice(off, off + n).get_string_from_ascii()

func _u32(off: int) -> int:
	return data.decode_u32(off)

## 遍历 [start, end) 里的 chunk，遇到 LIST 递归；任何越界的长度都记下来
func _walk(start: int, end: int, depth: int) -> Array:
	var out: Array = []
	var pos := start
	while pos + 8 <= end:
		var id := _str(pos, 4)
		var sz := _u32(pos + 4)
		var body := pos + 8
		if sz < 0 or body + sz > end:
			fails += 1
			print("  ❌ 块 %s 声明长度 %d，超出父块（父块还剩 %d）" % [id, sz, end - body])
			return out
		var node := {"id": id, "size": sz, "pos": pos}
		if id == "LIST":
			node["kind"] = _str(body, 4)
			node["kids"] = _walk(body + 4, body + sz, depth + 1)
		out.append(node)
		pos = body + sz + (sz % 2)
	if pos != end:
		print("  注意：遍历结束位置 %d != 父块结束 %d（可能有填充差异）" % [pos, end])
	return out

func check(name: String, got, want) -> void:
	var ok := str(got) == str(want)
	if ok:
		print("  ✅ %-34s %s" % [name, str(got)])
	else:
		fails += 1
		print("  ❌ %-34s 得到 %s，期望 %s" % [name, str(got), str(want)])
