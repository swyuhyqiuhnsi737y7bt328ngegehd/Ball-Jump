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

	print("")
	print("失败 %d 项 ❌" % fails if fails > 0 else "复盘 / toast 自检全部通过 ✅")
	quit()

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
