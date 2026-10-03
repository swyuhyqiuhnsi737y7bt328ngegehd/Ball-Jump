extends SceneTree

var fails := 0

func _initialize() -> void:
	print("=== AVI 写入器自检 ===")
	var w := AviWriter.new(320, 180, 30, 0.85)
	# 造 8 张会动的图
	for i in 8:
		var img := Image.create_empty(320, 180, false, Image.FORMAT_RGB8)
		img.fill(Color(0.06, 0.09, 0.18))
		for y in 180:
			for x in 320:
				if x >= i * 30 and x < i * 30 + 40 and y >= 60 and y < 120:
					img.set_pixel(x, y, Color(1, 0.84, 0.37))
		w.add_image(img)
	check("收下 8 帧", w.frame_count(), 8)
	var path := "user://avi_selftest.avi"
	var ok := w.save_to(path)
	check("写出成功", ok, true)
	if not ok:
		print("  error=", w.error)
		quit()
		return

	var f := FileAccess.open(path, FileAccess.READ)
	var data := f.get_buffer(f.get_length())
	f.close()
	print("  文件大小 %.1f KB" % (data.size() / 1024.0))
	check("RIFF 头", data.slice(0, 4).get_string_from_ascii(), "RIFF")
	check("类型 AVI ", data.slice(8, 12).get_string_from_ascii(), "AVI ")
	check("RIFF 长度字段 = 文件长度-8", data.decode_u32(4) + 8, data.size())

	# 遍历 chunk 找 movi / idx1
	var pos := 12
	var frames := 0
	var has_idx := false
	var first_jpg := PackedByteArray()
	while pos + 8 <= data.size():
		var cid := data.slice(pos, pos + 4).get_string_from_ascii()
		var csz := data.decode_u32(pos + 4)
		if cid == "LIST":
			var kind := data.slice(pos + 8, pos + 12).get_string_from_ascii()
			if kind == "movi":
				# 走一遍 movi 里的帧
				var p := pos + 12
				var end := pos + 8 + csz
				while p + 8 <= end:
					var fid := data.slice(p, p + 4).get_string_from_ascii()
					var fsz := data.decode_u32(p + 4)
					if fid == "00dc":
						if frames == 0:
							first_jpg = data.slice(p + 8, p + 8 + fsz)
						frames += 1
					p += 8 + fsz + (fsz % 2)
			pos += 8 + csz + (csz % 2)
		elif cid == "idx1":
			has_idx = true
			pos += 8 + csz
		else:
			pos += 8 + csz + (csz % 2)
	check("movi 里有 8 个 00dc 帧", frames, 8)
	check("有 idx1 索引", has_idx, true)

	# 把第一帧 JPEG 解回来，确认是真 JPEG
	var img2 := Image.new()
	var err := img2.load_jpg_from_buffer(first_jpg)
	check("第一帧能解码", err, OK)
	if err == OK:
		check("解码尺寸正确", str(img2.get_size()), "(320, 180)")
		var px := img2.get_pixel(30, 90)
		print("  第一帧方块处颜色 = (%.2f, %.2f, %.2f)" % [px.r, px.g, px.b])
		check("像素内容对得上（金色方块）", px.r > 0.8 and px.b < 0.6, true)

	# 空写入器要报错而不是崩
	var empty := AviWriter.new()
	check("没有帧时拒绝写出", empty.save_to("user://nope.avi"), false)

	print("")
	print("失败 %d 项 ❌" % fails if fails > 0 else "AVI 写入器自检全部通过 ✅")
	quit()

func check(name: String, got, want) -> void:
	var ok := str(got) == str(want)
	if ok:
		print("  ✅ %-28s %s" % [name, str(got)])
	else:
		fails += 1
		print("  ❌ %-28s 得到 %s，期望 %s" % [name, str(got), str(want)])
