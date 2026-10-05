class_name Editor
extends RefCounted

## 关卡编辑器：工具栏 / 属性面板 / 鼠标放置拖拽 / 保存
## 对应 cd.html 里的 editorOpen ~ drawEditor 一段

const TOOLS := [
	{"id": "move", "label": "移动"},
	{"id": "platform", "label": "平台"},
	{"id": "spike", "label": "尖刺"},
	{"id": "spring", "label": "弹簧"},
	{"id": "boost", "label": "加速带"},
	{"id": "coin", "label": "金币"},
	{"id": "portal", "label": "传送门"},
	{"id": "checkpoint", "label": "存档点"},
	{"id": "spawn", "label": "起点"},
	{"id": "goal", "label": "终点"},
	{"id": "erase", "label": "橡皮"},
]
const RECT_TOOLS := ["platform", "spike", "spring", "boost"]
const POINT_TOOLS := ["coin", "portal", "checkpoint"]

var main: Node
var world: World

var opened := false
var edit_level: Dictionary = {}
var original_index := -1
var initial_snapshot := ""

var tool := "platform"
var snap := true
var drag = null
var draft = null
var selected = null

# ---- UI ----
var bar: PanelContainer
var props: PanelContainer
var props_body: VBoxContainer
var props_title: Label
var name_edit: LineEdit
var dirty_lbl: Label
var snap_btn: Button
var tool_buttons := {}
# ---- 面板显隐 ----
var ui_hidden := false        # 专注编辑：工具栏 + 属性面板都收起来
var panel_toggle: Button      # 工具栏里的「收起/展开面板」
var restore_btn: Button       # 收起后右下角留的小胶囊，别让人找不回来

func setup(m: Node, w: World) -> void:
	main = m
	world = w
	_build_bar()
	_build_props()

func is_open() -> bool:
	return opened

# ================================================================ UI

func _mk_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	return b

## 统一决定工具栏 / 属性面板的显隐。
## 没选中任何物件时属性面板自动收起来（不然右上角一直盖着 250×340），
## 专注模式（Tab）下两个都收起来，右下角留个小胶囊用来叫回来。
func _sync_panels() -> void:
	var show_bar: bool = opened and not ui_hidden
	bar.visible = show_bar
	props.visible = show_bar and selected != null
	if restore_btn != null:
		restore_btn.visible = opened and ui_hidden
	if panel_toggle != null:
		panel_toggle.text = "展开面板" if ui_hidden else "收起面板"

func toggle_panels() -> void:
	ui_hidden = not ui_hidden
	_sync_panels()
	if ui_hidden:
		main.show_toast("面板已收起 · 按 Tab 或点右下角「面板」恢复")
	else:
		main.show_toast("面板已展开")

func _build_bar() -> void:
	bar = PanelContainer.new()
	var sb := UITheme.flat(Color(8 / 255.0, 14 / 255.0, 34 / 255.0, 0.93), 12, 1,
		Color(120 / 255.0, 170 / 255.0, 255 / 255.0, 0.22), 10.0, 8.0)
	UITheme.glow(sb, Color(0, 0, 0, 0.5), 18, 8)
	bar.add_theme_stylebox_override("panel", sb)
	bar.position = Vector2(10, 466)
	bar.size = Vector2(880, 84)
	bar.visible = false
	main.ui_layer.add_child(bar)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	bar.add_child(v)

	# 第一行：工具
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	v.add_child(h)
	for t in TOOLS:
		var b := _mk_btn(str(t["label"]), func(): set_tool(str(t["id"])))
		b.add_theme_font_size_override("font_size", 12)
		b.custom_minimum_size = Vector2(58, 26)
		tool_buttons[str(t["id"])] = b
		h.add_child(b)

	# 第二行：吸附 / 名字 / 未保存 / 操作
	var h2 := HBoxContainer.new()
	h2.add_theme_constant_override("separation", 6)
	v.add_child(h2)
	snap_btn = _mk_btn("吸附:开", func():
		snap = not snap
		snap_btn.text = "吸附:开" if snap else "吸附:关"
		UITheme.apply_toggle(snap_btn, snap)
	)
	snap_btn.add_theme_font_size_override("font_size", 12)
	UITheme.apply_toggle(snap_btn, true)
	h2.add_child(snap_btn)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "关卡名称"
	name_edit.max_length = 24
	name_edit.custom_minimum_size = Vector2(180, 28)
	name_edit.text_changed.connect(func(_t: String): mark_dirty())
	h2.add_child(name_edit)
	dirty_lbl = Label.new()
	dirty_lbl.text = "● 未保存"
	dirty_lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	dirty_lbl.visible = false
	h2.add_child(dirty_lbl)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h2.add_child(sp2)
	panel_toggle = _mk_btn("收起面板", func(): toggle_panels())
	panel_toggle.add_theme_font_size_override("font_size", 12)
	h2.add_child(panel_toggle)
	h2.add_child(_mk_btn("▶ 试玩", func(): test_play()))
	h2.add_child(_mk_btn("保存", func(): save()))
	h2.add_child(_mk_btn("{ } JSON", func(): main.open_json(edit_level)))
	h2.add_child(_mk_btn("清空", func(): clear_level()))
	h2.add_child(_mk_btn("退出", func(): exit()))

func _build_props() -> void:
	props = PanelContainer.new()
	UITheme.apply_floating(props)
	props.position = Vector2(640, 12)
	props.size = Vector2(250, 340)
	props.visible = false
	main.ui_layer.add_child(props)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	props.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	props_title = Label.new()
	props_title.text = "属性"
	props_title.add_theme_font_size_override("font_size", 13)
	props_title.add_theme_color_override("font_color", UITheme.C_ACCENT_SOFT)
	props_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(props_title)
	var close_btn := _mk_btn("✕", func(): selected = null; render_props())
	close_btn.add_theme_font_size_override("font_size", 14)
	head.add_child(close_btn)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 240)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	props_body = VBoxContainer.new()
	props_body.add_theme_constant_override("separation", 4)
	props_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(props_body)

	# 专注模式下仍然留一个能点的小胶囊，免得鼠标用户没法把面板叫回来
	restore_btn = _mk_btn("▸ 面板", func(): toggle_panels())
	restore_btn.add_theme_font_size_override("font_size", 12)
	UITheme.apply_pill(restore_btn)
	restore_btn.position = Vector2(794, 514)
	restore_btn.custom_minimum_size = Vector2(96, 32)
	restore_btn.size = Vector2(96, 32)
	restore_btn.visible = false
	main.ui_layer.add_child(restore_btn)

# ================================================================ 进出编辑器

func open_with(lv: Dictionary, index: int) -> void:
	edit_level = LevelIO.normalize_level(lv)
	if edit_level.is_empty():
		edit_level = LevelIO.blank_level()
	original_index = index
	drag = null
	draft = null
	selected = null
	initial_snapshot = JSON.stringify(edit_level)
	enter()

func enter() -> void:
	opened = true
	# 回到编辑器 = 试玩结束，把试玩标记清掉（HUD 的「试玩模式」也一起收）
	main.testing = false
	main.world.hud_testing = false
	main.set_menu_visible(false)
	main.hide_overlay()
	main.hint.visible = false
	main.menu_btn.visible = false
	var bar_was_hidden := not bar.visible
	ui_hidden = false
	_sync_panels()
	if bar_was_hidden and bar.visible:
		UITheme.pop_in_free(bar, 0.22, 0.98, 16.0)
	if bar_was_hidden and props.visible:
		UITheme.pop_in_free(props, 0.22, 0.96, -12.0)
	name_edit.text = str(edit_level["name"])
	world.editor_mode = true
	world.editor_level = edit_level
	world.editor_draft = null
	world.editor_selected = null
	set_tool(tool)
	render_props()
	update_dirty()
	main.refresh_pause()

func exit() -> void:
	if opened and JSON.stringify(edit_level) != initial_snapshot:
		var dlg := ConfirmationDialog.new()
		dlg.title = "退出编辑器"
		dlg.dialog_text = "有未保存的改动，确定要退出吗？\n（可以先点「保存」）"
		dlg.ok_button_text = "放弃并退出"
		dlg.cancel_button_text = "继续编辑"
		dlg.confirmed.connect(func(): _exit_now())
		main.ui_layer.add_child(dlg)
		dlg.popup_centered()
		return
	_exit_now()

func force_close() -> void:
	if opened:
		_exit_now()

func _exit_now() -> void:
	main.hide_overlay()
	opened = false
	_sync_panels()
	world.editor_mode = false
	drag = null
	draft = null
	selected = null
	main.open_menu()

func test_play() -> void:
	# 试玩不会往关卡列表里塞副本，退出时回编辑器。
	# ★ 必须先把编辑器收起来（opened = false）：
	#   main.refresh_pause() 会把 editor.opened 当成「该暂停」，不收起来的话
	#   试玩进去是暂停的、球根本不动，而且 Esc 会被 editor.exit() 抢走。
	#   记住是从编辑器出来的这件事由 main.testing 负责，回来时 reopen() 即可。
	opened = false
	selected = null
	_sync_panels()
	world.editor_mode = false
	drag = null
	draft = null
	main.play_test(edit_level.duplicate(true))
	main.show_toast("试玩中，Esc 回到编辑器")

func reopen() -> void:
	enter()

func clear_level() -> void:
	edit_level = LevelIO.blank_level()
	selected = null
	world.editor_level = edit_level
	mark_dirty()
	render_props()

func save() -> void:
	var nm := name_edit.text.strip_edges().substr(0, 24)
	if nm == "":
		nm = "未命名关卡"
	edit_level["name"] = nm
	var copy: Dictionary = edit_level.duplicate(true)
	if original_index >= 0 and original_index < main.playlist.size():
		main.playlist[original_index] = copy
	else:
		main.playlist.append(copy)
		original_index = main.playlist.size() - 1
	var ok := LevelIO.save_levels(main.playlist)
	initial_snapshot = JSON.stringify(edit_level)
	update_dirty()
	main.build_menu()
	if ok:
		main.show_toast("已保存「%s」" % nm)
	else:
		main.show_toast("保存失败（无法写入 user://）")

func update_dirty() -> void:
	dirty_lbl.visible = JSON.stringify(edit_level) != initial_snapshot

func mark_dirty() -> void:
	update_dirty()

func set_tool(t: String) -> void:
	tool = t
	for id in tool_buttons:
		var b: Button = tool_buttons[id]
		UITheme.apply_toggle(b, id == t)
	world.set_ed_tool(t)
	world.queue_redraw()

# ================================================================ 鼠标

func canvas_pos(event: InputEventMouse) -> Vector2:
	# 用事件自带的坐标（已经过拉伸变换，就是 900×560 逻辑坐标）
	if event != null:
		return event.position
	return world.get_viewport().get_mouse_position()

## 点在工具栏 / 属性面板范围内 → 不算画布操作
func over_ui(p: Vector2) -> bool:
	if bar.visible and bar.get_global_rect().has_point(p):
		return true
	if props.visible and props.get_global_rect().has_point(p):
		return true
	# 专注模式下的小胶囊也算 UI，别在它底下画出平台来
	if restore_btn != null and restore_btn.visible and restore_btn.get_global_rect().has_point(p):
		return true
	return false

func snap_val(v: float) -> float:
	return roundf(v / 10.0) * 10.0 if snap else roundf(v)

func hit_test(p: Vector2) -> Variant:
	var lv := edit_level
	var items: Array = lv["items"]
	for i in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[i]
		var ty := str(it["type"])
		if ty == "coin" or ty == "portal" or ty == "checkpoint":
			var rr := float(it.get("r", 20.0)) + 4.0
			if p.distance_to(Vector2(float(it["x"]), float(it["y"]))) <= rr:
				return {"kind": "item", "index": i, "obj": it}
		else:
			if p.x >= float(it["x"]) and p.x <= float(it["x"]) + float(it["w"]) \
				and p.y >= float(it["y"]) and p.y <= float(it["y"]) + float(it["h"]):
				return {"kind": "item", "index": i, "obj": it}
	var sp: Dictionary = lv["spawn"]
	if p.distance_to(Vector2(float(sp["x"]), float(sp["y"]))) <= 22.0:
		return {"kind": "spawn", "index": -1, "obj": sp}
	var gl: Dictionary = lv["goal"]
	if p.distance_to(Vector2(float(gl["x"]), float(gl["y"]))) <= float(gl.get("r", 22.0)) + 5.0:
		return {"kind": "goal", "index": -1, "obj": gl}
	var spikes: Array = lv["spikes"]
	for i in range(spikes.size() - 1, -1, -1):
		var s: Dictionary = spikes[i]
		if p.x >= float(s["x"]) and p.x <= float(s["x"]) + float(s["w"]) \
			and p.y >= float(s["y"]) and p.y <= float(s["y"]) + float(s["h"]):
			return {"kind": "spike", "index": i, "obj": s}
	var plats: Array = lv["platforms"]
	for i in range(plats.size() - 1, -1, -1):
		var q: Dictionary = plats[i]
		if p.x >= float(q["x"]) and p.x <= float(q["x"]) + float(q["w"]) \
			and p.y >= float(q["y"]) and p.y <= float(q["y"]) + float(q["h"]):
			return {"kind": "platform", "index": i, "obj": q}
	return null

func remove_object(hit) -> void:
	if hit == null:
		return
	var kind := str(hit["kind"])
	var idx := int(hit["index"])
	if kind == "platform":
		(edit_level["platforms"] as Array).remove_at(idx)
	elif kind == "spike":
		(edit_level["spikes"] as Array).remove_at(idx)
	elif kind == "item":
		(edit_level["items"] as Array).remove_at(idx)
	else:
		return
	selected = null
	mark_dirty()
	render_props()

func on_mouse(mb: InputEventMouseButton) -> void:
	if not opened:
		return
	var p := canvas_pos(mb)
	if not mb.pressed:
		if mb.button_index == MOUSE_BUTTON_LEFT and draft != null:
			_finish_draft()
		drag = null
		world.queue_redraw()
		return

	if over_ui(p):
		return
	var hit = hit_test(p)
	if mb.button_index == MOUSE_BUTTON_RIGHT or tool == "erase":
		remove_object(hit)
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return

	if tool == "spawn":
		edit_level["spawn"]["x"] = snap_val(p.x)
		edit_level["spawn"]["y"] = snap_val(p.y)
		selected = {"kind": "spawn", "index": -1}
		mark_dirty()
		render_props()
		return
	if tool == "goal":
		edit_level["goal"]["x"] = snap_val(p.x)
		edit_level["goal"]["y"] = snap_val(p.y)
		selected = {"kind": "goal", "index": -1}
		mark_dirty()
		render_props()
		return
	if POINT_TOOLS.has(tool):
		var def: Dictionary = LevelIO.ITEM_DEFAULTS[tool]
		var item := {"type": tool, "x": snap_val(p.x), "y": snap_val(p.y), "r": float(def["r"])}
		(edit_level["items"] as Array).append(item)
		selected = {"kind": "item", "index": (edit_level["items"] as Array).size() - 1}
		mark_dirty()
		render_props()
		return
	if tool == "move":
		if hit != null:
			selected = {"kind": str(hit["kind"]), "index": int(hit["index"])}
			render_props()
			drag = {"hit": hit, "startX": p.x, "startY": p.y,
				"origX": float(hit["obj"]["x"]), "origY": float(hit["obj"]["y"])}
		else:
			selected = null
			render_props()
		return
	# 矩形类工具：拖出草稿
	draft = {"x0": snap_val(p.x), "y0": snap_val(p.y), "x1": snap_val(p.x), "y1": snap_val(p.y)}
	world.editor_draft = draft
	world.queue_redraw()

func on_motion(mm: InputEventMouseMotion) -> void:
	if not opened:
		return
	var p := canvas_pos(mm)
	world.editor_mouse = p
	if drag != null:
		var dx := p.x - float(drag["startX"])
		var dy := p.y - float(drag["startY"])
		var obj: Dictionary = drag["hit"]["obj"]
		obj["x"] = snap_val(float(drag["origX"]) + dx)
		obj["y"] = snap_val(float(drag["origY"]) + dy)
		mark_dirty()
		if selected != null and str(selected["kind"]) == "item":
			render_props()
		world.editor_selected = selected
		world.queue_redraw()
	elif draft != null:
		draft["x1"] = snap_val(p.x)
		draft["y1"] = snap_val(p.y)
		world.editor_draft = draft
		world.queue_redraw()

func _finish_draft() -> void:
	var d: Dictionary = draft
	draft = null
	world.editor_draft = null
	var x0: float = minf(float(d["x0"]), float(d["x1"]))
	var y0: float = minf(float(d["y0"]), float(d["y1"]))
	var w: float = absf(float(d["x1"]) - float(d["x0"]))
	var h: float = absf(float(d["y1"]) - float(d["y0"]))
	if tool == "platform":
		var pw: float = maxf(20.0, w)
		var ph: float = maxf(8.0, h if h > 4.0 else 18.0)
		(edit_level["platforms"] as Array).append({"x": x0, "y": y0, "w": pw, "h": ph})
		selected = {"kind": "platform", "index": (edit_level["platforms"] as Array).size() - 1}
	elif tool == "spike":
		var sw: float = maxf(16.0, w)
		var sh: float = maxf(12.0, h)
		(edit_level["spikes"] as Array).append({"x": x0, "y": y0, "w": sw, "h": sh, "dir": "up"})
		selected = {"kind": "spike", "index": (edit_level["spikes"] as Array).size() - 1}
	elif tool == "spring" or tool == "boost":
		var def: Dictionary = LevelIO.ITEM_DEFAULTS[tool]
		var iw: float = clampf(w if w > 8.0 else float(def["w"]), 16.0, 600.0)
		var ih: float = clampf(h if h > 4.0 else float(def["h"]), 10.0, 300.0)
		var item := {"type": tool, "x": x0, "y": y0, "w": iw, "h": ih, "power": float(def["power"])}
		if tool == "boost":
			item["dir"] = 1
		(edit_level["items"] as Array).append(item)
		selected = {"kind": "item", "index": (edit_level["items"] as Array).size() - 1}
	mark_dirty()
	render_props()
	world.queue_redraw()

# ================================================================ 属性面板

func get_selected_object() -> Variant:
	if selected == null:
		return null
	var kind := str(selected["kind"])
	var idx := int(selected["index"])
	if kind == "platform":
		var a: Array = edit_level["platforms"]
		return a[idx] if idx >= 0 and idx < a.size() else null
	if kind == "spike":
		var a2: Array = edit_level["spikes"]
		return a2[idx] if idx >= 0 and idx < a2.size() else null
	if kind == "item":
		var a3: Array = edit_level["items"]
		return a3[idx] if idx >= 0 and idx < a3.size() else null
	if kind == "spawn":
		return edit_level["spawn"]
	if kind == "goal":
		return edit_level["goal"]
	return null

func get_fields(kind: String, obj: Dictionary) -> Array:
	var xy := [
		{"key": "x", "label": "X", "min": -400.0, "max": 1400.0, "step": 1.0},
		{"key": "y", "label": "Y", "min": -400.0, "max": 1000.0, "step": 1.0},
	]
	if kind == "platform":
		return xy + [
			{"key": "w", "label": "宽", "min": 20.0, "max": 2400.0, "step": 1.0},
			{"key": "h", "label": "高", "min": 8.0, "max": 600.0, "step": 1.0},
		]
	if kind == "spike":
		return [{"key": "dir", "label": "朝向", "type": "dirgrid",
			"options": [{"v": "up", "t": "↑ 上"}, {"v": "down", "t": "↓ 下"},
				{"v": "left", "t": "← 左"}, {"v": "right", "t": "→ 右"}]}] + xy + [
			{"key": "w", "label": "宽", "min": 16.0, "max": 900.0, "step": 1.0},
			{"key": "h", "label": "高", "min": 12.0, "max": 400.0, "step": 1.0},
		]
	if kind == "spawn":
		return xy
	if kind == "goal":
		return xy + [{"key": "r", "label": "半径", "min": 10.0, "max": 60.0, "step": 1.0}]
	if kind == "item":
		var ty := str(obj.get("type", ""))
		if ty == "coin" or ty == "portal" or ty == "checkpoint":
			return xy + [{"key": "r", "label": "半径", "min": 6.0, "max": 90.0, "step": 1.0}]
		var size_fields := [
			{"key": "w", "label": "宽", "min": 16.0, "max": 600.0, "step": 1.0},
			{"key": "h", "label": "高", "min": 10.0, "max": 300.0, "step": 1.0},
			{"key": "power", "label": "力度", "min": 100.0, "max": 3000.0, "step": 10.0},
		]
		if ty == "boost":
			return [{"key": "dir", "label": "方向", "type": "dirgrid",
				"options": [{"v": 1, "t": "→ 向右"}, {"v": -1, "t": "← 向左"}]}] + xy + size_fields
		return xy + size_fields
	return xy

func render_props() -> void:
	for c in props_body.get_children():
		c.queue_free()
	var obj = get_selected_object()
	if obj == null:
		props_title.text = "属性"
		var tip := Label.new()
		tip.text = "没选中东西。\n用「移动」点选物件，\n或右键 / 橡皮删除。"
		tip.add_theme_font_size_override("font_size", 11)
		tip.add_theme_color_override("font_color", Color(160 / 255.0, 195 / 255.0, 245 / 255.0, 0.62))
		tip.add_theme_stylebox_override("normal", UITheme.flat(
			Color(30 / 255.0, 50 / 255.0, 100 / 255.0, 0.35), 7, 0, Color.TRANSPARENT, 9.0, 7.0))
		tip.add_theme_constant_override("line_spacing", 4)
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		props_body.add_child(tip)
		_sync_panels()      # ★ 这里 return 之前也要同步，否则取消选中后面板不会收起来
		return

	var kind := str(selected["kind"])
	var title: String = {"platform": "平台", "spike": "尖刺", "spawn": "起点", "goal": "终点", "item": "道具"}.get(kind, "属性")
	if kind == "item":
		title = str(LevelIO.ITEM_NAMES.get(str(obj.get("type", "")), "道具"))
	props_title.text = title

	for f in get_fields(kind, obj):
		props_body.add_child(_make_field(f, obj))
	world.editor_selected = selected
	world.queue_redraw()
	_sync_panels()

func _make_field(f: Dictionary, obj: Dictionary) -> Control:
	var key := str(f["key"])
	if str(f.get("type", "")) == "dirgrid":
		var wrap := VBoxContainer.new()
		var lbl := Label.new()
		lbl.text = str(f["label"])
		lbl.add_theme_font_size_override("font_size", 12)
		wrap.add_child(lbl)
		var grid := HBoxContainer.new()
		grid.add_theme_constant_override("separation", 4)
		wrap.add_child(grid)
		for opt in (f["options"] as Array):
			var b := _mk_btn(str(opt["t"]), func():
				obj[key] = opt["v"]
				mark_dirty()
				render_props()
			)
			b.custom_minimum_size = Vector2(52, 26)
			b.add_theme_font_size_override("font_size", 12)
			UITheme.apply_toggle(b, obj.get(key, null) == opt["v"])
			grid.add_child(b)
		return wrap

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var l := Label.new()
	l.text = str(f["label"])
	l.custom_minimum_size = Vector2(34, 0)
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(160 / 255.0, 195 / 255.0, 245 / 255.0, 0.72))
	row.add_child(l)
	var spin := SpinBox.new()
	spin.theme_type_variation = "PropSpin"
	spin.min_value = float(f["min"])
	spin.max_value = float(f["max"])
	spin.step = float(f["step"])
	spin.value = float(obj.get(key, 0.0))
	spin.custom_minimum_size = Vector2(140, 24)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(v: float):
		obj[key] = v
		mark_dirty()
		world.queue_redraw()
	)
	row.add_child(spin)
	return row
