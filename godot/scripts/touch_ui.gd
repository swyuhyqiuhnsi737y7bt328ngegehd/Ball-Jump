class_name TouchUI
extends Control

## 触屏虚拟按键（左下：◀ ▶，右下：跳）
##
## 为什么不用 Button：Godot 默认的 emulate_mouse_from_touch 只把**第一根手指**当成鼠标，
## 第二根手指按「跳」时不会产生任何 GUI 事件 —— 平台跳跃必须能「按住右 + 点跳」，
## 所以这里直接收 InputEventScreenTouch / ScreenDrag，按手指编号逐指跟踪。
## 鼠标也一起收（桌面调试方便，也兼容触摸板）。

const BTN_R := 44.0
const JUMP_R := 52.0

var dir := 0                 # -1 左 / 0 / 1 右
var jump := false            # 是否有手指按在跳键上

var _rects := {}
var _fingers := {}           # 手指 index -> 键名
var _held := {"left": 0, "right": 0, "jump": 0}
var _flash := {"left": 0.0, "right": 0.0, "jump": 0.0}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_rects = {
		"left": Rect2(112.0 - BTN_R, 450.0 - BTN_R, BTN_R * 2.0, BTN_R * 2.0),
		"right": Rect2(216.0 - BTN_R, 450.0 - BTN_R, BTN_R * 2.0, BTN_R * 2.0),
		"jump": Rect2(790.0 - JUMP_R, 442.0 - JUMP_R, JUMP_R * 2.0, JUMP_R * 2.0),
	}

func _process(delta: float) -> void:
	var dirty := false
	for k in _flash:
		var target := 1.0 if _held[k] > 0 else 0.0
		if not is_equal_approx(_flash[k], target):
			_flash[k] = move_toward(_flash[k], target, delta * 9.0)
			dirty = true
	if dirty:
		queue_redraw()

# ---------------------------------------------------------------- 输入

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.index, event.position)
		else:
			_release(event.index)
	elif event is InputEventScreenDrag:
		var k: String = _fingers.get(event.index, "")
		if k != "" and not (_rects[k] as Rect2).has_point(event.position):
			_release(event.index)      # 手指划出按钮就算松开
	elif event is InputEventMouseButton:
		if event.pressed:
			_press(-1, event.position)
		else:
			_release(-1)

func _press(index: int, pos: Vector2) -> void:
	var k := hit(pos)
	if k == "":
		return
	_fingers[index] = k
	_held[k] += 1
	_sync()
	get_viewport().set_input_as_handled()

func _release(index: int) -> void:
	var k: String = _fingers.get(index, "")
	if k == "":
		return
	_fingers.erase(index)
	_held[k] = maxi(0, _held[k] - 1)
	_sync()
	get_viewport().set_input_as_handled()

## 隐藏时把状态清空，免得松手事件被吞掉后方向键卡住
func reset() -> void:
	_fingers.clear()
	for k in _held:
		_held[k] = 0
	_sync()

func hit(pos: Vector2) -> String:
	for k in _rects:
		if (_rects[k] as Rect2).has_point(pos):
			return k
	return ""

func _sync() -> void:
	dir = (1 if _held["right"] > 0 else 0) - (1 if _held["left"] > 0 else 0)
	jump = _held["jump"] > 0
	queue_redraw()

# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	_key(_rects["left"], "◀", _flash["left"], false)
	_key(_rects["right"], "▶", _flash["right"], false)
	_key(_rects["jump"], "跳", _flash["jump"], true)

func _key(r: Rect2, label: String, k: float, big: bool) -> void:
	var c := r.get_center()
	var rad := r.size.x * 0.5
	var base := Color(0.36, 0.66, 1.0) if big else Color(0.32, 0.55, 0.88)
	draw_circle(c, rad + k * 3.0, Color(base.r, base.g, base.b, 0.16 + k * 0.30))
	draw_arc(c, rad + k * 2.0, 0.0, TAU, 48, Color(0.66, 0.85, 1.0, 0.28 + k * 0.45), 2.0 + k, true)
	var f := ThemeDB.fallback_font
	if f == null:
		return
	var fs := 30 if big else 26
	var sz := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(f, c + Vector2(-sz.x * 0.5, sz.y * 0.34), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(1.0, 1.0, 1.0, 0.70 + k * 0.30))
