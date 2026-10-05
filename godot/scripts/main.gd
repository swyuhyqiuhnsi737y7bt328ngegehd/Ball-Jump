extends Node2D

## 主程序：游戏流程 / 输入 / 界面（菜单、通关浮层、Toast、JSON 面板、编辑器工具栏）
## 对应 cd.html 的启动、菜单、overlay、主循环部分

const FIXED := 1.0 / 120.0
const TIME_SCALES := [0.1, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0]

@onready var world: World = $World

var font: SystemFont
var root_theme: Theme

# ---- 流程状态 ----
var playlist: Array = []
var level_index := 0
var level: Dictionary = {}
var deaths := 0
var total_time := 0.0
var testing := false
var playing := false

# ---- TAS ----
var time_scale_idx := 4
var time_scale := 1.0
var frozen := false
var step_queue := 0
var physics_steps := 0

var _acc := 0.0

# ---- UI ----
var ui_layer: CanvasLayer
var menu_panel: PanelContainer
var menu_list: VBoxContainer
var overlay: Control
var ov_title: Label
var ov_text: Label
var ov_btn: Button
var ov_replay_btn: Button
# ---- 触屏 ----
var touch_ui: TouchUI
var touch_enabled := false
var ov_cb: Callable = Callable()
var toast: Label
var toast_left := 0.0
var _toast_tween: Tween
var _scale_hint_time := 0.0      # 变速提示显示多久了（几秒后淡下去）
var hint: Label
var menu_btn: Button
# ---- 复盘（死亡回放）----
var replay_panel: PanelContainer
var replay_slider: HSlider
var replay_info: Label
var replay_play_btn: Button
var replay_speed_btns := {}
var replay_active := false
var replay_playing := false
var replay_t := 0.0
var replay_speed := 1.0
var replay_return_overlay := false   # 看完回通关浮层而不是继续玩
var export_btn: Button
var export_gif_btn: Button
var video_exporting := false
const VIDEO_FPS := 30
const GIF_W := 450       # GIF 体积考虑，导出时缩到这个尺寸
const GIF_H := 280
const GIF_FPS := 12

var menu_scrim: ColorRect
var _bb_menu: BackBufferCopy
var _bb_overlay: BackBufferCopy
var json_panel: PanelContainer
var json_text: TextEdit
var storage_warn: Label

var editor: Editor

func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray([
		"Microsoft YaHei", "微软雅黑", "SimHei", "Noto Sans CJK SC",
		"PingFang SC", "sans-serif",
	])
	world.font = font

	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Courier New", "monospace"])

	root_theme = UITheme.build(font, mono)
	get_window().theme = root_theme

	_build_ui()

	world.ball_died.connect(_on_ball_died)
	world.level_won.connect(_on_level_won)

	editor = Editor.new()
	editor.setup(self, world)

	playlist = LevelIO.load_levels()
	if playlist.is_empty():
		playlist.append(_demo_level())
		LevelIO.save_levels(playlist)

	_fit_window()
	open_menu()

	# 调试用：godot --play 直接进第一关（方便截图 / 自动化）
	if OS.get_cmdline_args().has("--play") and not playlist.is_empty():
		var idx := 0
		for a in OS.get_cmdline_args():
			if a.begins_with("--level="):
				idx = clampi(int(a.substr(8)), 0, playlist.size() - 1)
		_play_level(idx)
	elif OS.get_cmdline_args().has("--edit-level") and not playlist.is_empty():
		editor.open_with(playlist[0], 0)
	elif OS.get_cmdline_args().has("--win-demo") and not playlist.is_empty():
		_play_level(0)
		await get_tree().create_timer(0.6).timeout
		show_overlay("🎉 过关！", "示例关卡 · 跑一圈\n用时 12.34 秒　·　金币 3/5", "下一关", func(): pass)
	# 有触摸屏就自动开虚拟按键；桌面上可以 --touch 或菜单里手动开
	# （这段必须独立于上面的 --play/--edit-level 链，别把 elif 抢走）
	touch_enabled = DisplayServer.is_touchscreen_available() or OS.get_cmdline_args().has("--touch")
	if touch_ui != null:
		touch_ui.visible = false
	if OS.get_cmdline_args().has("--replay-demo") and not playlist.is_empty():
		_play_level(0)
		await get_tree().create_timer(1.2).timeout
		world.rec_snapshot_now()
		open_replay()
		world.replay_end_fx = 0

## 对应原版的 layoutCanvas()：窗口撑到屏幕的 96% × 94% 并居中，
## 剩下的交给 stretch 等比缩放，画面不会被拉变形也不会糊
func _fit_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var idx := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(idx)
	if usable.size.x <= 0 or usable.size.y <= 0:
		return
	var s := minf(usable.size.x * 0.96 / 900.0, usable.size.y * 0.94 / 560.0)
	s = clampf(s, 0.6, 1.9)
	var w := int(round(900.0 * s))
	var h := int(round(560.0 * s))
	DisplayServer.window_set_size(Vector2i(w, h))
	DisplayServer.window_set_position(usable.position + (usable.size - Vector2i(w, h)) / 2)

## 内置示例关卡：第一次运行时会自动出现在菜单里
func _demo_level() -> Dictionary:
	return LevelIO.normalize_level({
		"name": "示例关卡 · 跑一圈",
		"spawn": {"x": 60, "y": 440},
		"goal": {"x": 850, "y": 160, "r": 22},
		"platforms": [
			{"x": 0, "y": 500, "w": 280, "h": 20},
			{"x": 350, "y": 500, "w": 210, "h": 20},
			{"x": 620, "y": 500, "w": 280, "h": 20},
			{"x": 300, "y": 400, "w": 160, "h": 16},
			{"x": 560, "y": 400, "w": 140, "h": 16},
			{"x": 120, "y": 300, "w": 180, "h": 16},
			{"x": 400, "y": 260, "w": 180, "h": 16},
			{"x": 660, "y": 200, "w": 240, "h": 16},
		],
		"spikes": [
			{"x": 285, "y": 500, "w": 60, "h": 20, "dir": "up"},
			{"x": 565, "y": 500, "w": 50, "h": 20, "dir": "up"},
			{"x": 470, "y": 260, "w": 60, "h": 24, "dir": "down"},
		],
		"items": [
			{"type": "coin", "x": 200, "y": 455, "r": 13},
			{"type": "coin", "x": 320, "y": 355, "r": 13},
			{"type": "coin", "x": 430, "y": 215, "r": 13},
			{"type": "coin", "x": 700, "y": 155, "r": 13},
			{"type": "coin", "x": 180, "y": 255, "r": 13},
			{"type": "spring", "x": 240, "y": 482, "w": 42, "h": 18, "power": 1180, "r": 0},
			{"type": "boost", "x": 630, "y": 478, "w": 130, "h": 22, "power": 540, "dir": 1},
			{"type": "checkpoint", "x": 400, "y": 470, "r": 22},
			{"type": "portal", "x": 150, "y": 270, "r": 24},
			{"type": "portal", "x": 700, "y": 170, "r": 24},
		],
	})

# ================================================================ UI 构建

func _mk_button(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	UITheme.apply_plain(b)
	if primary:
		UITheme.apply_primary(b)
	b.pressed.connect(cb)
	return b

## 小号按钮（列表行里那些）
func _mk_mini(text: String, cb: Callable) -> Button:
	var b := _mk_button(text, cb)
	b.add_theme_font_size_override("font_size", 12)
	return b

func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	# ---- 编辑器工具栏 ----
	# （Editor 自己会挂在 ui_layer 下）

	# ---- 右下角菜单按钮（和原版一致：圆角方块）----
	menu_btn = _mk_button("☰", _toggle_menu)
	menu_btn.add_theme_font_size_override("font_size", 18)
	menu_btn.position = Vector2(842, 502)
	menu_btn.size = Vector2(44, 44)
	ui_layer.add_child(menu_btn)

	# ---- 底部操作提示（居中、很淡）----
	hint = Label.new()
	hint.text = "← → / A D 移动　·　空格 / ↑ / W 跳跃（可二段跳）　·　[ ] 变速　·　P 冻结　·　F 逐帧　·　Esc 菜单"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UITheme.C_TEXT_FAINT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 530
	hint.offset_bottom = 550
	ui_layer.add_child(hint)

	# ---- Toast（胶囊，顶部滑入）----
	toast = Label.new()
	toast.add_theme_font_size_override("font_size", 14)
	toast.add_theme_color_override("font_color", UITheme.C_TEXT)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_stylebox_override("normal", UITheme.glow(
		UITheme.flat(Color(20 / 255.0, 34 / 255.0, 70 / 255.0, 0.96), 999, 1,
			Color(120 / 255.0, 170 / 255.0, 255 / 255.0, 0.3), 20.0, 9.0),
		Color(0, 0, 0, 0.45), 14, 6))
	toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	toast.offset_top = 16
	toast.offset_bottom = 54
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.visible = false
	ui_layer.add_child(toast)

	# ---- 通关 / 结算浮层：整屏压暗 + 发光标题 + 胶囊按钮 ----
	# ---- 触屏虚拟按键（放在浮层之前，保证浮层 still 在最上面）----
	touch_ui = TouchUI.new()
	touch_ui.name = "TouchUI"
	touch_ui.visible = false
	ui_layer.add_child(touch_ui)

	_bb_overlay = BackBufferCopy.new()
	_bb_overlay.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_bb_overlay.visible = false
	ui_layer.add_child(_bb_overlay)
	overlay = ColorRect.new()
	overlay.color = Color.WHITE
	overlay.material = UITheme.make_frosted(UITheme.C_SCRIM, 3.2)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_overlay_pressed())
	overlay.visible = false
	ui_layer.add_child(overlay)
	var ov_center := CenterContainer.new()
	ov_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(ov_center)
	var ov_box := VBoxContainer.new()
	ov_box.add_theme_constant_override("separation", 16)
	ov_box.alignment = BoxContainer.ALIGNMENT_CENTER
	ov_center.add_child(ov_box)
	ov_title = Label.new()
	ov_title.add_theme_font_size_override("font_size", 36)
	ov_title.add_theme_color_override("font_color", Color("e8f6ff"))
	ov_title.add_theme_color_override("font_outline_color", Color(125 / 255.0, 211 / 255.0, 252 / 255.0, 0.5))
	ov_title.add_theme_constant_override("outline_size", 12)
	ov_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov_box.add_child(ov_title)
	ov_text = Label.new()
	ov_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov_text.add_theme_color_override("font_color", UITheme.C_TEXT_DIM)
	ov_text.add_theme_font_size_override("font_size", 15)
	ov_text.add_theme_constant_override("line_spacing", 8)
	ov_box.add_child(ov_text)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 10)
	ov_box.add_child(btn_row)
	# 通关也能复盘：看过瘾了再点下一关
	ov_replay_btn = _mk_button("复盘刚才这一局", func(): open_replay(true))
	ov_replay_btn.add_theme_font_size_override("font_size", 14)
	ov_replay_btn.custom_minimum_size = Vector2(176, 48)
	ov_replay_btn.visible = false
	btn_row.add_child(ov_replay_btn)
	ov_btn = _mk_button("继续", func(): _overlay_pressed())
	UITheme.apply_pill(ov_btn)
	ov_btn.add_theme_font_size_override("font_size", 16)
	ov_btn.custom_minimum_size = Vector2(200, 48)
	ov_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn_row.add_child(ov_btn)

	# ---- 关卡菜单（背后也是毛玻璃）----
	_bb_menu = BackBufferCopy.new()
	_bb_menu.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_bb_menu.visible = false
	ui_layer.add_child(_bb_menu)
	menu_scrim = ColorRect.new()
	menu_scrim.color = Color.WHITE
	menu_scrim.material = UITheme.make_frosted(Color(6 / 255.0, 10 / 255.0, 26 / 255.0, 0.62), 4.0)
	menu_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_scrim.visible = false
	ui_layer.add_child(menu_scrim)

	menu_panel = PanelContainer.new()
	UITheme.apply_card(menu_panel)
	menu_panel.position = Vector2(150, 40)
	menu_panel.size = Vector2(600, 480)
	ui_layer.add_child(menu_panel)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 10)
	menu_panel.add_child(mv)
	var head := HBoxContainer.new()
	mv.add_child(head)
	var title := Label.new()
	title.text = "我的关卡"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_mk_button("＋ 新建关卡", func(): _new_level(), true))
	storage_warn = Label.new()
	storage_warn.add_theme_font_size_override("font_size", 12)
	storage_warn.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4, 0.9))
	storage_warn.visible = false
	mv.add_child(storage_warn)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mv.add_child(scroll)
	menu_list = VBoxContainer.new()
	menu_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_list.add_theme_constant_override("separation", 6)
	scroll.add_child(menu_list)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	mv.add_child(foot)
	foot.add_child(_mk_button("导出全部", func(): _export_all()))
	foot.add_child(_mk_button("导入全部", func(): _import_all()))
	foot.add_child(_mk_button("触屏按键", func(): _toggle_touch()))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(spacer)
	foot.add_child(_mk_button("关闭", func(): close_menu(), true))

	# ---- 复盘面板（死亡后回放这一条命）----
	replay_panel = PanelContainer.new()
	UITheme.apply_floating(replay_panel)
	replay_panel.position = Vector2(110, 452)
	replay_panel.size = Vector2(680, 98)
	replay_panel.visible = false
	ui_layer.add_child(replay_panel)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	replay_panel.add_child(rv)
	var rhead := HBoxContainer.new()
	rv.add_child(rhead)
	var rtitle := Label.new()
	rtitle.text = "复盘"
	rtitle.add_theme_font_size_override("font_size", 15)
	rtitle.add_theme_color_override("font_color", UITheme.C_ACCENT_SOFT)
	rhead.add_child(rtitle)
	replay_info = Label.new()
	replay_info.add_theme_font_size_override("font_size", 12)
	replay_info.add_theme_color_override("font_color", UITheme.C_TEXT_DIM)
	replay_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rhead.add_child(replay_info)
	export_gif_btn = _mk_mini("导出 GIF", func(): export_replay(true))
	export_gif_btn.add_theme_color_override("font_color", UITheme.C_ACCENT_SOFT)
	rhead.add_child(export_gif_btn)
	export_btn = _mk_mini("导出 AVI", func(): export_replay(false))
	rhead.add_child(export_btn)
	rhead.add_child(_mk_mini("关闭", func(): close_replay()))
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 6)
	rv.add_child(rrow)
	replay_slider = HSlider.new()
	replay_slider.min_value = 0.0
	replay_slider.max_value = 1.0
	replay_slider.step = 0.005
	replay_slider.custom_minimum_size = Vector2(220, 0)
	replay_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	replay_slider.value_changed.connect(func(v: float):
		replay_t = v
		world.replay_end_fx = 0
		world.trail.clear()
		world.replay_apply(replay_t))
	rrow.add_child(replay_slider)
	rrow.add_child(_mk_mini("重播", func(): _replay_restart()))
	replay_play_btn = _mk_mini("暂停", func(): _replay_toggle())
	rrow.add_child(replay_play_btn)
	var spd := Label.new()
	spd.text = "倍速"
	spd.add_theme_font_size_override("font_size", 12)
	spd.add_theme_color_override("font_color", UITheme.C_TEXT_DIM)
	rrow.add_child(spd)
	for s in [0.25, 0.5, 1.0, 2.0]:
		var b := _mk_mini(_speed_label(s), func(): _replay_set_speed(s))
		b.custom_minimum_size = Vector2(52, 0)
		replay_speed_btns[s] = b
		rrow.add_child(b)

	# ---- JSON 面板 ----
	json_panel = PanelContainer.new()
	UITheme.apply_card(json_panel)
	json_panel.position = Vector2(120, 30)
	json_panel.size = Vector2(660, 500)
	json_panel.visible = false
	ui_layer.add_child(json_panel)
	var jv := VBoxContainer.new()
	jv.add_theme_constant_override("separation", 10)
	json_panel.add_child(jv)
	var jt := Label.new()
	jt.text = "JSON 导入 / 导出（当前关卡）"
	jt.add_theme_font_size_override("font_size", 18)
	jv.add_child(jt)
	json_text = TextEdit.new()
	json_text.custom_minimum_size = Vector2(0, 330)
	json_text.add_theme_font_size_override("font_size", 12)
	jv.add_child(json_text)
	var jb := HBoxContainer.new()
	jb.add_theme_constant_override("separation", 8)
	jv.add_child(jb)
	jb.add_child(_mk_button("导入到编辑器", func(): _json_import(), true))
	jb.add_child(_mk_button("复制到剪贴板", func(): _json_copy()))
	jb.add_child(_mk_button("关闭", func(): close_json()))

# ================================================================ 提示 / 浮层

func show_toast(msg: String) -> void:
	toast.text = msg
	# 进出场共用一条补间，避免「淡入还没走完就被淡出接管」而卡在中间
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	toast.visible = true
	toast.modulate.a = 0.0
	toast.offset_top = 6.0
	_toast_tween = toast.create_tween()
	_toast_tween.set_parallel(true)
	_toast_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_property(toast, "modulate:a", 1.0, 0.22)
	_toast_tween.tween_property(toast, "offset_top", 18.0, 0.22)
	toast_left = 2.2          # ★ 之前这行丢了，toast_left 永远是 0 → 提示永不消失

func _hide_toast() -> void:
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	toast.visible = true
	_toast_tween = toast.create_tween()
	_toast_tween.set_parallel(true)
	_toast_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.28)
	_toast_tween.tween_property(toast, "offset_top", 6.0, 0.28)
	_toast_tween.chain().tween_callback(func(): toast.visible = false)

func show_overlay(title: String, text: String, btn: String, cb: Callable) -> void:
	ov_title.text = title
	ov_text.text = text
	ov_btn.text = btn
	ov_cb = cb
	# 有录像才给「复盘」按钮（刚复活就死这种太短的就不显示）
	ov_replay_btn.visible = world.rec_duration_cur() >= 0.35 and not replay_active
	overlay.visible = true
	_bb_overlay.visible = true
	ui_layer.move_child(_bb_overlay, ui_layer.get_child_count() - 2)
	ui_layer.move_child(overlay, ui_layer.get_child_count() - 1)
	UITheme.pop_in(ov_btn, 0.26, 0.9)
	UITheme.pop_in(ov_title, 0.24, 1.0)
	UITheme.pop_in(ov_text, 0.24, 1.0)
	var tw := overlay.create_tween()
	overlay.modulate.a = 0.0
	tw.tween_property(overlay, "modulate:a", 1.0, 0.22)
	refresh_pause()

func hide_overlay() -> void:
	overlay.visible = false
	_bb_overlay.visible = false
	refresh_pause()

func _overlay_pressed() -> void:
	overlay.visible = false
	world.sync_jump_state()      # 回车/空格关浮层时同理
	refresh_pause()
	if ov_cb.is_valid():
		ov_cb.call()

func refresh_pause() -> void:
	playing = (not level.is_empty()) and (not editor.is_open()) and (not menu_panel.visible) \
		and (not json_panel.visible) and (not overlay.visible) and (not replay_active)

# ================================================================ 关卡菜单

func set_menu_visible(v: bool) -> void:
	var was := menu_panel.visible
	menu_panel.visible = v
	menu_scrim.visible = v
	_bb_menu.visible = v
	if v and not was:
		UITheme.pop_in_free(menu_panel, 0.24, 0.96, 14.0)

func open_menu() -> void:
	editor.force_close()
	set_menu_visible(true)
	hint.visible = false
	menu_btn.visible = false
	if testing:
		testing = false
		level = {}
		world.clear_level()
	build_menu()
	refresh_pause()

func close_menu() -> void:
	set_menu_visible(false)
	# ★ 少了这句，直接关菜单（没选关卡）之后 playing 一直是 false，球就再也不动了
	refresh_pause()
	menu_btn.visible = true
	if not level.is_empty():
		hint.visible = true
	refresh_pause()

func _toggle_menu() -> void:
	if menu_panel.visible:
		close_menu()
	else:
		open_menu()

func build_menu() -> void:
	for c in menu_list.get_children():
		c.queue_free()
	if playlist.is_empty():
		var empty := Label.new()
		empty.text = "还没有关卡。点「＋ 新建关卡」开始做一张，\n或者用「导入全部」载入网页版导出的 JSON。"
		empty.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9, 0.8))
		menu_list.add_child(empty)
		return
	for i in playlist.size():
		menu_list.add_child(_make_level_row(playlist[i], i))

func _make_level_row(lv: Dictionary, i: int) -> Control:
	var row := PanelContainer.new()
	UITheme.apply_row(row)
	row.mouse_entered.connect(func(): row.modulate = Color(1.25, 1.25, 1.25))
	row.mouse_exited.connect(func(): row.modulate = Color.WHITE)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	row.add_child(h)
	var idx_lbl := Label.new()
	idx_lbl.text = "%d." % [i + 1]
	idx_lbl.add_theme_font_size_override("font_size", 12)
	idx_lbl.add_theme_color_override("font_color", Color(140 / 255.0, 180 / 255.0, 240 / 255.0, 0.6))
	h.add_child(idx_lbl)
	var name_lbl := Label.new()
	name_lbl.text = str(lv["name"])
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color("dbe8ff"))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_lbl)
	var meta := Label.new()
	meta.text = "%d 平台 · %d 尖刺 · %d 道具" % [(lv["platforms"] as Array).size(), (lv["spikes"] as Array).size(), (lv["items"] as Array).size()]
	meta.add_theme_font_size_override("font_size", 11)
	meta.add_theme_color_override("font_color", Color(140 / 255.0, 180 / 255.0, 240 / 255.0, 0.55))
	h.add_child(meta)
	h.add_child(_mk_mini("▶ 开始", func(): _play_level(i)))
	h.add_child(_mk_mini("编辑", func(): editor.open_with(playlist[i], i)))
	h.add_child(_mk_mini("JSON", func(): open_json(playlist[i])))
	var del := _mk_mini("删除", func(): _delete_level(i))
	del.add_theme_color_override("font_color", Color("ffb3c1"))
	del.add_theme_color_override("font_hover_color", Color("ffd0da"))
	h.add_child(del)
	return row

func _new_level() -> void:
	editor.open_with(LevelIO.blank_level(), -1)

func _delete_level(i: int) -> void:
	if i < 0 or i >= playlist.size():
		return
	var nm := str(playlist[i]["name"])
	playlist.remove_at(i)
	LevelIO.save_levels(playlist)
	build_menu()
	show_toast("已删除「%s」" % nm)

## 手动开关触屏虚拟按键（桌面上也能试）
func _toggle_touch() -> void:
	touch_enabled = not touch_enabled
	if touch_ui != null and not touch_enabled:
		touch_ui.visible = false
		touch_ui.reset()
	show_toast("触屏按键：%s" % ("开" if touch_enabled else "关"))

func _play_level(i: int) -> void:
	if i < 0 or i >= playlist.size():
		return
	level_index = i
	reset_run()
	load_level(i)

func reset_run() -> void:
	deaths = 0
	total_time = 0.0
	testing = false

## 编辑器「试玩」：跑一份临时关卡，不进关卡列表
func play_test(lv: Dictionary) -> void:
	testing = true
	deaths = 0
	total_time = 0.0
	level_index = -1
	level = lv
	world.editor_mode = false      # 试玩要看游戏画面，不是编辑器网格
	world.load_level(lv)
	set_menu_visible(false)
	menu_btn.visible = true
	hint.visible = true
	hide_overlay()
	world.hud_testing = true
	refresh_pause()

func load_level(i: int) -> void:
	level_index = i
	level = playlist[i]
	world.load_level(level)
	set_menu_visible(false)
	menu_btn.visible = true
	hint.visible = true
	hide_overlay()
	testing = false
	refresh_pause()

func _on_ball_died() -> void:
	deaths += 1
	# 有录像就弹复盘；太短（刚复活就死）就不打扰
	if world.rec_duration() >= 0.35:
		open_replay()

# ================================================================ 复盘

func _speed_label(s: float) -> String:
	# GDScript 的 % 格式化不支持 %g，自己来
	if is_equal_approx(s, roundf(s)):
		return "%d×" % int(roundf(s))
	return "%s×" % str(s)

## 死亡后弹出：回放这一条命，可 0.25× ~ 2× 变速、可拖进度
func open_replay(from_win := false) -> void:
	replay_active = true
	replay_return_overlay = from_win
	if from_win:
		world.rec_snapshot_now()      # 通关没有死亡快照，现定一版
		overlay.visible = false
		_bb_overlay.visible = false
		hint.visible = false
	replay_t = 0.0
	replay_playing = true
	replay_speed = 1.0
	replay_play_btn.text = "暂停"
	world.replay_mode = true
	world.replay_end_fx = 1 if not from_win else 2
	world.trail.clear()
	var dur := world.rec_duration()
	replay_slider.min_value = 0.0
	replay_slider.max_value = maxf(0.01, dur)
	replay_slider.set_value_no_signal(0.0)
	replay_info.text = "这条命 %.1f 秒　·　死亡 %d 次　·　空格 / 回车 = 重生" % [dur, deaths]
	for s in replay_speed_btns:
		UITheme.apply_toggle(replay_speed_btns[s], is_equal_approx(s, replay_speed))
	replay_panel.visible = true
	UITheme.pop_in_free(replay_panel, 0.22, 0.97, 18.0)
	world.replay_apply(0.0)
	refresh_pause()

func close_replay() -> void:
	replay_active = false
	replay_playing = false
	replay_panel.visible = false
	world.replay_mode = false
	world.replay_end_fx = 0
	world.trail.clear()
	if replay_return_overlay:
		# 从通关浮层进来的，看完回浮层，不要复活球
		replay_return_overlay = false
		overlay.visible = true
		_bb_overlay.visible = true
		ui_layer.move_child(_bb_overlay, ui_layer.get_child_count() - 2)
		ui_layer.move_child(overlay, ui_layer.get_child_count() - 1)
	else:
		world.reset_ball()
	world.sync_jump_state()      # 正按着空格关掉弹窗的话，别让这一下变成起跳
	refresh_pause()

## 导出目录：优先「视频」文件夹，退而求其次桌面，再不行就 user://
func _video_dir() -> String:
	# Godot 4.7 的 OS.SystemDir 里没有 VIDEOS，就自己拼用户目录
	var home := OS.get_environment("USERPROFILE")
	if home == "":
		home = OS.get_environment("HOME")
	var candidates: Array = []
	if home != "":
		candidates.append(home.path_join("Videos"))
	candidates.append(OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP))
	for d in candidates:
		if d != "" and DirAccess.dir_exists_absolute(d):
			return d
	return ProjectSettings.globalize_path("user://")

## 把当前复盘逐帧渲染出来。
## to_gif=true → GIF（不需要任何解码器，浏览器/微信/相册都能放，推荐）
## to_gif=false → MJPEG 的 AVI（体积小画质好，但 Windows 自带播放器没有 MJPEG 解码器）
func export_replay(to_gif := true) -> void:
	if video_exporting:
		return
	var dur: float = world.rec_duration()
	if dur < 0.2:
		show_toast("这段录像太短，没什么可导出的")
		return
	video_exporting = true
	replay_playing = false
	export_btn.disabled = true
	export_gif_btn.disabled = true
	var out_fps := GIF_FPS if to_gif else VIDEO_FPS
	var total := maxi(1, int(round(dur * float(out_fps))))
	var out_dir := _video_dir()
	var stamp := Time.get_datetime_string_from_system(false, true)
	stamp = stamp.replace("-", "").replace(":", "").replace("T", "-").replace(" ", "-")
	var ext := "gif" if to_gif else "avi"
	var path := out_dir.path_join("BallJump-replay-%s.%s" % [stamp, ext])
	var avi: AviWriter = null
	var gif: GifWriter = null
	if to_gif:
		gif = GifWriter.new(GIF_W, GIF_H, GIF_FPS)
		if not gif.open(path):
			video_exporting = false
			export_btn.disabled = false
			export_gif_btn.disabled = false
			show_toast("导出失败：%s" % gif.error)
			return
	else:
		avi = AviWriter.new(900, 560, VIDEO_FPS, 0.85)

	# 录制时把界面全藏起来，视频里只有游戏画面（HUD 还在，因为它是画在世界里的）
	replay_panel.visible = false
	replay_slider.set_value_no_signal(0.0)
	var overlay_was := overlay.visible
	overlay.visible = false
	_bb_overlay.visible = false
	toast.visible = false
	hint.visible = false
	menu_btn.visible = false
	var vp := get_viewport()
	world.trail.clear()
	var crop := Rect2i()

	var got := 0
	for i in total:
		world.replay_apply(float(i) / float(out_fps))
		world.update_effects(1.0 / float(out_fps))
		world.queue_redraw()
		# 等两帧：第一帧把 queue_redraw 画出来，第二帧保证抓到的就是它。
		# （不用 RenderingServer.frame_post_draw —— 无头模式它永远不触发，会把游戏卡死）
		await get_tree().process_frame
		await get_tree().process_frame
		var tex := vp.get_texture()
		if tex == null:
			continue                      # 无头 / 无渲染时抓不到画面，直接跳过
		var img := tex.get_image()
		if img == null or img.is_empty():
			continue
		# 抓到的像素尺寸和逻辑尺寸不是一回事（窗口可能被缩放成 1.9×），
		# 所以每帧按实际图像算一次该裁哪块
		var isz := Vector2(img.get_size())
		var sc := minf(isz.x / 900.0, isz.y / 560.0)
		var content := Vector2(900.0, 560.0) * sc
		var off := (isz - content) * 0.5
		crop = Rect2i(int(off.x), int(off.y), int(content.x), int(content.y))
		var region := crop.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		if region.size.x > 8 and region.size.y > 8:
			img = img.get_region(region)
		img.convert(Image.FORMAT_RGB8)
		if img.get_width() != 900 or img.get_height() != 560:
			img.resize(900, 560, Image.INTERPOLATE_LANCZOS)
		if to_gif:
			gif.add_image(img)
		else:
			avi.add_image(img)
		got += 1
		var pct := int(float(i + 1) * 100.0 / float(total))
		if to_gif:
			export_gif_btn.text = "GIF %d%%" % pct
		else:
			export_btn.text = "AVI %d%%" % pct
		if (i + 1) % 2 == 0:
			await get_tree().process_frame

	export_btn.text = "导出 AVI"
	export_gif_btn.text = "导出 GIF"
	export_btn.disabled = false
	export_gif_btn.disabled = false
	overlay.visible = overlay_was
	_bb_overlay.visible = overlay_was
	menu_btn.visible = true
	replay_panel.visible = true
	replay_playing = false
	world.replay_apply(replay_t)
	video_exporting = false
	var ok_write := false
	var werr := ""
	if got == 0:
		werr = "画面抓不到"
	elif to_gif:
		ok_write = gif.finish()
		werr = gif.error
	else:
		ok_write = avi.save_to(path)
		werr = avi.error
	if not ok_write:
		if to_gif:
			gif.finish()
		show_toast("导出失败：%s" % werr)
		return
	var mb := float(FileAccess.get_file_as_bytes(path).size()) / 1048576.0
	# 不再自动弹资源管理器 —— 抢焦点那一下就是「卡一下」的来源
	show_toast("已导出 %s（%.1f 秒 / %d 帧 / %.1f MB）→ %s" % [ext.to_upper(), float(got) / float(out_fps), got, mb, out_dir])

func _replay_restart() -> void:
	replay_t = 0.0
	replay_playing = true
	replay_play_btn.text = "暂停"
	world.replay_end_fx = 2 if replay_return_overlay else 1
	world.trail.clear()
	world.replay_apply(0.0)
	replay_slider.set_value_no_signal(0.0)

func _replay_toggle() -> void:
	replay_playing = not replay_playing
	replay_play_btn.text = "暂停" if replay_playing else "播放"

func _replay_set_speed(s: float) -> void:
	replay_speed = s
	for k in replay_speed_btns:
		UITheme.apply_toggle(replay_speed_btns[k], is_equal_approx(k, s))
	show_toast("回放 " + _speed_label(s) + " 速度")

func _replay_tick(delta: float) -> void:
	if not replay_playing:
		return
	var dur := world.rec_duration()
	replay_t += delta * replay_speed
	if replay_t >= dur:
		replay_t = dur
		replay_playing = false
		replay_play_btn.text = "播放"
	world.replay_apply(replay_t)
	replay_slider.set_value_no_signal(replay_t)

func _on_level_won() -> void:
	playing = false
	if testing:
		show_overlay("🎉 试玩通关！",
			"%s\n用时 %.2f 秒" % [str(level["name"]), world.level_time],
			"回到编辑器", func(): editor.reopen())
		return
	var is_last := level_index >= playlist.size() - 1
	var coin_text := ""
	if world.coins_total > 0:
		coin_text = "　·　金币 %d/%d" % [world.coins_got, world.coins_total]
	if not is_last:
		show_overlay("🎉 过关！",
			"%s\n用时 %.2f 秒%s" % [str(level["name"]), world.level_time, coin_text],
			"下一关", func(): load_level(level_index + 1))
	else:
		show_overlay("🏆 全部通关！",
			"总用时 %.2f 秒\n总死亡 %d 次" % [total_time, deaths],
			"返回菜单", func(): open_menu())

func open_json(lv: Dictionary) -> void:
	json_text.text = JSON.stringify(lv, "  ")
	json_panel.visible = true
	UITheme.pop_in_free(json_panel, 0.24, 0.96, 14.0)
	refresh_pause()

func close_json() -> void:
	json_panel.visible = false
	refresh_pause()

func _json_import() -> void:
	var parsed = JSON.parse_string(json_text.text)
	var lv := LevelIO.normalize_level(parsed)
	if lv.is_empty():
		show_toast("JSON 无效，无法解析成关卡")
		return
	editor.open_with(lv, -1)
	close_json()
	show_toast("已导入到编辑器")

func _json_copy() -> void:
	DisplayServer.clipboard_set(json_text.text)
	show_toast("已复制到剪贴板")

func _export_all() -> void:
	if playlist.is_empty():
		show_toast("还没有关卡可导出")
		return
	var path := "user://balljump-levels-export.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		show_toast("导出失败：无法写入文件")
		return
	f.store_string(LevelIO.levels_to_json(playlist))
	f.close()
	DisplayServer.clipboard_set(LevelIO.levels_to_json(playlist))
	show_toast("已导出 %d 个关卡到 %s（并复制到剪贴板）" % [playlist.size(), ProjectSettings.globalize_path(path)])

func _import_all() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.add_filter("*.json", "关卡 JSON")
	dlg.size = Vector2i(700, 480)
	dlg.file_selected.connect(func(path: String):
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			show_toast("打不开文件")
			return
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if not (parsed is Array):
			show_toast("导入失败：文件内容不是关卡数组")
			return
		var added := 0
		for raw in parsed:
			var lv := LevelIO.normalize_level(raw)
			if not lv.is_empty():
				playlist.append(lv)
				added += 1
		if added == 0:
			show_toast("导入失败：没有有效的关卡")
			return
		LevelIO.save_levels(playlist)
		build_menu()
		show_toast("已导入 %d 个关卡" % added)
	)
	ui_layer.add_child(dlg)
	dlg.popup_centered()

# ================================================================ 主循环

func _process(delta: float) -> void:
	# ---- 触屏虚拟键：只在真正玩的时候露出来，其它时候把状态清干净 ----
	if touch_ui != null:
		var want := touch_enabled and playing and not editor.is_open() 			and not menu_panel.visible and not overlay.visible and not json_panel.visible 			and not replay_active and not video_exporting
		if touch_ui.visible != want:
			touch_ui.visible = want
			if not want:
				touch_ui.reset()
		world.touch_dir = touch_ui.dir
		world.touch_jump = touch_ui.jump

	world.hud_deaths = deaths
	world.hud_level_index = level_index
	world.hud_playlist_len = playlist.size()
	world.hud_frozen = frozen
	world.hud_time_scale = time_scale
	world.hud_testing = testing
	world.hud_steps = physics_steps

	# delta 偶尔会很大（卡顿/首帧），夹一下，别让一条提示瞬间被跳过
	var udelta := minf(delta, 0.1)
	if toast_left > 0.0:
		toast_left -= udelta
		if toast_left <= 0.0:
			_hide_toast()
	if _scale_hint_time > 0.0:
		_scale_hint_time -= udelta
	if replay_active:
		_replay_tick(delta)

	if frozen:
		var steps := 0
		while step_queue > 0 and steps < 300:
			if playing:
				world.step(FIXED)
				total_time += FIXED
			world.update_effects(FIXED)
			physics_steps += 1
			step_queue -= 1
			steps += 1
		step_queue = 0
		_acc = 0.0
	else:
		_acc += delta * time_scale
		var guard := 0
		while _acc >= FIXED and guard < 200:
			if playing:
				world.step(FIXED)
				total_time += FIXED
			world.update_effects(FIXED)
			physics_steps += 1
			_acc -= FIXED
			guard += 1
		if guard >= 200:
			_acc = 0.0

	world.queue_redraw()
	world.hud_testing = testing

## 编辑器的鼠标走 _unhandled_input：这样点在工具栏 / 属性面板上的那一下
## 会被 Control 吃掉，不会顺手在画布上画一笔
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if editor.is_open():
			editor.on_mouse(event as InputEventMouseButton)
		return
	if event is InputEventMouseMotion and editor.is_open():
		editor.on_motion(event as InputEventMouseMotion)

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		# 仍然处理松开（跳跃截断在 World 里用轮询实现）
		return
	# 正在输入框里打字时，别把 p / [ / ] 这些当成游戏快捷键
	var focused := get_viewport().gui_get_focus_owner()
	if (focused is LineEdit or focused is TextEdit) and k.keycode != KEY_ESCAPE:
		return
	match k.keycode:
		KEY_ESCAPE:
			if video_exporting:
				pass
			elif replay_active:
				close_replay()
			elif json_panel.visible:
				close_json()
			elif editor.is_open():
				editor.exit()
			elif menu_panel.visible:
				close_menu()
			elif testing:
				testing = false
				world.hud_testing = false
				editor.reopen()
			else:
				open_menu()
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			# 死了 / 通关了不用摸鼠标：空格或回车直接继续。
			# 平时空格是跳跃，所以这里只在复盘弹窗或结算浮层开着的时候接管。
			if replay_active:
				close_replay()
			elif overlay.visible:
				_overlay_pressed()
		KEY_TAB:
			# 编辑器里按 Tab 收起/展开面板，方便看清整张图
			if editor.is_open():
				editor.toggle_panels()
				get_viewport().set_input_as_handled()
		KEY_R:
			# 手动复盘：把刚才这一段倒回去看（死了是自动弹）
			if replay_active:
				close_replay()
			elif world.rec_duration_cur() >= 0.35:
				world.rec_snapshot_now()
				open_replay()
				world.replay_end_fx = 0          # 手动复盘不放特效
		KEY_P:
			frozen = not frozen
			show_toast("冻结" if frozen else "解冻")
		KEY_F:
			if frozen:
				step_queue += 1
		KEY_BRACKETLEFT:
			_set_scale(time_scale_idx - 1)
		KEY_BRACKETRIGHT:
			_set_scale(time_scale_idx + 1)
		KEY_BACKSLASH:
			_set_scale(4)
		KEY_ENTER:
			if overlay.visible:
				_overlay_pressed()
		KEY_SPACE:
			if overlay.visible:
				_overlay_pressed()

func _set_scale(i: int) -> void:
	time_scale_idx = clampi(i, 0, TIME_SCALES.size() - 1)
	time_scale = TIME_SCALES[time_scale_idx]
	show_toast("速度 %.2fx" % time_scale)
