extends SceneTree

## 编辑器鼠标自检：放置 / 拖动 / 擦除 / 别在工具栏上误画
## （不碰存档，只在内存里改）

var main
var ed

func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await process_frame
	main._new_level()
	await process_frame
	ed = main.editor
	var fails := 0
	fails += check("新建关卡打开了编辑器", ed.opened, true)
	fails += check("新建关卡是空关卡（1 块地板）", (ed.edit_level["platforms"] as Array).size(), 1)

	# 拖一块平台
	ed.set_tool("platform")
	drag(Vector2(120, 300), Vector2(320, 330))
	fails += check("拖拽能画出平台", (ed.edit_level["platforms"] as Array).size(), 2)
	fails += check("平台尺寸正确", str((ed.edit_level["platforms"] as Array)[1]),
		'{ "x": 120.0, "y": 300.0, "w": 200.0, "h": 30.0 }')

	# 点一个金币
	ed.set_tool("coin")
	click(Vector2(500, 200))
	fails += check("点一下能放金币", (ed.edit_level["items"] as Array).size(), 1)

	# 工具栏 / 属性面板上不该误画
	var bp := (ed.edit_level["platforms"] as Array).size()
	ed.set_tool("platform")
	drag(Vector2(58, 483), Vector2(300, 483))
	fails += check("在工具栏上拖不会误画", (ed.edit_level["platforms"] as Array).size(), bp)

	var bs := (ed.edit_level["spikes"] as Array).size()
	ed.set_tool("spike")
	drag(Vector2(750, 60), Vector2(820, 220))
	fails += check("在属性面板上拖不会误画", (ed.edit_level["spikes"] as Array).size(), bs)

	# 拖动物件
	ed.set_tool("move")
	drag(Vector2(200, 315), Vector2(250, 365))
	fails += check("移动工具能拖动物件", "%.0f,%.0f" % [
		float((ed.edit_level["platforms"] as Array)[1]["x"]), float((ed.edit_level["platforms"] as Array)[1]["y"])], "170,350")

	# 右键擦除
	var n := (ed.edit_level["platforms"] as Array).size()
	right_click(Vector2(250, 365))
	fails += check("右键能擦除", (ed.edit_level["platforms"] as Array).size(), n - 1)

	# 不应该动到玩家的存档
	fails += check("自检没写存档（关卡数不变）", main.playlist.size(), LevelIO.load_levels().size())

	print("")
	if fails == 0:
		print("编辑器自检全部通过 ✅")
	else:
		print("失败 %d 项 ❌" % fails)
	quit()

func check(name: String, got, want) -> int:
	if str(got) == str(want):
		print("  ✅ %-30s %s" % [name, str(got)])
		return 0
	print("  ❌ %-30s 得到 %s，期望 %s" % [name, str(got), str(want)])
	return 1

func ev_btn(p: Vector2, pressed: bool, right := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT if right else MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = p
	main._unhandled_input(e)
func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	main._unhandled_input(e)
func drag(a: Vector2, b: Vector2) -> void:
	ev_btn(a, true); ev_move(b); ev_btn(b, false)
func click(p: Vector2) -> void:
	ev_btn(p, true); ev_btn(p, false)
func right_click(p: Vector2) -> void:
	ev_btn(p, true, true)
