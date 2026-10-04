extends SceneTree

var fails := 0

func _initialize() -> void:
	print("=== GIF 写入器自检 ===")
	var w := GifWriter.new(200, 120, 12)
	var path := "user://gif_selftest.gif"
	check("打开文件", w.open(path), true)
	for i in 10:
		var img := Image.create_empty(200, 120, false, Image.FORMAT_RGB8)
		img.fill(Color(0.06, 0.09, 0.18))
		for y in 120:
			for x in 200:
				if x >= i * 18 and x < i * 18 + 24 and y >= 40 and y < 80:
					img.set_pixel(x, y, Color(1, 0.84, 0.37))
		w.add_image(img)
	check("写入 10 帧", w.frame_count(), 10)
	check("收尾", w.finish(), true)
	var f := FileAccess.open(path, FileAccess.READ)
	var data := f.get_buffer(f.get_length())
	f.close()
	print("  文件大小 %.1f KB" % (data.size() / 1024.0))
	check("文件头 GIF89a", data.slice(0, 6).get_string_from_ascii(), "GIF89a")
	check("宽 200", data.decode_u16(6), 200)
	check("高 120", data.decode_u16(8), 120)
	check("最后一字节是 trailer", data[data.size() - 1], 0x3B)
	var blocks := 0
	for i in data.size():
		if data[i] == 0x21 and data[i + 1] == 0xF9:
			blocks += 1
	check("有 10 个图形控制块", blocks, 10)
	print("")
	print("失败 %d 项 ❌" % fails if fails > 0 else "GIF 写入器自检全部通过 ✅")
	quit()

func check(name: String, got, want) -> void:
	var ok := str(got) == str(want)
	if ok:
		print("  ✅ %-24s %s" % [name, str(got)])
	else:
		fails += 1
		print("  ❌ %-24s 得到 %s，期望 %s" % [name, str(got), str(want)])
