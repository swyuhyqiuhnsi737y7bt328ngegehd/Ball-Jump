class_name World
extends Node2D

## 世界：物理模拟 + 全部画面绘制
## 对应 cd.html 里的 update / updateItems / updateEffects / draw* 系列

signal ball_died
signal level_won

const W := 900.0
const H := 560.0

# ---- 物理常量（与网页版完全一致）----
const GRAVITY := 2200.0
const MOVE_MAX := 340.0
const MOVE_ACC := 3200.0
const MOVE_DEC := 2800.0
const JUMP_V := 820.0
const JUMP_V2 := 760.0
const MAX_FALL := 1050.0
const COYOTE := 0.10
const JUMP_BUF := 0.12

# ---- 球 ----
var bx := 0.0
var by := 0.0
var bvx := 0.0
var bvy := 0.0
var br := 14.0

# ---- 关卡与运行时状态 ----
var level: Dictionary = {}
var on_ground := false
var coyote := 0.0
var jump_buffer := 0.0
var jumps_left := 2
var jump_pressed := false
var level_time := 0.0
var shake_time := 0.0
var jump_restore_fx := 0.0

var coins_taken := {}
var coins_total := 0
var coins_got := 0
var portal_pairs: Array = []
var portal_cd := 0.0

var current_spawn := Vector2.ZERO
var active_checkpoint := -1

var particles: Array = []
var trail: Array = []

var _prev_jump := false
var _time := 0.0
var _ed_tool := "platform"

# ---- HUD 共享状态（由 Main 填写）----
var hud_deaths := 0
var hud_level_index := 0
var hud_playlist_len := 0
var hud_frozen := false
var hud_time_scale := 1.0
var hud_testing := false
## 触屏虚拟键状态（由 TouchUI 每帧写入）
var touch_dir := 0
var touch_jump := false
var hud_steps := 0

# ---- 编辑器共享状态 ----
var editor_mode := false
var editor_level: Dictionary = {}
var editor_draft = null
var editor_selected = null
var editor_mouse := Vector2(-999, -999)

# ---- 绘制资源 ----
var font: Font
var _sb_plat: StyleBoxFlat
var _stars: Array = []
var _glow_tex: GradientTexture2D
var _bg_tex: GradientTexture2D
var _ball_tex: ImageTexture
var _coin_tex: ImageTexture

func _ready() -> void:
	_rec_init()
	_sb_plat = StyleBoxFlat.new()
	_sb_plat.draw_center = false          # 只借它画阴影，本体用渐变多边形
	_sb_plat.bg_color = Color("3d55bd")
	_sb_plat.shadow_color = Color(0.31, 0.55, 1.0, 0.35)
	_sb_plat.shadow_size = 10
	_sb_plat.shadow_offset = Vector2(0, 5)
	# 平滑的径向渐变贴图（同心圆会有色带）
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	_glow_tex = GradientTexture2D.new()
	_glow_tex.gradient = grad
	_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_glow_tex.fill_from = Vector2(0.5, 0.5)
	_glow_tex.fill_to = Vector2(0.5, 0.0)
	_glow_tex.width = 128
	_glow_tex.height = 128
	# 背景竖直渐变也只建一次（在 _draw 里建纹理会来不及上传，画出来是空白）
	var bg := Gradient.new()
	bg.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	bg.colors = PackedColorArray([Color("0b1026"), Color("141c3d"), Color("1d2757")])
	_bg_tex = GradientTexture2D.new()
	_bg_tex.gradient = bg
	_bg_tex.fill = GradientTexture2D.FILL_LINEAR
	_bg_tex.fill_from = Vector2(0, 0)
	_bg_tex.fill_to = Vector2(0, 1)
	_bg_tex.width = 8
	_bg_tex.height = 512
	# 球：渐变圆心往左上偏 (5,6)、渐变半径 = 球半径，色标 #fffbe6 → #ffd75e → #f59e0b
	# 贴图覆盖 ±22px，沿球心半径 14 裁成圆形（带 1px 羽化）
	_ball_tex = _make_radial(128, [[0.0, Color("fffbe6")], [0.42, Color("ffd75e")], [1.0, Color("f59e0b")]],
		Vector2(0.5 - 5.0 / 44.0, 0.5 - 6.0 / 44.0), 14.0 / 44.0, Vector2(0.5, 0.5), 14.0 / 44.0, 1.0 / 44.0)
	# 金币：圆心偏左上 (-0.35r, -0.4r)
	_coin_tex = _make_radial(128, [[0.0, Color("fffbe6")], [0.45, Color("ffd75e")], [1.0, Color("e0a010")]],
		Vector2(0.5 - 0.35 * 0.5, 0.5 - 0.4 * 0.5), 0.5, Vector2(0.5, 0.5), 0.5, 0.008)
	randomize()
	for i in 110:
		_stars.append({
			"x": randf() * W, "y": randf() * H,
			"r": randf() * 1.5 + 0.3,
			"a": randf() * 0.5 + 0.15,
			"ph": randf() * TAU,
		})

# ================================================================ 关卡装载

func load_level(lv: Dictionary) -> void:
	level = lv
	particles.clear()
	trail.clear()
	level_time = 0.0
	jump_restore_fx = 0.0
	coins_taken = {}
	coins_total = 0
	coins_got = 0
	portal_pairs = []
	portal_cd = 0.0
	active_checkpoint = -1
	current_spawn = Vector2(float(lv["spawn"]["x"]), float(lv["spawn"]["y"]))
	rec_reset()

	var portals: Array = []
	for i in (lv["items"] as Array).size():
		var it: Dictionary = lv["items"][i]
		if it["type"] == "coin":
			coins_total += 1
		elif it["type"] == "portal":
			portals.append(it)
	var k := 0
	while k + 1 < portals.size():
		portal_pairs.append([portals[k], portals[k + 1]])
		k += 2

	reset_ball()
	queue_redraw()

func clear_level() -> void:
	level = {}
	queue_redraw()

func reset_ball() -> void:
	if level.is_empty():
		return
	bx = current_spawn.x
	by = current_spawn.y
	bvx = 0.0
	bvy = 0.0
	on_ground = false
	coyote = 0.0
	jump_buffer = 0.0
	jumps_left = 2
	jump_pressed = false
	trail.clear()
	portal_cd = 0.0
	_rec_mark_life()

func die() -> void:
	rec_snapshot_death()          # 先把这条命的录像定格，再复活
	spawn_particles(bx, by, Color("ff4d6d"), 26)
	shake_time = 0.22
	reset_ball()
	ball_died.emit()

# ================================================================ 碰撞工具

func _aabb_hit(p: Dictionary) -> bool:
	return bx + br > float(p["x"]) and bx - br < float(p["x"]) + float(p["w"]) \
		and by + br > float(p["y"]) and by - br < float(p["y"]) + float(p["h"])

func _ball_in_rect(r: Dictionary) -> bool:
	return bx + br > float(r["x"]) and bx - br < float(r["x"]) + float(r["w"]) \
		and by + br > float(r["y"]) and by - br < float(r["y"]) + float(r["h"])

func _ball_in_circle(c: Dictionary) -> bool:
	var dx := bx - float(c["x"])
	var dy := by - float(c["y"])
	var rr := br + float(c.get("r", 20.0)) * 0.92
	return dx * dx + dy * dy < rr * rr

func spike_hit_rect(s: Dictionary) -> Rect2:
	var dir := str(s.get("dir", "up"))
	var m := 4.0
	var t := 7.0
	var x := float(s["x"])
	var y := float(s["y"])
	var w := float(s["w"])
	var h := float(s["h"])
	if dir == "down":
		return Rect2(x + m, y, w - m * 2.0, h - t)
	if dir == "left":
		return Rect2(x + t, y + m, w - t, h - m * 2.0)
	if dir == "right":
		return Rect2(x, y + m, w - t, h - m * 2.0)
	return Rect2(x + m, y + t, w - m * 2.0, h - t)

# ================================================================ 物理步进

func step(dt: float) -> void:
	if level.is_empty():
		return
	level_time += dt
	if jump_restore_fx > 0.0:
		jump_restore_fx = maxf(0.0, jump_restore_fx - dt)

	# ---- 读取输入：键盘 + 触屏虚拟键 ----
	var dir := clampi(touch_dir, -1, 1)
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		dir -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir += 1
	dir = clampi(dir, -1, 1)
	var jump_now := touch_jump or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W)
	if jump_now and not _prev_jump:
		jump_pressed = true
	if _prev_jump and not jump_now and bvy < -260.0:
		bvy = -260.0
	_prev_jump = jump_now

	# ---- 加速带 / 左右移动 ----
	var boost_zone: Dictionary = {}
	for it in (level["items"] as Array):
		if it["type"] == "boost" and _ball_in_rect(it):
			boost_zone = it
			break

	if not boost_zone.is_empty():
		var tgt := float(boost_zone["dir"]) * float(boost_zone["power"])
		var rate := 4600.0 * dt
		if tgt > bvx:
			bvx = minf(tgt, bvx + rate)
		elif tgt < bvx:
			bvx = maxf(tgt, bvx - rate)
		if dir != 0 and signi(dir) != signi(int(boost_zone["dir"])):
			bvx -= float(dir) * 900.0 * dt
	else:
		var target := float(dir) * MOVE_MAX
		var acc := MOVE_ACC if dir != 0 else MOVE_DEC
		if bvx < target:
			bvx = minf(target, bvx + acc * dt)
		else:
			bvx = maxf(target, bvx - acc * dt)

	# ---- 重力 / 土狼时间 / 跳跃缓冲 ----
	bvy += GRAVITY * dt
	if bvy > MAX_FALL:
		bvy = MAX_FALL

	if on_ground:
		coyote = COYOTE
		jumps_left = 2
	else:
		coyote = maxf(0.0, coyote - dt)

	if jump_pressed:
		jump_buffer = JUMP_BUF
		jump_pressed = false
	else:
		jump_buffer = maxf(0.0, jump_buffer - dt)

	if jump_buffer > 0.0:
		if coyote > 0.0:
			bvy = -JUMP_V
			coyote = 0.0
			jump_buffer = 0.0
			jumps_left = 1
			on_ground = false
			spawn_particles(bx, by + br, Color("7dd3fc"), 8)
		elif jumps_left > 0:
			bvy = -JUMP_V2
			jumps_left = 0
			jump_buffer = 0.0
			spawn_particles(bx, by + br, Color("a78bfa"), 12)

	# ---- 横向 ----
	bx += bvx * dt
	for p in (level["platforms"] as Array):
		if _aabb_hit(p):
			if bvx > 0.0:
				bx = float(p["x"]) - br
			elif bvx < 0.0:
				bx = float(p["x"]) + float(p["w"]) + br
			bvx = 0.0

	# ---- 纵向 ----
	by += bvy * dt
	on_ground = false
	for p in (level["platforms"] as Array):
		if _aabb_hit(p):
			if bvy >= 0.0:
				by = float(p["y"]) - br
				bvy = 0.0
				on_ground = true
			else:
				by = float(p["y"]) + float(p["h"]) + br
				bvy = 0.0

	# 录像：在危险判定之前记一帧，这样死亡位置本身就是最后一帧
	_rec_push()

	_update_items(dt)

	# ---- 尖刺 ----
	for s in (level["spikes"] as Array):
		var rect := spike_hit_rect(s)
		var r := br * 0.72
		if bx + r > rect.position.x and bx - r < rect.position.x + rect.size.x \
			and by + r > rect.position.y and by - r < rect.position.y + rect.size.y:
			die()
			return

	# ---- 掉出画面 ----
	if by > H + 140.0 or bx < -260.0 or bx > W + 260.0:
		die()
		return

	# ---- 终点 ----
	var dx := bx - float(level["goal"]["x"])
	var dy := by - float(level["goal"]["y"])
	var rr := br + float(level["goal"].get("r", 22.0))
	if dx * dx + dy * dy < rr * rr:
		_on_win()
		return

	trail.append(Vector2(bx, by))
	if trail.size() > 12:
		trail.pop_front()

func _update_items(dt: float) -> void:
	var items: Array = level["items"]

	for i in items.size():
		var it: Dictionary = items[i]
		if it["type"] == "coin" and not coins_taken.has(i) and _ball_in_circle(it):
			coins_taken[i] = true
			coins_got += 1
			spawn_particles(float(it["x"]), float(it["y"]), Color("ffe066"), 16)
			spawn_particles(float(it["x"]), float(it["y"]), Color("fffbe6"), 6)
		if it["type"] == "checkpoint" and _ball_in_circle(it):
			if active_checkpoint != i:
				active_checkpoint = i
				var r := float(it.get("r", 22.0))
				current_spawn = Vector2(float(it["x"]), float(it["y"]) - r - 8.0)
				spawn_particles(float(it["x"]), float(it["y"]), Color("4ade80"), 18)
				spawn_particles(float(it["x"]), float(it["y"]), Color("86efac"), 10)

	for it in items:
		if it["type"] != "spring":
			continue
		if not _ball_in_rect(it):
			continue
		if bvy < 0.0:
			continue
		if by > float(it["y"]) + float(it["h"]) * 0.75:
			continue
		by = float(it["y"]) - br
		bvy = -float(it["power"])
		on_ground = false
		coyote = 0.0
		jump_buffer = 0.0
		jumps_left = 1
		spawn_particles(float(it["x"]) + float(it["w"]) * 0.5, float(it["y"]), Color("c4b5fd"), 16)
		spawn_particles(float(it["x"]) + float(it["w"]) * 0.5, float(it["y"]), Color("a78bfa"), 8)

	if portal_cd > 0.0:
		portal_cd -= dt
	if portal_cd <= 0.0 and portal_pairs.size() > 0:
		for pair in portal_pairs:
			var a: Dictionary = pair[0]
			var b: Dictionary = pair[1]
			if _ball_in_circle(a):
				_do_teleport(a, b)
				break
			if _ball_in_circle(b):
				_do_teleport(b, a)
				break

func _do_teleport(from: Dictionary, to: Dictionary) -> void:
	spawn_particles(bx, by, Color("c084fc"), 18)
	bx = float(to["x"])
	by = float(to["y"]) - br * 0.2
	bvx *= 0.35
	bvy = minf(bvy * 0.35, 0.0)
	trail.clear()
	portal_cd = 0.55
	jumps_left = 1
	coyote = 0.0
	jump_buffer = 0.0
	jump_restore_fx = 0.55
	spawn_particles(bx, by, Color("e9d5ff"), 18)
	for k in 10:
		var a := (float(k) / 10.0) * TAU
		var sp := 90.0 + randf() * 70.0
		particles.append({
			"x": bx + cos(a) * br * 0.8, "y": by + sin(a) * br * 0.8,
			"vx": cos(a) * sp, "vy": sin(a) * sp - 30.0,
			"life": 0.55, "maxLife": 0.55, "r": 2.0 + randf() * 2.0,
			"color": Color("7dd3fc"),
		})

func _on_win() -> void:
	spawn_particles(float(level["goal"]["x"]), float(level["goal"]["y"]), Color("7dd3fc"), 42)
	spawn_particles(float(level["goal"]["x"]), float(level["goal"]["y"]), Color("ffe066"), 26)
	level_won.emit()

# ================================================================ 特效

func update_effects(dt: float) -> void:
	_time += dt
	if shake_time > 0.0:
		shake_time = maxf(0.0, shake_time - dt)
	var i := particles.size() - 1
	while i >= 0:
		var p: Dictionary = particles[i]
		p["life"] = float(p["life"]) - dt
		if float(p["life"]) <= 0.0:
			particles.remove_at(i)
			i -= 1
			continue
		p["vy"] = float(p["vy"]) + 900.0 * dt
		p["vx"] = float(p["vx"]) * 0.985
		p["x"] = float(p["x"]) + float(p["vx"]) * dt
		p["y"] = float(p["y"]) + float(p["vy"]) * dt
		i -= 1

func spawn_particles(x: float, y: float, color: Color, n: int) -> void:
	for i in n:
		var a := randf() * TAU
		var sp := 50.0 + randf() * 230.0
		particles.append({
			"x": x, "y": y,
			"vx": cos(a) * sp, "vy": sin(a) * sp - 60.0,
			"life": 0.45 + randf() * 0.45, "maxLife": 0.9,
			"r": 2.0 + randf() * 3.0, "color": color,
		})

# ================================================================ 绘制

func _draw() -> void:
	if editor_mode:
		_draw_editor()
		return
	_draw_background()
	if level.is_empty():
		return
	var t := _time
	for p in (level["platforms"] as Array):
		draw_platform(p)
	for s in (level["spikes"] as Array):
		draw_spikes(s)
	draw_items(t, false)
	draw_goal(level["goal"], t)
	_draw_particles()
	_draw_ball()
	_draw_hud()

func _draw_editor() -> void:
	var t := _time
	_draw_background()
	var g1 := Color(0.47, 0.67, 1.0, 0.09)
	var g2 := Color(0.47, 0.67, 1.0, 0.2)
	for x in range(0, int(W) + 1, 20):
		draw_line(Vector2(x + 0.5, 0), Vector2(x + 0.5, H), g2 if x % 100 == 0 else g1, 1.0)
	for y in range(0, int(H) + 1, 20):
		draw_line(Vector2(0, y + 0.5), Vector2(W, y + 0.5), g2 if y % 100 == 0 else g1, 1.0)

	var lv := editor_level
	if lv.is_empty():
		return
	for p in (lv["platforms"] as Array):
		draw_platform(p)
	for s in (lv["spikes"] as Array):
		draw_spikes(s)
	draw_items(t, true)
	draw_goal(lv["goal"], t)

	var sp: Dictionary = lv["spawn"]
	draw_arc(Vector2(float(sp["x"]), float(sp["y"])), 17.0, 0.0, TAU, 40, Color(0.37, 0.92, 0.83, 0.9), 2.5)
	draw_circle(Vector2(float(sp["x"]), float(sp["y"])), 13.0, Color(0.37, 0.92, 0.83, 0.25))
	_draw_text("起点", Vector2(float(sp["x"]), float(sp["y"]) - 24.0), 11, Color("5eead4"), HORIZONTAL_ALIGNMENT_CENTER)

	if editor_draft != null:
		var d: Dictionary = editor_draft
		var x0: float = minf(float(d["x0"]), float(d["x1"]))
		var y0: float = minf(float(d["y0"]), float(d["y1"]))
		var rw: float = absf(float(d["x1"]) - float(d["x0"]))
		var rh: float = absf(float(d["y1"]) - float(d["y0"]))
		var col := Color(0.49, 0.83, 0.99, 0.95)
		var fill := Color(0.22, 0.74, 0.97, 0.18)
		if _ed_tool == "spike":
			col = Color(1.0, 0.47, 0.59, 0.95)
			fill = Color(1.0, 0.24, 0.39, 0.18)
		draw_rect(Rect2(x0, y0, rw, rh), fill)
		draw_rect(Rect2(x0 + 0.5, y0 + 0.5, rw, rh), col, false, 1.5)

	if editor_selected != null:
		_draw_selection()

func _draw_selection() -> void:
	var sel: Dictionary = editor_selected
	var obj = null
	var kind := str(sel["kind"])
	var idx := int(sel["index"])
	if kind == "platform":
		var a: Array = editor_level["platforms"]
		if idx < a.size():
			obj = a[idx]
	elif kind == "spike":
		var a2: Array = editor_level["spikes"]
		if idx < a2.size():
			obj = a2[idx]
	elif kind == "item":
		var a3: Array = editor_level["items"]
		if idx < a3.size():
			obj = a3[idx]
	elif kind == "spawn":
		obj = editor_level["spawn"]
	elif kind == "goal":
		obj = editor_level["goal"]
	if obj == null:
		return
	var halo := Color(1.0, 0.85, 0.3, 0.9)
	if kind == "spawn" or kind == "goal":
		draw_arc(Vector2(float(obj["x"]), float(obj["y"])), 22.0, 0.0, TAU, 40, halo, 2.0)
		return
	if kind == "item" and not obj.has("w"):
		draw_arc(Vector2(float(obj["x"]), float(obj["y"])), float(obj.get("r", 20.0)) + 5.0, 0.0, TAU, 40, halo, 2.0)
		return
	draw_rect(Rect2(float(obj["x"]) - 2.0, float(obj["y"]) - 2.0, float(obj["w"]) + 4.0, float(obj["h"]) + 4.0),
		halo, false, 2.0)

## draw_string 的 width=-1 时对齐参数不生效，这里自己按宽度偏移
func _draw_text(txt: String, pos: Vector2, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	if font == null:
		return
	var x := pos.x
	if align != HORIZONTAL_ALIGNMENT_LEFT:
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		x -= w * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else w
	draw_string(font, Vector2(x, pos.y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw_background() -> void:
	# 三档色标的竖直渐变，和原版 createLinearGradient 一致
	draw_texture_rect(_bg_tex, Rect2(0, 0, W, H), false, Color.WHITE)
	for s in _stars:
		var a: float = float(s["a"]) * (0.6 + 0.4 * sin(_time * 1.6 + float(s["ph"])))
		draw_circle(Vector2(float(s["x"]), float(s["y"])), float(s["r"]), Color(0.81, 0.89, 1.0, a))
	draw_texture_rect(_glow_tex, Rect2(W * 0.5 - 620.0, H + 120.0 - 620.0, 1240.0, 1240.0), false,
		Color(0.35, 0.55, 1.0, 0.22))

func draw_platform(p: Dictionary) -> void:
	var rect := Rect2(float(p["x"]), float(p["y"]), float(p["w"]), float(p["h"]))
	var rad: float = minf(8.0, float(p["h"]) * 0.5)
	# 阴影交给 StyleBoxFlat（只有它支持 shadow），本体用带渐变的圆角多边形
	_sb_plat.set_corner_radius_all(int(rad))
	draw_style_box(_sb_plat, rect)
	_round_grad_v(rect, rad, Color("5b7cfa"), Color("293a91"))
	if float(p["h"]) >= 6.0:
		# 顶面高光：比原版更淡更圆（细一点、透明度低一点、两端全圆）
		var hw: float = maxf(0.0, rect.size.x - 12.0)
		if hw > 4.0:
			_round_fill(Rect2(rect.position.x + 6.0, rect.position.y + 1.5, hw, 2.5), 1.25,
				Color(0.78, 0.89, 1.0, 0.42))

func draw_spikes(s: Dictionary) -> void:
	var dir := str(s.get("dir", "up"))
	var cx := float(s["x"]) + float(s["w"]) * 0.5
	var cy := float(s["y"]) + float(s["h"]) * 0.5
	var rot := 0.0
	var ew := float(s["w"])
	var eh := float(s["h"])
	if dir == "down":
		rot = PI
	elif dir == "left":
		rot = -PI * 0.5
		ew = float(s["h"])
		eh = float(s["w"])
	elif dir == "right":
		rot = PI * 0.5
		ew = float(s["h"])
		eh = float(s["w"])
	var count := maxi(1, int(round(ew / 20.0)))
	var tw := ew / float(count)
	var x0 := -ew * 0.5
	var y0 := -eh * 0.5
	var y1 := eh * 0.5
	draw_set_transform(Vector2(cx, cy), rot, Vector2.ONE)
	# 原版 shadowBlur 14 的红光：固定外扩，不随刺的长度爆开
	_rect_glow(Rect2(x0, y0, ew, eh), 3.0, Color(1.0, 0.24, 0.39, 0.55), 14.0, 5)
	for i in count:
		var x := x0 + float(i) * tw
		draw_polygon(
			PackedVector2Array([
				Vector2(x, y1),
				Vector2(x + tw * 0.5, y0 + 1.0),
				Vector2(x + tw, y1),
			]),
			PackedColorArray([Color("c81e50"), Color("ff8fa3"), Color("c81e50")])
		)
	draw_rect(Rect2(x0, y1 - 3.0, ew, 3.0), Color(0.47, 0.08, 0.2, 0.8))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func draw_spring(it: Dictionary) -> void:
	_rect_glow(Rect2(float(it["x"]), float(it["y"]), float(it["w"]), float(it["h"])),
		6.0, Color(0.65, 0.55, 0.98, 0.6), 16.0, 5)
	var x := float(it["x"])
	var y := float(it["y"])
	var w := float(it["w"])
	var h := float(it["h"])
	var coil_h := maxf(4.0, h - 6.0)
	for i in 4:
		var y0 := y + 5.0 + (coil_h / 4.0) * float(i)
		var y1 := y0 + coil_h / 4.0
		draw_line(Vector2(x + 4.0, y1), Vector2(x + w - 4.0, y0), Color(0.77, 0.71, 0.99, 0.95), 2.0)
	_round_grad_v(Rect2(x, y, w, 7.0), 3.5, Color("f5f3ff"), Color("a78bfa"))
	_round_fill(Rect2(x + 2.0, y + h - 5.0, w - 4.0, 5.0), 2.5, Color("4c1d95"))

func draw_boost(it: Dictionary, t: float) -> void:
	var dir := int(it.get("dir", 1))
	var x := float(it["x"])
	var y := float(it["y"])
	var w := float(it["w"])
	var h := float(it["h"])
	var c_lo := Color(0.22, 0.74, 0.97, 0.12)
	var c_hi := Color(0.22, 0.74, 0.97, 0.48)
	# ★ 原版是 roundRectPath(..., it.h / 2) —— 两端全圆的胶囊，不是方框
	var cap := h * 0.5
	_round_grad_h(Rect2(x, y, w, h), cap, c_lo if dir > 0 else c_hi, c_hi if dir > 0 else c_lo)
	_round_stroke(Rect2(x, y, w, h), cap, Color(0.49, 0.83, 0.99, 0.65), 1.5)
	var cy := y + h * 0.5
	var n := maxi(2, int(w / 40.0))
	var gap := w / float(n + 1)
	var flow := fmod(t * 60.0, gap)
	for i in n:
		var cx := x + gap * float(i + 1)
		cx += (flow - gap * 0.5) if dir > 0 else -(flow - gap * 0.5)
		if cx < x + 7.0 or cx > x + w - 7.0:
			continue
		var sz := minf(6.0, h * 0.32)
		var pts := PackedVector2Array()
		if dir > 0:
			pts = PackedVector2Array([Vector2(cx - sz, cy - sz), Vector2(cx + sz * 0.6, cy), Vector2(cx - sz, cy + sz)])
		else:
			pts = PackedVector2Array([Vector2(cx + sz, cy - sz), Vector2(cx - sz * 0.6, cy), Vector2(cx + sz, cy + sz)])
		draw_polyline(pts, Color(0.88, 0.98, 1.0, 0.9), 2.4)

func draw_coin(it: Dictionary, t: float, taken: bool) -> void:
	var ix := float(it["x"])
	var iy := float(it["y"])
	var ir := float(it["r"])
	if taken:
		draw_arc(Vector2(ix, iy), ir * 0.7, 0.0, TAU, 32, Color(1.0, 0.84, 0.37, 0.16), 1.5)
		return
	var pulse := 1.0 + sin(t * 4.0 + ix * 0.02) * 0.07
	var r := ir * pulse
	_circle_glow(Vector2(ix, iy), r, Color(1.0, 0.78, 0.24, 0.55), 18.0)
	draw_texture_rect(_coin_tex, Rect2(ix - r, iy - r, r * 2.0, r * 2.0), false, Color.WHITE)
	var w := r * 0.85 * absf(cos(t * 2.2 + iy * 0.01))
	draw_rect(Rect2(ix - w * 0.5, iy - r * 0.34, maxf(1.5, w), r * 0.68), Color(1.0, 0.98, 0.86, 0.85))

func draw_portal(it: Dictionary, t: float, pair_idx: int, label: String) -> void:
	var ix := float(it["x"])
	var iy := float(it["y"])
	var r := float(it.get("r", 24.0))
	var color: Color = LevelIO.PORTAL_COLORS[pair_idx % LevelIO.PORTAL_COLORS.size()]
	_ring_glow(Vector2(ix, iy), r, Color(color.r, color.g, color.b, 0.55), 24.0, 3.0)
	draw_arc(Vector2(ix, iy), r, 0.0, TAU, 48, color, 3.0)
	for i in 3:
		var rr := r * (0.55 - float(i) * 0.13)
		var a0 := t * 1.6 + float(i) * 2.1
		draw_arc(Vector2(ix, iy), rr, a0, a0 + 3.4, 24, Color(color.r, color.g, color.b, 0.75), 2.0)
	draw_circle(Vector2(ix, iy), r * 0.6, Color(color.r, color.g, color.b, 0.35))
	draw_circle(Vector2(ix, iy), r * 0.28, Color(1, 1, 1, 0.9))
	if label != "":
		_draw_text_outlined(label, Vector2(ix, iy + 4.0), 12, Color.WHITE,
			Color(0, 0, 0, 0.55), 1.0, HORIZONTAL_ALIGNMENT_CENTER)

func draw_checkpoint(it: Dictionary, t: float, active: bool) -> void:
	var ix := float(it["x"])
	var iy := float(it["y"])
	var r := float(it.get("r", 22.0))
	if active:
		_ring_glow(Vector2(ix, iy), r, Color(0.29, 0.87, 0.5, 0.5), 22.0, 2.5)
	var ring := Color("86efac") if active else Color(0.29, 0.87, 0.5, 0.55)
	draw_arc(Vector2(ix, iy), r, 0.0, TAU, 40, ring, 3.0 if active else 2.0)
	draw_circle(Vector2(ix, iy), r, Color(0.29, 0.87, 0.5, 0.22 if active else 0.07))
	if active:
		var pulse := 1.0 + sin(t * 4.0) * 0.1
		draw_arc(Vector2(ix, iy), r * pulse + 5.0, 0.0, TAU, 40, Color(0.53, 0.94, 0.67, 0.55), 1.5)
	var fx := ix - r * 0.45
	var fy0 := iy + r * 0.5
	var fy1 := iy - r * 0.65
	draw_line(Vector2(fx, fy0), Vector2(fx, fy1), Color("86efac") if active else Color(0.29, 0.87, 0.5, 0.7), 2.5)
	draw_colored_polygon(PackedVector2Array([
		Vector2(fx, fy1), Vector2(fx + r * 0.65, fy1 + r * 0.22), Vector2(fx, fy1 + r * 0.44),
	]), Color("86efac") if active else Color(0.29, 0.87, 0.5, 0.55))

func draw_items(t: float, for_editor: bool) -> void:
	var items: Array = editor_level["items"] if for_editor else level["items"]
	for i in items.size():
		var it: Dictionary = items[i]
		var ty := str(it["type"])
		if ty == "coin":
			draw_coin(it, t, (not for_editor) and coins_taken.has(i))
		elif ty == "boost":
			draw_boost(it, t)
		elif ty == "spring":
			draw_spring(it)
		elif ty == "checkpoint":
			draw_checkpoint(it, t, (not for_editor) and active_checkpoint == i)
	var portal_no := 0
	for it in items:
		if str(it["type"]) != "portal":
			continue
		var pair_idx := int(portal_no / 2)
		var in_pair := (portal_no % 2) + 1
		portal_no += 1
		draw_portal(it, t, pair_idx, str(pair_idx + 1) + ("A" if in_pair == 1 else "B"))

func draw_goal(goal: Dictionary, t: float) -> void:
	var gx := float(goal["x"])
	var gy := float(goal["y"])
	var gr := float(goal.get("r", 22.0))
	var pulse := 1.0 + sin(t * 3.2) * 0.10
	_ring_glow(Vector2(gx, gy), gr * pulse, Color(0.22, 0.74, 0.97, 0.55), 30.0, 3.5)
	draw_arc(Vector2(gx, gy), gr * pulse, 0.0, TAU, 48, Color(0.49, 0.83, 0.99, 0.95), 3.5)
	draw_circle(Vector2(gx, gy), gr * pulse, Color(0.22, 0.74, 0.97, 0.28))
	draw_circle(Vector2(gx, gy), gr * pulse * 0.5, Color(0.88, 0.98, 1.0, 0.75))
	_disc(Vector2(gx, gy), 3.5 * pulse, Color.WHITE)

func _draw_particles() -> void:
	for p in particles:
		var a: float = clampf(float(p["life"]) / float(p["maxLife"]), 0.0, 1.0)
		var c: Color = p["color"]
		draw_circle(Vector2(float(p["x"]), float(p["y"])), float(p["r"]), Color(c.r, c.g, c.b, a))

func _draw_ball() -> void:
	for i in trail.size():
		var tp: Vector2 = trail[i]
		var k := float(i + 1) / float(trail.size())
		draw_circle(tp, br * (0.35 + k * 0.6), Color(1.0, 0.76, 0.28, k * k * 0.30))
	if jump_restore_fx > 0.0:
		var k2 := 1.0 - (jump_restore_fx / 0.55)
		draw_arc(Vector2(bx, by), br + 6.0 + k2 * 22.0, 0.0, TAU, 40, Color(0.49, 0.83, 0.99, (1.0 - k2) * 0.75), 2.5)
	_circle_glow(Vector2(bx, by), br, Color(1.0, 0.69, 0.13, 0.55), 26.0)
	# 真正的径向渐变贴图（圆心偏左上，和原版 createRadialGradient 参数一致）
	draw_texture_rect(_ball_tex, Rect2(bx - 22.0, by - 22.0, 44.0, 44.0), false, Color.WHITE)
	var look_x := clampf(bvx / 110.0, -3.0, 3.0)
	var look_y := clampf(bvy / 200.0, -3.0, 3.0)
	_disc(Vector2(bx - 4.8 + look_x, by - 2.0 + look_y), 2.5, Color("4a2c07"))
	_disc(Vector2(bx + 4.8 + look_x, by - 2.0 + look_y), 2.5, Color("4a2c07"))

func _draw_hud() -> void:
	if font == null:
		return
	var c1 := Color(0.91, 0.94, 1.0, 0.92)
	var c2 := Color(0.63, 0.75, 0.94, 0.75)
	_draw_text(str(level["name"]), Vector2(26, 40), 19, c1)
	var info := "死亡 %d 次　·　用时 %.1f 秒" % [hud_deaths, level_time]
	if coins_total > 0:
		info += "　·　金币 %d/%d" % [coins_got, coins_total]
	_draw_text(info, Vector2(26, 64), 14, c2)

	var has_cp := false
	for it in (level["items"] as Array):
		if it["type"] == "checkpoint":
			has_cp = true
			break
	if has_cp and active_checkpoint >= 0:
		_draw_text("⛳ 已存档", Vector2(26, 86), 13, Color(0.53, 0.94, 0.67, 0.85))

	# 跳跃机会（右上，和原版一致：文字在 pips 左边）
	_draw_text("跳跃", Vector2(W - 56, 66), 13, c2, HORIZONTAL_ALIGNMENT_RIGHT)
	for i in 2:
		var px := W - 46.0 + float(i) * 12.0
		var col := Color(0.47, 0.6, 0.82, 0.25)
		if i < jumps_left:
			col = Color("7dd3fc") if jump_restore_fx > 0.0 else Color("38bdf8")
		_disc(Vector2(px, 62.0), 4.5, col)
	if hud_testing:
		_draw_text("试玩模式", Vector2(W - 26, 40), 13, Color(1.0, 0.82, 0.39, 0.8), HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		_draw_text("关卡 %d / %d" % [hud_level_index + 1, hud_playlist_len], Vector2(W - 26, 40), 13,
			Color(0.63, 0.75, 0.94, 0.6), HORIZONTAL_ALIGNMENT_RIGHT)

	var total := mini(hud_playlist_len, 14)
	for i in total:
		var x := W - 26.0 - float(total - 1 - i) * 18.0
		_disc(Vector2(x, 88.0), 5.0, Color("38bdf8") if i <= hud_level_index else Color(0.47, 0.6, 0.82, 0.3))

	if hud_frozen:
		_draw_text("⏸ 冻结中　步数 %d" % hud_steps, Vector2(26, H - 32), 14, Color("fbbf24"))
		_draw_text("F 逐帧　·　P 解冻　·　[ ] 变速", Vector2(26, H - 14), 12, Color(0.98, 0.75, 0.14, 0.72))
	elif not is_equal_approx(hud_time_scale, 1.0):
		var col2 := Color("fb7185") if hud_time_scale > 1.0 else Color("4ade80")
		_draw_text("⚡ %.2fx　按 \u005c 重置" % hud_time_scale, Vector2(26, H - 14), 14, col2)
	if hud_testing:
		_draw_text("◆ 试玩模式 ◆", Vector2(W * 0.5, 32), 13, Color(1.0, 0.82, 0.39, 0.85), HORIZONTAL_ALIGNMENT_CENTER)

func set_ed_tool(t: String) -> void:
	_ed_tool = t
	queue_redraw()

# ================================================================ 圆角 / 渐变绘制
# 原版 canvas 里到处是 roundRectPath + createLinearGradient 的组合，
# 之前我用 draw_rect / draw_polygon 走了直角，这里补回来。

## 圆角矩形轮廓（等价 roundRectPath）
func _round_rect_pts(r: Rect2, radius: float, seg := 7) -> PackedVector2Array:
	var rad: float = minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var pts := PackedVector2Array()
	if rad <= 0.5:
		pts.append(r.position)
		pts.append(Vector2(r.end.x, r.position.y))
		pts.append(r.end)
		pts.append(Vector2(r.position.x, r.end.y))
		return pts
	var corners := [
		[Vector2(r.end.x - rad, r.position.y + rad), -PI * 0.5],
		[Vector2(r.end.x - rad, r.end.y - rad), 0.0],
		[Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5],
		[Vector2(r.position.x + rad, r.position.y + rad), PI],
	]
	for c in corners:
		var center: Vector2 = c[0]
		var a0: float = c[1]
		for i in range(seg + 1):
			var a := a0 + (PI * 0.5) * float(i) / float(seg)
			pts.append(center + Vector2(cos(a), sin(a)) * rad)
	return pts

## 圆角 + 纯色
func _round_fill(r: Rect2, radius: float, col: Color, seg := 7) -> void:
	draw_colored_polygon(_round_rect_pts(r, radius, seg), col)

## 圆角 + 竖直渐变（平台、弹簧）
func _round_grad_v(r: Rect2, radius: float, top: Color, bottom: Color, seg := 7) -> void:
	var pts := _round_rect_pts(r, radius, seg)
	var cols := PackedColorArray()
	var h: float = maxf(1.0, r.size.y)
	for p in pts:
		cols.append(top.lerp(bottom, clampf((p.y - r.position.y) / h, 0.0, 1.0)))
	draw_polygon(pts, cols)

## 圆角 + 水平渐变（加速带）
func _round_grad_h(r: Rect2, radius: float, left: Color, right: Color, seg := 7) -> void:
	var pts := _round_rect_pts(r, radius, seg)
	var cols := PackedColorArray()
	var w: float = maxf(1.0, r.size.x)
	for p in pts:
		cols.append(left.lerp(right, clampf((p.x - r.position.x) / w, 0.0, 1.0)))
	draw_polygon(pts, cols)

## 圆角描边
func _round_stroke(r: Rect2, radius: float, col: Color, width := 1.5, seg := 7) -> void:
	var pts := _round_rect_pts(r, radius, seg)
	var closed := PackedVector2Array(pts)
	closed.append(pts[0])
	draw_polyline(closed, col, width)

## 带描边的文字（原版传送门编号 / 地图标签都描了黑边）
func _draw_text_outlined(txt: String, pos: Vector2, size: int, color: Color,
		outline: Color, width := 1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	if font == null:
		return
	var x := pos.x
	if align != HORIZONTAL_ALIGNMENT_LEFT:
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		x -= w * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else w
	for dx in [-width, 0.0, width]:
		for dy in [-width, 0.0, width]:
			if dx == 0.0 and dy == 0.0:
				continue
			draw_string(font, Vector2(x + dx, pos.y + dy), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline)
	draw_string(font, Vector2(x, pos.y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

# ================================================================ 径向渐变贴图（等价 canvas createRadialGradient）
# 用 CPU 烘一张贴图：颜色按到「渐变圆心」的距离查色标，并且可以沿「形状圆心」裁成圆形。
# 这样球和金币就是真正的径向渐变，不是几层同心圆叠出来的。

static func _sample_stops(stops: Array, t: float) -> Color:
	if t <= float(stops[0][0]):
		return stops[0][1]
	for i in range(1, stops.size()):
		var a: float = float(stops[i - 1][0])
		var b: float = float(stops[i][0])
		if t <= b:
			return (stops[i - 1][1] as Color).lerp(stops[i][1], (t - a) / maxf(0.0001, b - a))
	return stops[stops.size() - 1][1]

static func _make_radial(size: int, stops: Array, grad_center: Vector2, grad_radius: float,
		clip_center := Vector2(0.5, 0.5), clip_radius := 0.0, feather := 0.012) -> ImageTexture:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var uv := Vector2(x + 0.5, y + 0.5) / float(size)
			var col := _sample_stops(stops, (uv - grad_center).length() / maxf(0.0001, grad_radius))
			if clip_radius > 0.0:
				var dc := (uv - clip_center).length()
				col.a *= clampf((clip_radius - dc) / feather, 0.0, 1.0)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

## 圆形外发光：叠若干层由外向内、由淡到浓的圆（等价 shadowBlur 的高斯扩散），
## 形状本体画在最上面把中间盖住，露出来的就是贴边的光晕
func _circle_glow(center: Vector2, radius: float, col: Color, blur := 14.0) -> void:
	var layers := 7
	for i in range(layers, 0, -1):
		var t := float(i) / float(layers)
		draw_circle(center, radius + blur * t,
			Color(col.r, col.g, col.b, col.a * pow(1.0 - t, 1.7) * 0.6))

## 圆环外发光（传送门那种空心圈：光晕得贴着环，不能把圈里也糊上）
func _ring_glow(center: Vector2, radius: float, col: Color, blur := 24.0, width := 3.0) -> void:
	var layers := 7
	for i in range(layers, 0, -1):
		var t := float(i) / float(layers)
		draw_arc(center, radius + blur * t, 0.0, TAU, 48,
			Color(col.r, col.g, col.b, col.a * pow(1.0 - t, 1.7) * 0.6), width + blur * t * 0.9)

## 矩形外发光（尖刺 / 弹簧）
func _rect_glow(r: Rect2, radius: float, col: Color, blur := 14.0, layers := 7) -> void:
	for i in range(layers, 0, -1):
		var t := float(i) / float(layers)
		var grow := blur * t
		_round_fill(Rect2(r.position - Vector2(grow, grow), r.size + Vector2(grow, grow) * 2.0),
			radius + grow, Color(col.r, col.g, col.b, col.a * pow(1.0 - t, 1.7) * 0.6))

## 平滑小圆：draw_circle 在半径很小时分段太少，放大看是方块
func _disc(center: Vector2, radius: float, col: Color, seg := 18) -> void:
	if radius <= 0.7:
		draw_rect(Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), col)
		return
	var pts := PackedVector2Array()
	for i in seg:
		var a := TAU * float(i) / float(seg)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(pts, col)

# ================================================================ 录像 / 复盘
# 每物理帧记一次球的状态，环形缓冲存最近 30 秒；死后可以按任意倍速回放。
# 复现方式是「把球放回记录的位置」，所以绘制、拖尾、眼睛朝向全都自动跟着走。

const REC_STRIDE := 6
const REC_CAP := 120 * 30          # 30 秒

var _rec := PackedFloat32Array()
var _rec_head := 0                 # 下一个写入槽
var _rec_total := 0                # 累计写入帧数
var _life_start := 0               # 当前这条命从第几帧开始
var _rep_start := 0                # 死亡时定格的回放区间
var _rep_end := 0
var replay_mode := false
## 回放到结尾时放什么特效：0=不放 1=死亡 2=通关
var replay_end_fx := 0

func _rec_init() -> void:
	_rec.resize(REC_CAP * REC_STRIDE)

func _rec_push() -> void:
	var i := _rec_head * REC_STRIDE
	_rec[i] = bx
	_rec[i + 1] = by
	_rec[i + 2] = bvx
	_rec[i + 3] = bvy
	_rec[i + 4] = 1.0 if on_ground else 0.0
	_rec[i + 5] = float(jumps_left)
	_rec_head = (_rec_head + 1) % REC_CAP
	_rec_total += 1

func _rec_mark_life() -> void:
	_life_start = _rec_total

func rec_reset() -> void:
	_rec_head = 0
	_rec_total = 0
	_life_start = 0
	_rep_start = 0
	_rep_end = 0

## 死亡瞬间把这条命的区间定格下来（之后 reset_ball 会开始下一条命）
func rec_snapshot_death() -> void:
	_rec_push()
	_rep_end = _rec_total
	_rep_start = maxi(_life_start, _rec_total - REC_CAP + 1)
	replay_end_fx = 1          # 死亡复盘：结尾补死亡特效

## 当前这条命已经录了多久（手动复盘用）
func rec_duration_cur() -> float:
	return float(maxi(0, _rec_total - _life_start)) / 120.0

## 手动复盘：把「现在」定格成回放区间（不播死亡特效）
func rec_snapshot_now() -> void:
	_rep_end = _rec_total
	_rep_start = maxi(_life_start, _rec_total - REC_CAP + 1)
	replay_end_fx = 0          # 手动复盘不放特效，由调用方决定

func rec_frames() -> int:
	return maxi(0, _rep_end - _rep_start)

func rec_duration() -> float:
	return float(rec_frames()) / 120.0

## 拖尾按「时间窗口」重建，而不是按「调用次数」追加。
## 实时玩的时候每物理帧追加一个点、保留 12 个 = 最近 0.1 秒的残影；
## 回放/导出时如果把 replay_apply 的每次调用都当成一个点，
## 30fps 导出就变成 0.4 秒、12fps 的 GIF 更是 1 秒 —— 残影会拖成一条长尾巴。
## 所以这里直接从录像里取「最后 0.1 秒」的原始帧位置，任何倍速/任何导出帧率都一致。
func _rebuild_trail_for(pos: float) -> void:
	var n := rec_frames()
	if n < 2:
		return
	var end_i := int(clampf(pos, 0.0, float(n - 1)))
	var start_i := maxi(0, end_i - 11)
	trail.clear()
	for i in range(start_i, end_i + 1):
		var idx := ((_rep_start + i) % REC_CAP) * REC_STRIDE
		trail.append(Vector2(_rec[idx], _rec[idx + 1]))

## 把球放到「这条命开始后 t 秒」的位置（帧间插值，任何倍速都顺滑）
func replay_apply(t: float) -> void:
	var n := rec_frames()
	if n < 2:
		return
	var pos := clampf(t * 120.0, 0.0, float(n - 1))
	var i0 := int(pos)
	var i1 := mini(i0 + 1, n - 1)
	var k := pos - float(i0)
	var ia := ((_rep_start + i0) % REC_CAP) * REC_STRIDE
	var ib := ((_rep_start + i1) % REC_CAP) * REC_STRIDE
	bx = lerpf(_rec[ia], _rec[ib], k)
	by = lerpf(_rec[ia + 1], _rec[ib + 1], k)
	bvx = lerpf(_rec[ia + 2], _rec[ib + 2], k)
	bvy = lerpf(_rec[ia + 3], _rec[ib + 3], k)
	on_ground = _rec[ia + 4] > 0.5
	_rebuild_trail_for(pos)
	# 放到最后一帧时补一次特效（死亡 / 通关）
	if replay_end_fx > 0 and pos >= float(n - 1) - 0.01:
		var fx := replay_end_fx
		replay_end_fx = 0
		if fx == 1:
			spawn_particles(bx, by, Color("ff4d6d"), 26)
			shake_time = 0.22
		else:
			var gx := float(level["goal"]["x"])
			var gy := float(level["goal"]["y"])
			spawn_particles(gx, gy, Color("7dd3fc"), 42)
			spawn_particles(gx, gy, Color("ffe066"), 26)
