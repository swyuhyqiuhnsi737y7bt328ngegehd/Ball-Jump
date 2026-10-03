extends SceneTree

## 无头物理自检：验证移植后的数值和网页版一致

const FIXED := 1.0 / 120.0

var world: World
var failures := 0

func _initialize() -> void:
	world = World.new()
	get_root().add_child(world)

	print("=== 弹球闯关 Godot 版 · 物理自检 ===")
	_test_free_fall()
	_test_landing()
	_test_jump_height()
	_test_spikes()
	_test_coin_and_checkpoint()
	_test_portal()
	_test_spring()
	_test_goal()
	_test_level_io()

	print("")
	if failures == 0:
		print("全部通过 ✅")
	else:
		print("失败 %d 项 ❌" % failures)
	quit()

func _mk_level(extra := {}) -> Dictionary:
	var lv := LevelIO.blank_level()
	lv["spawn"] = {"x": 100.0, "y": 100.0}
	lv["platforms"] = [{"x": 0.0, "y": 500.0, "w": 900.0, "h": 40.0}]
	lv["goal"] = {"x": 860.0, "y": 470.0, "r": 22.0}
	lv["spikes"] = []
	lv["items"] = []
	for k in extra:
		lv[k] = extra[k]
	return lv

func _run(seconds: float) -> void:
	var n := int(seconds / FIXED)
	for i in n:
		world.step(FIXED)
		world.update_effects(FIXED)

func _check(name: String, got, want, tol := 0.5) -> void:
	var ok := false
	if got is float and want is float:
		ok = absf(got - want) <= tol
	else:
		ok = str(got) == str(want)
	if ok:
		print("  ✅ %-28s %s" % [name, str(got)])
	else:
		failures += 1
		print("  ❌ %-28s 得到 %s，期望 %s" % [name, str(got), str(want)])

# 1) 自由落体（120Hz 半隐式欧拉）+ 终端速度
func _test_free_fall() -> void:
	world.load_level(_mk_level())
	world.current_spawn = Vector2(100, 100)
	world.reset_ball()
	_run(0.4)
	# 解析解 g·dt²·Σn = 2200*(1/120)^2*(48*49/2) = 179.67
	_check("自由落体 0.4 秒后 y", snappedf(world.by, 0.01), 279.67, 0.05)
	_run(0.2)
	_check("终端速度上限 MAX_FALL", world.bvy, 1050.0, 0.001)

# 2) 落地静止
func _test_landing() -> void:
	world.load_level(_mk_level())
	world.current_spawn = Vector2(100, 100)
	world.reset_ball()
	_run(2.0)
	_check("落地后 y（平台顶 - 半径）", snappedf(world.by, 0.01), 500.0 - 14.0, 0.05)
	_check("落地后 on_ground", world.on_ground, true)
	_check("落地后 vy", world.bvy, 0.0, 0.001)

# 3) 跳跃高度 = v²/2g
func _test_jump_height() -> void:
	world.load_level(_mk_level())
	world.current_spawn = Vector2(100, 480)
	world.reset_ball()
	_run(1.0)                     # 先站稳
	var base := world.by
	world.jump_pressed = true      # 模拟按下跳跃
	var apex := base
	for i in 240:
		world.step(FIXED)
		world.update_effects(FIXED)
		if world.by < apex:
			apex = world.by
	# 离散积分的顶点 ≈ v²/2g + v·dt/2 = 152.83 + 3.42
	_check("跳跃最高点高度", snappedf(base - apex, 0.1), 156.25, 0.6)

# 4) 尖刺致死
func _test_spikes() -> void:
	var lv := _mk_level({"spikes": [{"x": 0.0, "y": 460.0, "w": 900.0, "h": 40.0, "dir": "up"}]})
	lv["spawn"] = {"x": 100.0, "y": 300.0}
	world.load_level(lv)
	_run(1.5)
	_check("掉到尖刺上会死（回到出生点）", world.by, 300.0, 60.0)

# 5) 金币 + 存档点
func _test_coin_and_checkpoint() -> void:
	var lv := _mk_level({
		"items": [
			{"type": "coin", "x": 100.0, "y": 300.0, "r": 13.0},
			{"type": "checkpoint", "x": 200.0, "y": 470.0, "r": 22.0},
		],
		"spawn": {"x": 100.0, "y": 200.0},
	})
	world.load_level(lv)
	_check("金币总数", world.coins_total, 1)
	_run(0.6)
	_check("吃到金币", world.coins_got, 1)

# 6) 传送门
func _test_portal() -> void:
	var lv := _mk_level({
		"items": [
			{"type": "portal", "x": 100.0, "y": 300.0, "r": 24.0},
			{"type": "portal", "x": 700.0, "y": 300.0, "r": 24.0},
		],
		"spawn": {"x": 100.0, "y": 260.0},
	})
	world.load_level(lv)
	_check("传送门配对数", world.portal_pairs.size(), 1)
	_run(0.5)
	_check("被传送到 B 门附近", snappedf(world.bx, 1.0) > 600.0, true)

# 7) 弹簧
func _test_spring() -> void:
	var lv := _mk_level({
		"items": [{"type": "spring", "x": 60.0, "y": 470.0, "w": 42.0, "h": 18.0, "power": 1180.0, "r": 0.0}],
		"spawn": {"x": 80.0, "y": 300.0},
	})
	world.load_level(lv)
	var min_y := 9999.0
	for i in 300:
		world.step(FIXED)
		if world.by < min_y:
			min_y = world.by
	_check("弹簧把人弹到 152+ 高度", min_y < 470.0 - 152.0, true)

# 8) 终点判定
func _test_goal() -> void:
	var lv := _mk_level({"goal": {"x": 150.0, "y": 460.0, "r": 22.0}, "spawn": {"x": 150.0, "y": 470.0}})
	var won := [false]
	world.level_won.connect(func(): won[0] = true)
	world.load_level(lv)
	_run(1.0)
	_check("碰到终点会触发通关", won[0], true)

# 9) 关卡数据往返
func _test_level_io() -> void:
	var raw := {
		"name": "测试关卡",
		"spawn": {"x": 50, "y": 400},
		"goal": {"x": 800, "y": 400, "r": 22},
		"platforms": [{"x": 0, "y": 500, "w": 900, "h": 40}, {"x": 100, "y": 300, "w": 120, "h": 16}],
		"spikes": [{"x": 400, "y": 460, "w": 40, "h": 40, "dir": "up"}, {"x": 500, "y": 100, "w": 40, "h": 40, "dir": "down"}],
		"items": [
			{"type": "coin", "x": 300, "y": 400, "r": 13},
			{"type": "spring", "x": 200, "y": 480, "w": 42, "h": 18, "power": 1180},
			{"type": "boost", "x": 600, "y": 480, "w": 130, "h": 22, "power": 540, "dir": -1},
			{"type": "portal", "x": 700, "y": 300, "r": 24},
		],
	}
	var lv := LevelIO.normalize_level(raw)
	_check("关卡名", str(lv["name"]), "测试关卡")
	_check("平台数", (lv["platforms"] as Array).size(), 2)
	_check("尖刺数", (lv["spikes"] as Array).size(), 2)
	_check("道具数", (lv["items"] as Array).size(), 4)
	_check("boost.dir 保留 -1", int((lv["items"] as Array)[2]["dir"]), -1)
	var round_trip := LevelIO.normalize_level(JSON.parse_string(JSON.stringify(lv)))
	_check("JSON 往返后完全一致", JSON.stringify(round_trip) == JSON.stringify(lv), true)
	# 越界会被夹住
	var clamp_lv := LevelIO.normalize_level({"name": "x", "platforms": [{"x": 99999, "y": -99999, "w": 1, "h": 99999}]})
	_check("x 被夹到 1800", float((clamp_lv["platforms"] as Array)[0]["x"]), 1800.0)
	_check("h 被夹到 600", float((clamp_lv["platforms"] as Array)[0]["h"]), 600.0)
