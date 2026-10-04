class_name GifWriter
extends RefCounted

## 极简 GIF89a 写入器（自己写 LZW）
##
## 为什么不用 AVI：MJPEG 的 AVI 本身是合法的（Godot 自己的 Movie Maker 也写这个），
## 但 Windows 自带播放器没有 MJPEG 解码器，双击就是打不开。
## GIF 不需要任何解码器 —— 浏览器、微信、QQ、Windows 照片、手机相册全都能放，还能循环。

# 这个游戏画面偏蓝（深蓝渐变背景 + 蓝色平台），所以蓝给 3 位、绿给 2 位，
# 比均匀的 3-3-2 明显少一圈色带
const PAL_R := 8       # 3 位红
const PAL_G := 4       # 2 位绿
const PAL_B := 8       # 3 位蓝  → 8*4*8 = 256 色

# 4x4 有序抖动，便宜且能把渐变磨平
const BAYER4 := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

var width := 450
var height := 280
var delay_cs := 8      # 帧间隔，单位 1/100 秒
var error := ""

var _f: FileAccess
var _palette := PackedByteArray()
var _frames_written := 0

func _init(w: int, h: int, fps: int) -> void:
	width = w
	height = h
	delay_cs = maxi(2, int(round(100.0 / float(maxi(1, fps)))))
	# 顺序必须和 _quantize 的位打包一致：index = r*32 + g*8 + b
	for r in PAL_R:
		for g in PAL_G:
			for b in PAL_B:
				_palette.append(int(round(float(r) * 255.0 / float(PAL_R - 1))))
				_palette.append(int(round(float(g) * 255.0 / float(PAL_G - 1))))
				_palette.append(int(round(float(b) * 255.0 / float(PAL_B - 1))))

func open(path: String) -> bool:
	_f = FileAccess.open(path, FileAccess.WRITE)
	if _f == null:
		error = "打不开文件：%s" % path
		return false
	_ascii("GIF89a")
	_u16(width)
	_u16(height)
	_f.store_8(0xF7)          # 有全局色表 / 8 位色深 / 256 项
	_f.store_8(0)             # 背景色索引
	_f.store_8(0)             # 像素宽高比
	_f.store_buffer(_palette)
	# NETSCAPE2.0 —— 无限循环
	_f.store_8(0x21)
	_f.store_8(0xFF)
	_f.store_8(0x0B)
	_ascii("NETSCAPE2.0")
	_f.store_8(0x03)
	_f.store_8(0x01)
	_u16(0)
	_f.store_8(0x00)
	return true

func add_image(img: Image) -> void:
	if _f == null:
		return
	var im := img
	if im.get_width() != width or im.get_height() != height:
		im = im.duplicate()
		im.resize(width, height, Image.INTERPOLATE_BILINEAR)
	if im.get_format() != Image.FORMAT_RGB8:
		im.convert(Image.FORMAT_RGB8)
	var indices := _quantize(im)

	# 图形控制扩展：disposal=1（保留上一帧），带延时
	_f.store_8(0x21)
	_f.store_8(0xF9)
	_f.store_8(0x04)
	_f.store_8(0x04)
	_u16(delay_cs)
	_f.store_8(0)
	_f.store_8(0)
	# 图像描述符
	_f.store_8(0x2C)
	_u16(0)
	_u16(0)
	_u16(width)
	_u16(height)
	_f.store_8(0)
	_lzw(indices, 8)
	_f.store_8(0x00)          # 数据块结束
	_frames_written += 1

func frame_count() -> int:
	return _frames_written

func finish() -> bool:
	if _f == null:
		return false
	_f.store_8(0x3B)          # trailer
	_f.close()
	_f = null
	return true

# ---------------------------------------------------------------- 内部

## 直接位打包 + 4x4 有序抖动：O(1) 一个像素，不用找最近色（GDScript 里快得多）
func _quantize(img: Image) -> PackedByteArray:
	var data := img.get_data()
	var out := PackedByteArray()
	out.resize(width * height)
	for y in height:
		var row := y * width
		for x in width:
			var i := row + x
			var b: int = (int(BAYER4[(y & 3) * 4 + (x & 3)]) - 8) * 3   # ±24 的扰动
			var r := clampi(int(data[i * 3]) + b, 0, 255)
			var g := clampi(int(data[i * 3 + 1]) + b, 0, 255)
			var bl := clampi(int(data[i * 3 + 2]) + b, 0, 255)
			out[i] = ((r >> 5) << 5) | ((g >> 6) << 3) | (bl >> 5)
	return out

func _lzw(indices: PackedByteArray, min_code: int) -> void:
	# ★ LZW 最小码长必须先单独写一个字节，漏了它解码器会把子块长度当成码长
	_f.store_8(min_code)
	var clear := 1 << min_code
	var eoi := clear + 1
	var next_code := eoi + 1
	var code_size := min_code + 1
	var dict := {}
	var block := PackedByteArray()
	var bitbuf := 0
	var bitcnt := 0

	# 初始 clear
	bitbuf |= clear << bitcnt
	bitcnt += code_size
	while bitcnt >= 8:
		block.append(bitbuf & 0xFF)
		bitbuf >>= 8
		bitcnt -= 8

	var cur := -1
	for i in indices.size():
		var c := int(indices[i])
		if cur < 0:
			cur = c
			continue
		var key := (cur << 8) | c
		if dict.has(key):
			cur = dict[key]
			continue
		# 输出 cur
		bitbuf |= cur << bitcnt
		bitcnt += code_size
		while bitcnt >= 8:
			block.append(bitbuf & 0xFF)
			bitbuf >>= 8
			bitcnt -= 8
		dict[key] = next_code
		next_code += 1
		if code_size < 12:
			# ★ 阈值要 +1：解码器的字典永远比编码器慢一格（它得等下一个码才知道
			#   上一个码的尾巴），所以码长必须晚一格增长，否则 511→512 那一下就错位，
			#   存的 GIF 会变成「broken data stream」
			if next_code >= (1 << code_size) + 1:
				code_size += 1
		elif next_code > 4095:
			# 12 位（4095）塞满了：发 clear 重来
			bitbuf |= clear << bitcnt
			bitcnt += code_size
			while bitcnt >= 8:
				block.append(bitbuf & 0xFF)
				bitbuf >>= 8
				bitcnt -= 8
			dict.clear()
			next_code = eoi + 1
			code_size = min_code + 1
		cur = c

	# 收尾：最后一个前缀 + EOI
	if cur >= 0:
		bitbuf |= cur << bitcnt
		bitcnt += code_size
		while bitcnt >= 8:
			block.append(bitbuf & 0xFF)
			bitbuf >>= 8
			bitcnt -= 8
	bitbuf |= eoi << bitcnt
	bitcnt += code_size
	while bitcnt >= 8:
		block.append(bitbuf & 0xFF)
		bitbuf >>= 8
		bitcnt -= 8
	if bitcnt > 0:
		block.append(bitbuf & 0xFF)

	# 按 <=255 字节切成子块
	var pos := 0
	while pos < block.size():
		var n := mini(255, block.size() - pos)
		_f.store_8(n)
		_f.store_buffer(block.slice(pos, pos + n))
		pos += n

func _u16(v: int) -> void:
	_f.store_8(v & 0xFF)
	_f.store_8((v >> 8) & 0xFF)

func _ascii(s: String) -> void:
	for i in s.length():
		_f.store_8(s.unicode_at(i))
