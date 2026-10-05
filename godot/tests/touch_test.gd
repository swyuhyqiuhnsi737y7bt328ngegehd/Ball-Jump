extends SceneTree

var main
var fails := 0

func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await process_frame
	await process_frame

	print("=== 1. 仓库自带的示例关卡 ===")
	var samples := LevelIO.load_sample_levels()
	# 关卡会持续更新，所以只要求「至少有 6 张、每张都完整」，别把数量写死
	check("示例关卡读出来了（>=6）", samples.size() >= 6, true)
	var names := []
	for l in samples:
		names.append(str(l["name"]))
	print("  共 %d 张: %s" % [samples.size(), " / ".join(names)])
	var geo_ok := true
	for l in samples:
		if (l["spawn"] as Dictionary).is_empty() or (l["goal"] as Dictionary).is_empty():
			geo_ok = false
		if (l["platforms"] as Array).is_empty():
			geo_ok = false
	check("每关都有起点/终点/平台", geo_ok, true)
	check("名字都不是空的", names[0] != "" and names[5] != "", true)

	print("")
	print("=== 2. 触屏按键：多指同时按 ===")
	main.touch_enabled = true
	var lv: Dictionary = LevelIO.blank_level()
	lv["name"] = "触屏测试"
	lv["spawn"] = {"x": 200, "y": 380}
	lv["goal"] = {"x": 880, "y": 360, "r": 20}
	lv["platforms"] = [{"x": 0, "y": 400, "w": 900, "h": 60}]
	main.play_test(lv)
	main._process(1.0 / 120.0)
	check("玩的时候触屏键露出来", main.touch_ui.visible, true)

	var L: Vector2 = (main.touch_ui._rects["left"] as Rect2).get_center()
	var R: Vector2 = (main.touch_ui._rects["right"] as Rect2).get_center()
	var J: Vector2 = (main.touch_ui._rects["jump"] as Rect2).get_center()
	print("  按钮中心 左=%s 右=%s 跳=%s" % [str(L), str(R), str(J)])

	main.touch_ui._input(_touch(0, R, true))
	main._process(1.0 / 120.0)
	check("单指按右 → dir", main.world.touch_dir, 1)

	main.touch_ui._input(_touch(1, J, true))
	main._process(1.0 / 120.0)
	check("加上第二指按跳 → dir 不变", main.world.touch_dir, 1)
	check("加上第二指按跳 → jump", main.world.touch_jump, true)

	# 真正跑几帧，看球是不是真的往右跑并跳起来
	var x0: float = main.world.bx
	var min_vy := 0.0
	var peak_y: float = main.world.by
	for i in 60:
		main._process(1.0 / 120.0)
		min_vy = minf(min_vy, main.world.bvy)
		peak_y = minf(peak_y, main.world.by)
	check("球确实往右走了", main.world.bx > x0 + 20.0, true)
	check("跳跃确实起跳了（最高速 < -300）", min_vy < -300.0, true)
	check("球确实离地上升过", peak_y < main.world.by - 5.0, true)

	main.touch_ui._input(_touch(0, R, false))
	main._process(1.0 / 120.0)
	check("松开右 → dir 归零", main.world.touch_dir, 0)
	check("松开右 → 跳还按着", main.world.touch_jump, true)

	main.touch_ui._input(_touch(1, J, false))
	main._process(1.0 / 120.0)
	check("全松开 → jump 归零", main.world.touch_jump, false)

	main.touch_ui._input(_touch(2, L, true))
	main._process(1.0 / 120.0)
	check("按左 → dir=-1", main.world.touch_dir, -1)
	main.touch_ui._input(_touch(2, L, false))

	print("")
	print("=== 3. 手指划出按钮 = 松开 ===")
	main.touch_ui._input(_touch(3, R, true))
	main._process(1.0 / 120.0)
	check("按住右", main.world.touch_dir, 1)
	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = Vector2(450, 120)
	main.touch_ui._input(drag)
	main._process(1.0 / 120.0)
	check("划走后自动松开", main.world.touch_dir, 0)

	print("")
	print("=== 4. 菜单 / 编辑器里要收起来 ===")
	main.play_test(lv)
	for i in 3:
		main._process(1.0 / 120.0)
	check("试玩中触屏键在", main.touch_ui.visible, true)
	main.open_menu()
	main._process(1.0 / 120.0)
	check("菜单打开时隐藏", main.touch_ui.visible, false)
	check("隐藏时方向清零", main.world.touch_dir, 0)
	# 试玩时开菜单会结束这一局（level 清空），重新开一局
	main.play_test(lv)
	for i in 5:
		main._process(1.0 / 120.0)
	check("重新开局后又出现", main.touch_ui.visible, true)

	main.editor.open_with(lv, -1)
	main._process(1.0 / 120.0)
	check("编辑器里隐藏（别挡工具栏）", main.touch_ui.visible, false)

	print("")
	print("=== 5. 普通关卡：开菜单再关掉要能继续跑 ===")
	main.editor.force_close()
	await process_frame
	main._play_level(0)
	for i in 5:
		main._process(1.0 / 120.0)
	check("关卡在跑", main.playing, true)
	main.open_menu()
	main._process(1.0 / 120.0)
	check("开菜单后暂停", main.playing, false)
	main.close_menu()
	main._process(1.0 / 120.0)
	check("关菜单后恢复运行（close_menu 里那句 refresh_pause）", main.playing, true)

	main.touch_enabled = false

	print("")
	print("失败 %d 项 ❌" % fails if fails > 0 else "触屏 / 示例关卡自检全部通过 ✅")
	quit()

func _touch(index: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	return e

func check(name: String, got, want) -> void:
	var ok := str(got) == str(want)
	if ok:
		print("  ✅ %-30s %s" % [name, str(got)])
	else:
		fails += 1
		print("  ❌ %-30s 得到 %s，期望 %s" % [name, str(got), str(want)])
