class_name AviWriter
extends RefCounted

## 极简 AVI(MJPEG) 写入器
##
## Godot 没有内置视频编码，但：
##   1) Image.save_jpg_to_buffer() 能出单帧 JPEG
##   2) AVI 就是个很朴素的 RIFF 容器
## 两个一拼就能得到到处都能播的视频文件（VLC / ffmpeg / 剪映 / Windows 照片 都能直接打开）。
##
## 结构：
##   RIFF 'AVI '
##     LIST 'hdrl'
##       'avih' (MainAVIHeader 56B)
##       LIST 'strl'  'strh'(56B) 'strf'(BITMAPINFOHEADER 40B)
##     LIST 'movi'  '00dc'(每帧 JPEG)
##     'idx1' 每帧一条 16B 索引

const FOURCC_AVI := "AVI "
const FOURCC_MJPG := "MJPG"
const AVIF_HASINDEX := 0x00000010

var width := 900
var height := 560
var fps := 30
var quality := 0.85

var _frames: Array = []          # 每帧的 JPEG 字节
var _max_frame_bytes := 0
var error := ""

func _init(w := 900, h := 560, f := 30, q := 0.85) -> void:
	width = w
	height = h
	fps = maxi(1, f)
	quality = q

func add_image(img: Image) -> void:
	var jpg := img.save_jpg_to_buffer(quality)
	if jpg.is_empty():
		error = "JPEG 编码失败"
		return
	_frames.append(jpg)
	_max_frame_bytes = maxi(_max_frame_bytes, jpg.size())

func frame_count() -> int:
	return _frames.size()

## 写出 .avi，返回是否成功
func save_to(path: String) -> bool:
	if _frames.is_empty():
		error = "没有可写的帧"
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		error = "打不开文件：%s" % path
		return false

	# ---- movi 数据 + idx1 ----
	var movi := PackedByteArray()
	var idx := PackedByteArray()
	var offset := 4               # movi 数据相对 'movi' fourcc 之后的偏移（含自身 fourcc）
	for jpg in _frames:
		var sz: int = jpg.size()
		movi.append_array(_fourcc("00dc"))
		movi.append_array(_u32(sz))
		movi.append_array(jpg)
		if sz % 2 == 1:
			movi.append(0)        # chunk 要 2 字节对齐
		idx.append_array(_fourcc("00dc"))
		idx.append_array(_u32(AVIF_HASINDEX))
		idx.append_array(_u32(offset))
		idx.append_array(_u32(sz))
		offset += 8 + sz + (sz % 2)

	var avih := _avih()
	var strh := _strh()
	var strf := _strf()
	var strl := _chunk("strh", strh) + _chunk("strf", strf)
	# ★ _list() 自己会写 kind 四字符码，这里不能再手动拼一次 'hdrl'，
	#   否则变成 LIST('hdrl' 'hdrl' avih ...)，解码器读到一个长度 17 亿的假块直接拒绝
	var hdrl := _chunk("avih", avih) + _list("strl", strl)
	var body := _list("hdrl", hdrl) + _list("movi", movi) + _chunk("idx1", idx)

	# ---- RIFF 外壳 ----
	f.store_buffer(_fourcc("RIFF"))
	f.store_32(4 + body.size())
	f.store_buffer(_fourcc(FOURCC_AVI))
	f.store_buffer(body)
	f.close()
	return true

# ---------------------------------------------------------------- RIFF 小工具

static func _u16(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(2)
	b.encode_u16(0, v & 0xFFFF)
	return b

static func _u32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, v & 0xFFFFFFFF)
	return b

static func _fourcc(s: String) -> PackedByteArray:
	var b := PackedByteArray()
	for i in 4:
		b.append(s.unicode_at(i) if i < s.length() else 32)
	return b

static func _chunk(id: String, data: PackedByteArray) -> PackedByteArray:
	var b := _fourcc(id)
	b.append_array(_u32(data.size()))
	b.append_array(data)
	if data.size() % 2 == 1:
		b.append(0)
	return b

static func _list(kind: String, data: PackedByteArray) -> PackedByteArray:
	var inner := _fourcc(kind)
	inner.append_array(data)
	return _chunk("LIST", inner)

func _avih() -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array(_u32(int(1000000.0 / float(fps))))   # dwMicroSecPerFrame
	b.append_array(_u32(_max_frame_bytes * fps))        # dwMaxBytesPerSec
	b.append_array(_u32(0))                             # dwPaddingGranularity
	b.append_array(_u32(AVIF_HASINDEX))                 # dwFlags
	b.append_array(_u32(_frames.size()))                # dwTotalFrames
	b.append_array(_u32(0))                             # dwInitialFrames
	b.append_array(_u32(1))                             # dwStreams
	b.append_array(_u32(_max_frame_bytes))              # dwSuggestedBufferSize
	b.append_array(_u32(width))
	b.append_array(_u32(height))
	for i in 4:
		b.append_array(_u32(0))                         # dwReserved[4]
	return b                                            # 56 字节

func _strh() -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array(_fourcc("vids"))
	b.append_array(_fourcc(FOURCC_MJPG))
	b.append_array(_u32(0))                             # dwFlags
	b.append_array(_u16(0))                             # wPriority
	b.append_array(_u16(0))                             # wLanguage
	b.append_array(_u32(0))                             # dwInitialFrames
	b.append_array(_u32(1000))                          # dwScale
	b.append_array(_u32(fps * 1000))                    # dwRate → rate/scale = fps
	b.append_array(_u32(0))                             # dwStart
	b.append_array(_u32(_frames.size()))                # dwLength
	b.append_array(_u32(_max_frame_bytes))              # dwSuggestedBufferSize
	b.append_array(_u32(0xFFFFFFFF))                    # dwQuality
	b.append_array(_u32(0))                             # dwSampleSize
	b.append_array(_u16(0))                             # rcFrame.left
	b.append_array(_u16(0))                             # rcFrame.top
	b.append_array(_u16(width))                         # rcFrame.right
	b.append_array(_u16(height))                        # rcFrame.bottom
	return b                                            # 56 字节

func _strf() -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array(_u32(40))                            # biSize
	b.append_array(_u32(width))
	b.append_array(_u32(height))
	b.append_array(_u16(1))                             # biPlanes
	b.append_array(_u16(24))                            # biBitCount
	b.append_array(_fourcc(FOURCC_MJPG))                # biCompression = MJPG
	b.append_array(_u32(width * height * 3))            # biSizeImage
	b.append_array(_u32(0))                             # biXPelsPerMeter
	b.append_array(_u32(0))                             # biYPelsPerMeter
	b.append_array(_u32(0))                             # biClrUsed
	b.append_array(_u32(0))                             # biClrImportant
	return b                                            # 40 字节
