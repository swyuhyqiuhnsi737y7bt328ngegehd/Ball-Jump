extends SceneTree

var main
var fails := 0

func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await process_frame
	await process_frame

	var lv: Dictionary = LevelIO.blank_level()
	lv["name"] = "面板测试"
	lv["spawn"] = {"x": 100, "y": 400}
	lv["goal"] = {"x": 800, "y": 400, "r": 22}
	lv["platforms"] = [{"x": 200, "y": 300, "w": 200, "h": 20}]

	print("=== 1. 进编辑器时的初始状态 ===")
	main.editor.open_with(lv, -1)
	await process_frame
	check("编辑器打开", main.editor.opened, true)
	check("工具栏可见", main.editor.bar.visible, true)
	check("没选中东西时属性面板自动收起", main.editor.props.visible, false)
	check("恢复胶囊不显示", main.editor.restore_btn.visible, false)

	print("")
	print("=== 2. 选中物件才显示属性 ===")
	main.editor.selected = {"kind": "platform", "index": 0}
	main.editor.render_props()
	await process_frame
	check("选中平台 → 属性面板出现", main.editor.props.visible, true)
	main.editor.selected = null
	main.editor.render_props()
	await process_frame
	check("取消选中 → 属性面板收起", main.editor.props.visible, false)

	print("")
	print("=== 3. Tab 专注模式 ===")
	main._input(_key(KEY_TAB))
	await process_frame
	check("Tab → 工具栏收起", main.editor.bar.visible, false)
	check("Tab → 属性面板收起", main.editor.props.visible, false)
	check("Tab → 右下角出现恢复胶囊", main.editor.restore_btn.visible, true)
	check("按钮文字变成「展开面板」", main.editor.panel_toggle.text, "展开面板")

	# 收起状态下画布不能被 UI 挡住鼠标
	check("收起后画布点不被 UI 拦截", main.editor.over_ui(Vector2(300, 310)), false)
	check("收起后右下角胶囊自己不被当成画布", main.editor.over_ui(Vector2(840, 530)), true)

	main._input(_key(KEY_TAB))
	await process_frame
	check("再按 Tab → 工具栏回来", main.editor.bar.visible, true)
	check("再按 Tab → 胶囊消失", main.editor.restore_btn.visible, false)
	check("按钮文字变回「收起面板」", main.editor.panel_toggle.text, "收起面板")

	print("")
	print("=== 4. 用按钮切换（鼠标党）===")
	if main.editor.bar.visible:
		main.editor.panel_toggle.pressed.emit()
	else:
		main.editor.restore_btn.pressed.emit()
	await process_frame
	check("点按钮 → 收起", main.editor.bar.visible, false)
	main.editor.restore_btn.pressed.emit()
	await process_frame
	check("点胶囊 → 展开", main.editor.bar.visible, true)

	print("")
	print("=== 5. 试玩回来后依然正常 ===")
	main.editor.toggle_panels()
	await process_frame
	check("先收起", main.editor.bar.visible, false)
	main.editor.test_play()
	await process_frame
	check("试玩时编辑器面板都收着", main.editor.bar.visible, false)
	main.editor.reopen()
	await process_frame
	check("回到编辑器 → 工具栏回来", main.editor.bar.visible, true)
	check("回到编辑器 → 专注模式被重置", main.editor.ui_hidden, false)
	check("回到编辑器 → 胶囊不显示", main.editor.restore_btn.visible, false)

	main.editor.exit()
	await process_frame

	print("")
	print("失败 %d 项 ❌" % fails if fails > 0 else "编辑器面板自检全部通过 ✅")
	quit()

func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e

func _click(pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = pos
	e.pressed = true
	return e

func check(name: String, got, want) -> void:
	var ok := str(got) == str(want)
	if ok:
		print("  ✅ %-32s %s" % [name, str(got)])
	else:
		fails += 1
		print("  ❌ %-32s 得到 %s，期望 %s" % [name, str(got), str(want)])
