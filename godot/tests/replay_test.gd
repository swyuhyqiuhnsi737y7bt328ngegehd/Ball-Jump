extends SceneTree

var main
var fails := 0

func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await process_frame
	await process_frame

	# ---------- 1. toast 能不能自己消失 ----------
	print("=== toast ===")
	main.show_toast("速度 1.50x")
	print("  刚弹: left=%.2f visible=%s" % [main.toast_left, str(main.toast.visible)])
	for i in 200:
		main._process(1.0 / 60.0)
	print("  走完 2.2 秒计时: left=%.2f" % main.toast_left)
	for i in 500:
		await process_frame
	print("  等淡出补间跑完: visible=%s a=%.2f" % [str(main.toast.visible), main.toast.modulate.a])
	check("toast 计时归零", main.toast_left <= 0.0, true)
	check("toast 最终隐藏", main.toast.visible, false)

	# ---------- 2. 死后复盘 ----------
	print("")
	print("=== 复盘 ===")
	var lv: Dictionary = LevelIO.normalize_level({
		"name": "复盘测试",
		"spawn": {"x": 100, "y": 160},
		"goal": {"x": 850, "y": 470, "r": 22},
		"platforms": [{"x": 0, "y": 520, "w": 900, "h": 40}],
		"spikes": [{"x": 60, "y": 470, "w": 780, "h": 50, "dir": "up"}],
		"items": [],
	})
	main.play_test(lv)
	print("  开始跑，球从 y=160 落到尖刺上…")
	var died_at := -1
	for i in 400:
		main._process(1.0 / 120.0)
		if main.replay_active and died_at < 0:
			died_at = i
			break
	check("死亡后自动弹出复盘", main.replay_active, true)
	check("录像有内容", main.world.rec_duration() >= 0.3, true)
	print("  %.2f 秒后死，录像长度 %.2f 秒" % [float(died_at) / 120.0, main.world.rec_duration()])

	var dur: float = main.world.rec_duration()
	main.world.replay_apply(0.0)
	var start_pos := Vector2(main.world.bx, main.world.by)
	main.world.replay_apply(dur)
	var end_pos := Vector2(main.world.bx, main.world.by)
	print("  回放起点 (%.0f, %.0f) → 终点 (%.0f, %.0f)" % [start_pos.x, start_pos.y, end_pos.x, end_pos.y])
	check("回放起点就是出生点", snappedf(start_pos.y, 1.0), 160.0, 2.0)
	check("回放终点就是死亡位置", end_pos.y > 400.0, true)

	# 倍速
	main._replay_set_speed(0.25)
	var t0: float = main.replay_t
	for i in 60:
		main._replay_tick(1.0 / 60.0)
	var slow: float = main.replay_t - t0
	main._replay_restart()
	main._replay_set_speed(2.0)
	t0 = main.replay_t
	for i in 60:
		main._replay_tick(1.0 / 60.0)
	var fast: float = main.replay_t - t0
	print("  1 秒实时：0.25× 走了 %.2f 秒，2× 走了 %.2f 秒" % [slow, fast])
	check("0.25× 播放约 1/4 速度", snappedf(slow, 0.01), 0.25, 0.03)
	# 录像只有 0.54 秒，2× 播 1 秒会播到结尾并自动暂停
	check("2× 播放会更快到达结尾", fast >= dur - 0.01, true)
	check("播到结尾自动暂停", main.replay_playing, false)

	main.close_replay()
	await process_frame
	check("关闭复盘", main.replay_active, false)
	check("关闭后球回到出生点", snappedf(main.world.by, 1.0), 160.0, 2.0)
	check("关闭后游戏恢复运行", main.playing, true)

	# ---------- 3. 通关也能复盘 ----------
	print("")
	print("=== 通关复盘 ===")
	var lv2: Dictionary = LevelIO.normalize_level({
		"name": "通关复盘测试",
		"spawn": {"x": 100, "y": 100},
		"goal": {"x": 100, "y": 440, "r": 26},
		"platforms": [{"x": 0, "y": 520, "w": 900, "h": 40}],
		"spikes": [],
		"items": [],
	})
	main.play_test(lv2)
	var won_at := -1
	for i in 400:
		main._process(1.0 / 120.0)
		if main.overlay.visible:
			won_at = i
			break
	check("碰到终点弹出通关浮层", main.overlay.visible, true)
	check("通关浮层上有复盘按钮", main.ov_replay_btn.visible, true)
	print("  %.2f 秒通关，这条录像 %.2f 秒" % [float(won_at) / 120.0, main.world.rec_duration_cur()])
	main.ov_replay_btn.pressed.emit()
	await process_frame
	check("点复盘后进入回放", main.replay_active, true)
	check("回放时收起通关浮层", main.overlay.visible, false)
	main.world.replay_apply(0.0)
	check("回放起点是出生点", snappedf(main.world.by, 1.0), 100.0, 2.0)
	main.world.replay_apply(main.world.rec_duration())
	check("回放终点就是通关位置", main.world.by > 380.0, true)
	main.close_replay()
	await process_frame
	check("看完回到通关浮层", main.overlay.visible, true)
	check("看完不再回放", main.replay_active, false)

	# ---------- 4. 拖尾必须是「最近 0.1 秒」，跟采样率无关 ----------
	print("")
	print("=== 拖尾时间窗口 ===")
	main.play_test(lv2)
	for i in 400:
		main._process(1.0 / 120.0)
		if main.overlay.visible:
			break
	main.ov_replay_btn.pressed.emit()
	await process_frame
	var W: Node = main.world

	# 同一时刻，用三种采样率跑过去，拖尾应该完全一样
	var trail_ref := []
	W.replay_apply(0.45)
	trail_ref = W.trail.duplicate()
	check("拖尾点数 = 12", W.trail.size(), 12)

	# 先用 30fps 一路跑，再用 12fps 一路跑，最后都补一帧到 0.45 —— 终点相同才能比
	W.trail.clear()
	for i in range(0, 14):
		W.replay_apply(float(i) / 30.0)
	W.replay_apply(0.45)
	var at30: Array = W.trail.duplicate()

	W.trail.clear()
	for i in range(0, 6):
		W.replay_apply(float(i) / 12.0)
	W.replay_apply(0.45)
	var at12: Array = W.trail.duplicate()

	check("30fps 采样后点数 = 12", at30.size(), 12)
	check("12fps 采样后点数 = 12", at12.size(), 12)
	var span30: float = (at30[0] as Vector2).distance_to(at30[at30.size() - 1])
	var span12: float = (at12[0] as Vector2).distance_to(at12[at12.size() - 1])
	print("  0.45 秒处拖尾跨度：30fps 采样 %.1f px，12fps 采样 %.1f px" % [span30, span12])
	check("两种采样率拖尾完全一致（差 < 0.5px）", absf(span30 - span12) < 0.5, true)
	# 12 个记录帧 = 11/120 ≈ 0.092 秒；此处自由落体约 1000px/s，所以跨度应该在 90px 上下
	check("跨度符合 0.092 秒的下落距离（40~150px）", span30 > 40.0 and span30 < 150.0, true)
	check("拖尾就等于调用次数无关的固定窗口", at30.size() == at12.size(), true)

	# 拖尾首点应该就是 11 帧之前的位置
	W.replay_apply(0.45)
	var tip: Vector2 = W.trail[0]
	var pos0: Vector2 = W.trail[W.trail.size() - 1]
	print("  拖尾首点 y=%.1f，末端 y=%.1f（球 y=%.1f）" % [tip.y, pos0.y, W.by])
	check("末端点就是球当前位置", snappedf(pos0.y, 1.0), snappedf(W.by, 1.0))
	main.close_replay()
	await process_frame

	# ---------- 5. 死后用键盘重生（不用动鼠标）----------
	print("")
	print("=== 键盘重生 ===")

	# 死一次
	main.play_test(lv)
	var dead1 := false
	for i in 600:
		main._process(1.0 / 120.0)
		if main.replay_active:
			dead1 = true
			break
	check("先死一次，复盘自动弹出", dead1, true)
	main._input(_key(KEY_SPACE))
	await process_frame
	check("空格 → 关闭复盘", main.replay_active, false)
	check("空格 → 游戏继续跑", main.playing, true)
	check("空格 → 球已回出生点", absf(main.world.by - 160.0) < 4.0, true)

	# 再死一次，这次用回车
	var dead2 := false
	for i in 600:
		main._process(1.0 / 120.0)
		if main.replay_active:
			dead2 = true
			break
	check("第二次也自动弹出", dead2, true)
	main._input(_key(KEY_ENTER))
	await process_frame
	check("回车 → 关闭复盘", main.replay_active, false)
	check("回车 → 游戏继续跑", main.playing, true)

	# 通关浮层上回车 = 点主按钮
	overlay_fired = false
	main.show_overlay("测试浮层", "内容", "确定", func(): overlay_fired = true)
	await process_frame
	main._input(_key(KEY_ENTER))
	await process_frame
	check("回车 → 触发浮层按钮", overlay_fired, true)
	check("回车 → 浮层收起", main.overlay.visible, false)

	# 平时空格还是跳跃键，不能被这段逻辑吃掉
	main.play_test(lv)
	main._process(1.0 / 120.0)
	check("平时按回车不误触（没弹窗时）", main.replay_active, false)
	check("平时仍处于游戏中", main.playing, true)

	# 按着跳键关弹窗，不该在重生瞬间起跳
	main.world.touch_jump = true
	main.world.sync_jump_state()
	check("按着跳时同步 _prev_jump", main.world._prev_jump, true)
	main.world.touch_jump = false
	main.world.sync_jump_state()
	check("松开后 _prev_jump 复位", main.world._prev_jump, false)

	print("")
	print("失败 %d 项 ❌" % fails if fails > 0 else "复盘 / toast 自检全部通过 ✅")
	quit()

var overlay_fired := false

func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e

func check(name: String, got, want, tol := 0.0) -> void:
	var ok := false
	if got is float and want is float:
		ok = absf(got - want) <= maxf(tol, 0.0001)
	else:
		ok = str(got) == str(want)
	if ok:
		print("  ✅ %-24s %s" % [name, str(got)])
	else:
		fails += 1
		print("  ❌ %-24s 得到 %s，期望 %s" % [name, str(got), str(want)])
