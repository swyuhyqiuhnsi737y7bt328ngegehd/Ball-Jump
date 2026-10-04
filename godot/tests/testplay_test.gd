extends SceneTree

var main
var fails := 0

func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await process_frame
	await process_frame

	# 造一个「一步就能通关」的关卡：终点就放在出生点旁边
	var lv: Dictionary = LevelIO.blank_level()
	lv["name"] = "试玩用关卡"
	# 出生点正下方就是终点：球一落下去就通关，不用操作
	lv["spawn"] = {"x": 200, "y": 240}
	lv["goal"] = {"x": 200, "y": 380, "r": 26}
	lv["platforms"] = [{"x": 0, "y": 500, "w": 900, "h": 40}]

	print("=== 1. 进编辑器 → 试玩 → 通关 → 回编辑器 ===")
	main.editor.open_with(lv, -1)
	await process_frame
	check("编辑器已打开", main.editor.opened, true)
	check("编辑器打开时不是 playing", main.playing, false)

	main.editor.test_play()
	await process_frame
	print("  testing=%s  hud_testing=%s  playing=%s" % [str(main.testing), str(main.world.hud_testing), str(main.playing)])
	check("试玩中 testing", main.testing, true)
	check("试玩中 HUD 标记", main.world.hud_testing, true)
	check("试玩时游戏在跑", main.playing, true)

	var won := false
	for i in 600:
		main._process(1.0 / 120.0)
		if main.overlay.visible:
			won = true
			break
	check("碰到终点后弹浮层", won, true)
	print("  浮层标题 = %s" % main.ov_title.text)
	print("  主按钮 = %s" % main.ov_btn.text)
	print("  复盘按钮可见 = %s" % str(main.ov_replay_btn.visible))
	check("是「试玩通关」", main.ov_title.text.contains("试玩"), true)
	check("按钮是「回到编辑器」", main.ov_btn.text, "回到编辑器")

	main.ov_btn.pressed.emit()
	await process_frame
	await process_frame
	print("  回到编辑器后: editor.opened=%s editor_mode=%s playing=%s testing=%s hud_testing=%s" % [
		str(main.editor.opened), str(main.world.editor_mode), str(main.playing),
		str(main.testing), str(main.world.hud_testing)])
	check("回到编辑器", main.editor.opened, true)
	check("世界回到编辑器模式", main.world.editor_mode, true)
	check("回到编辑器后暂停", main.playing, false)
	check("浮层已收起", main.overlay.visible, false)
	check("testing 应该复位", main.testing, false)
	check("hud_testing 应该复位", main.world.hud_testing, false)
	check("工具栏可见", main.editor.bar.visible, true)

	print("")
	print("=== 2. 试玩中按 Esc ===")
	main.editor.test_play()
	await process_frame
	main._input(_key(KEY_ESCAPE))
	await process_frame
	check("Esc 后回编辑器", main.editor.opened, true)
	check("Esc 后 testing 复位", main.testing, false)
	check("Esc 后 hud_testing 复位", main.world.hud_testing, false)

	print("")
	print("=== 3. 试玩中死掉（会自动弹复盘）===")
	var lv2: Dictionary = LevelIO.blank_level()
	lv2["name"] = "试玩会死"
	lv2["spawn"] = {"x": 200, "y": 200}
	lv2["goal"] = {"x": 850, "y": 500, "r": 20}
	lv2["platforms"] = [{"x": 0, "y": 520, "w": 900, "h": 40}]
	lv2["spikes"] = [{"x": 0, "y": 470, "w": 900, "h": 50, "dir": "up"}]
	main.editor.edit_level = LevelIO.normalize_level(lv2)
	main.editor.test_play()
	await process_frame
	var died := false
	for i in 600:
		main._process(1.0 / 120.0)
		if main.replay_active:
			died = true
			break
	check("死后自动复盘", died, true)
	check("复盘时 testing 还是 true", main.testing, true)
	main.close_replay()
	await process_frame
	check("关闭复盘后回到试玩", main.testing, true)
	check("关闭复盘后还在跑", main.playing, true)
	check("关闭复盘后球在出生点", absf(main.world.by - 200.0) < 3.0, true)

	print("")
	print("失败 %d 项 ❌" % fails if fails > 0 else "试玩流程自检全部通过 ✅")
	quit()

func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e

func check(name: String, got, want) -> void:
	var ok := str(got) == str(want)
	if ok:
		print("  ✅ %-26s %s" % [name, str(got)])
	else:
		fails += 1
		print("  ❌ %-26s 得到 %s，期望 %s" % [name, str(got), str(want)])
