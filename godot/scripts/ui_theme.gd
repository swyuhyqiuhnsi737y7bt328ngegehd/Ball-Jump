class_name UITheme
extends RefCounted

## 界面主题：把 cd.html 里那套 CSS 视觉语言搬到 Godot
## 圆角、半透明蓝、渐变主按钮、发光阴影、0.1~0.28s 的过渡动画

# ---- 调色板（直接取自原版 CSS）----
const C_TEXT          := Color("cfe0ff")
const C_TEXT_BRIGHT   := Color("dceaff")
const C_TEXT_DIM      := Color("9fb3d9")
const C_TEXT_FAINT    := Color(200 / 255.0, 220 / 255.0, 255 / 255.0, 0.35)
const C_ACCENT        := Color("38bdf8")
const C_ACCENT_SOFT   := Color("a9e6ff")
const C_ACCENT_LIGHT  := Color("9fe4ff")
const C_DARK_TEXT     := Color("06122b")
const C_WARN          := Color("ffd9a8")

const C_BTN_BG        := Color(40 / 255.0, 60 / 255.0, 120 / 255.0, 0.55)
const C_BTN_HOVER     := Color(64 / 255.0, 96 / 255.0, 180 / 255.0, 0.72)
const C_BTN_PRESS     := Color(52 / 255.0, 80 / 255.0, 150 / 255.0, 0.9)
const C_BTN_BORDER    := Color(120 / 255.0, 170 / 255.0, 255 / 255.0, 0.25)
const C_BTN_BORDER_HI := Color(120 / 255.0, 170 / 255.0, 255 / 255.0, 0.45)
const C_FIELD_BG      := Color(20 / 255.0, 32 / 255.0, 66 / 255.0, 0.9)
const C_PANEL_BG      := Color(14 / 255.0, 22 / 255.0, 48 / 255.0, 0.96)
const C_PANEL_BORDER  := Color(120 / 255.0, 170 / 255.0, 255 / 255.0, 0.22)
const C_SCRIM         := Color(6 / 255.0, 10 / 255.0, 26 / 255.0, 0.82)
const C_ROW_BG        := Color(40 / 255.0, 60 / 255.0, 120 / 255.0, 0.3)
const C_ROW_HOVER     := Color(60 / 255.0, 92 / 255.0, 175 / 255.0, 0.48)

static func flat(bg: Color, radius := 8, border_w := 1, border_col := C_BTN_BORDER,
		pad_h := 14.0, pad_v := 7.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border_col
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	sb.anti_aliasing = true
	return sb

static func glow(sb: StyleBoxFlat, color: Color, size: int, offset := 0) -> StyleBoxFlat:
	sb.shadow_color = color
	sb.shadow_size = size
	sb.shadow_offset = Vector2(0, offset)
	return sb

static func build(font: Font, mono: Font) -> Theme:
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 14

	# ---------- 普通按钮 ----------
	t.set_stylebox("normal", "Button", flat(C_BTN_BG, 8))
	t.set_stylebox("hover", "Button", flat(C_BTN_HOVER, 8, 1, C_BTN_BORDER_HI))
	var press := flat(C_BTN_PRESS, 8, 1, C_BTN_BORDER_HI)
	press.content_margin_top = 8.0   # 按下时文字下沉 1px（对应 CSS 的 translateY(1px)）
	press.content_margin_bottom = 6.0
	t.set_stylebox("pressed", "Button", press)
	t.set_stylebox("disabled", "Button", flat(Color(30 / 255.0, 40 / 255.0, 70 / 255.0, 0.4), 8, 1,
		Color(120 / 255.0, 170 / 255.0, 255 / 255.0, 0.12)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_hover_color", "Button", Color("e6f2ff"))
	t.set_color("font_pressed_color", "Button", C_ACCENT_SOFT)
	t.set_color("font_disabled_color", "Button", Color(0.6, 0.7, 0.85, 0.35))

	# ---------- 主按钮（渐变蓝，深色字）----------
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", glow(flat(Color("6ed6ff"), 8, 0, Color.TRANSPARENT, 16.0, 7.0),
		Color(56 / 255.0, 189 / 255.0, 248 / 255.0, 0.30), 8))
	t.set_stylebox("hover", "PrimaryButton", glow(flat(Color("93e4ff"), 8, 0, Color.TRANSPARENT, 16.0, 7.0),
		Color(56 / 255.0, 189 / 255.0, 248 / 255.0, 0.55), 12))
	t.set_stylebox("pressed", "PrimaryButton", glow(flat(Color("4ec9ff"), 8, 0, Color.TRANSPARENT, 16.0, 7.0),
		Color(56 / 255.0, 189 / 255.0, 248 / 255.0, 0.35), 6))
	t.set_color("font_color", "PrimaryButton", C_DARK_TEXT)
	t.set_color("font_hover_color", "PrimaryButton", C_DARK_TEXT)
	t.set_color("font_pressed_color", "PrimaryButton", C_DARK_TEXT)

	# ---------- 胶囊按钮（通关浮层用）----------
	t.set_type_variation("PillButton", "Button")
	t.set_stylebox("normal", "PillButton", glow(flat(Color("6ed6ff"), 24, 0, Color.TRANSPARENT, 30.0, 12.0),
		Color(56 / 255.0, 189 / 255.0, 248 / 255.0, 0.45), 14, 2))
	t.set_stylebox("hover", "PillButton", glow(flat(Color("93e4ff"), 24, 0, Color.TRANSPARENT, 30.0, 12.0),
		Color(56 / 255.0, 189 / 255.0, 248 / 255.0, 0.62), 20, 4))
	t.set_stylebox("pressed", "PillButton", glow(flat(Color("4ec9ff"), 24, 0, Color.TRANSPARENT, 30.0, 12.0),
		Color(56 / 255.0, 189 / 255.0, 248 / 255.0, 0.4), 10, 1))
	t.set_color("font_color", "PillButton", C_DARK_TEXT)
	t.set_color("font_hover_color", "PillButton", C_DARK_TEXT)
	t.set_color("font_pressed_color", "PillButton", C_DARK_TEXT)

	# ---------- 开关按下去的样子 ----------
	t.set_type_variation("ToggleOnButton", "Button")
	t.set_stylebox("normal", "ToggleOnButton", flat(Color(56 / 255.0, 189 / 255.0, 248 / 255.0, 0.28), 8, 1,
		Color(56 / 255.0, 189 / 255.0, 248 / 255.0, 0.6)))
	t.set_stylebox("hover", "ToggleOnButton", flat(Color(56 / 255.0, 189 / 255.0, 248 / 255.0, 0.38), 8, 1,
		Color(56 / 255.0, 189 / 255.0, 248 / 255.0, 0.75)))
	t.set_stylebox("pressed", "ToggleOnButton", flat(Color(56 / 255.0, 189 / 255.0, 248 / 255.0, 0.32), 8, 1,
		Color(56 / 255.0, 189 / 255.0, 248 / 255.0, 0.7)))
	t.set_color("font_color", "ToggleOnButton", C_ACCENT_SOFT)
	t.set_color("font_hover_color", "ToggleOnButton", Color("d6f3ff"))

	# ---------- 面板 ----------
	t.set_type_variation("CardPanel", "PanelContainer")
	var card := flat(C_PANEL_BG, 16, 1, C_PANEL_BORDER, 18.0, 18.0)
	glow(card, Color(0, 0, 0, 0.6), 30, 12)
	t.set_stylebox("panel", "CardPanel", card)

	t.set_type_variation("FloatingPanel", "PanelContainer")
	var fl := flat(Color(10 / 255.0, 16 / 255.0, 38 / 255.0, 0.96), 12, 1,
		Color(120 / 255.0, 170 / 255.0, 255 / 255.0, 0.28), 12.0, 10.0)
	glow(fl, Color(0, 0, 0, 0.55), 22, 10)
	t.set_stylebox("panel", "FloatingPanel", fl)

	t.set_stylebox("panel", "PanelContainer", flat(Color(8 / 255.0, 14 / 255.0, 34 / 255.0, 0.93), 12, 1,
		Color(120 / 255.0, 170 / 255.0, 255 / 255.0, 0.22), 10.0, 8.0))

	t.set_type_variation("RowPanel", "PanelContainer")
	t.set_stylebox("panel", "RowPanel", flat(C_ROW_BG, 10, 1, Color.TRANSPARENT, 12.0, 9.0))

	# ---------- 输入框 ----------
	t.set_stylebox("normal", "LineEdit", flat(C_FIELD_BG, 8, 1, C_BTN_BORDER, 10.0, 6.0))
	t.set_stylebox("focus", "LineEdit", flat(C_FIELD_BG, 8, 1, Color(56 / 255.0, 189 / 255.0, 248 / 255.0, 0.7), 10.0, 6.0))
	t.set_color("font_color", "LineEdit", Color("dbe8ff"))
	t.set_color("font_placeholder_color", "LineEdit", Color(160 / 255.0, 195 / 255.0, 245 / 255.0, 0.45))
	t.set_color("caret_color", "LineEdit", C_ACCENT)

	t.set_stylebox("normal", "TextEdit", flat(Color(8 / 255.0, 14 / 255.0, 32 / 255.0, 0.95), 10, 1, C_BTN_BORDER, 12.0, 12.0))
	t.set_stylebox("focus", "TextEdit", flat(Color(8 / 255.0, 14 / 255.0, 32 / 255.0, 0.95), 10, 1,
		Color(56 / 255.0, 189 / 255.0, 248 / 255.0, 0.7), 12.0, 12.0))
	t.set_color("font_color", "TextEdit", Color("bfe0ff"))
	t.set_font("font", "TextEdit", mono)
	t.set_font_size("font_size", "TextEdit", 12)

	# ---------- 滚动条 ----------
	var grab := flat(Color(90 / 255.0, 130 / 255.0, 220 / 255.0, 0.4), 4, 0, Color.TRANSPARENT, 0.0, 0.0)
	var grab_hi := flat(Color(90 / 255.0, 130 / 255.0, 220 / 255.0, 0.65), 4, 0, Color.TRANSPARENT, 0.0, 0.0)
	t.set_stylebox("scroll", "VScrollBar", flat(Color(0, 0, 0, 0), 4, 0, Color.TRANSPARENT, 0.0, 0.0))
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_hi)

	# ---------- SpinBox ----------
	t.set_type_variation("PropSpin", "SpinBox")
	t.set_stylebox("normal", "PropSpin", flat(C_FIELD_BG, 5, 1, Color(120 / 255.0, 170 / 255.0, 255 / 255.0, 0.22), 6.0, 3.0))
	t.set_color("font_color", "PropSpin", Color("dbe8ff"))
	t.set_font_size("font_size", "PropSpin", 11)

	t.set_color("font_color", "Label", C_TEXT)
	t.set_color("font_color", "CheckBox", C_TEXT)
	return t

## 毛玻璃：取样背后画面做高斯模糊，再叠一层色（对应 CSS 的 backdrop-filter: blur）
static func make_frosted(tint: Color, blur := 2.6) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform vec4 tint : source_color = vec4(0.024, 0.039, 0.102, 0.82);
uniform float blur_amount : hint_range(0.0, 8.0) = 2.6;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * blur_amount;
	vec4 c = vec4(0.0);
	// 两圈 12 抽样，够平滑又不贵
	float w1 = 0.0625;
	float w2 = 0.03125;
	c += texture(screen_tex, SCREEN_UV + vec2(-1.0, -1.0) * px) * w1;
	c += texture(screen_tex, SCREEN_UV + vec2( 0.0, -1.0) * px) * w1 * 2.0;
	c += texture(screen_tex, SCREEN_UV + vec2( 1.0, -1.0) * px) * w1;
	c += texture(screen_tex, SCREEN_UV + vec2(-1.0,  0.0) * px) * w1 * 2.0;
	c += texture(screen_tex, SCREEN_UV) * 0.125;
	c += texture(screen_tex, SCREEN_UV + vec2( 1.0,  0.0) * px) * w1 * 2.0;
	c += texture(screen_tex, SCREEN_UV + vec2(-1.0,  1.0) * px) * w1;
	c += texture(screen_tex, SCREEN_UV + vec2( 0.0,  1.0) * px) * w1 * 2.0;
	c += texture(screen_tex, SCREEN_UV + vec2( 1.0,  1.0) * px) * w1;
	c += texture(screen_tex, SCREEN_UV + vec2(-2.0,  0.0) * px) * w2 * 2.0;
	c += texture(screen_tex, SCREEN_UV + vec2( 2.0,  0.0) * px) * w2 * 2.0;
	c += texture(screen_tex, SCREEN_UV + vec2( 0.0, -2.0) * px) * w2 * 2.0;
	c += texture(screen_tex, SCREEN_UV + vec2( 0.0,  2.0) * px) * w2 * 2.0;
	COLOR = vec4(mix(c.rgb, tint.rgb, tint.a), 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("blur_amount", blur)
	return mat

# ================================================================ 动画

## 淡入 + 轻微放大。只动 modulate 和 scale，绝不动 position ——
## 容器里的控件一旦被外部改 position，排版会被按住不放（子控件全叠到 (0,0)）
static func pop_in(node: Control, dur := 0.22, from_scale := 0.94) -> void:
	if not node.is_inside_tree():
		return
	node.resized.connect(func(): node.pivot_offset = node.size * 0.5)
	node.pivot_offset = node.size * 0.5
	var tw := node.create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	node.modulate.a = 0.0
	tw.tween_property(node, "modulate:a", 1.0, dur * 0.8)
	tw.tween_property(node, "scale", Vector2.ONE, dur).from(Vector2(from_scale, from_scale))

## 自由摆放的面板（不在容器里）：可以连位置一起滑进来
static func pop_in_free(node: Control, dur := 0.22, from_scale := 0.96, from_y := 12.0) -> void:
	if not node.is_inside_tree():
		return
	node.resized.connect(func(): node.pivot_offset = node.size * 0.5)
	node.pivot_offset = node.size * 0.5
	var target_y := node.position.y
	node.modulate.a = 0.0
	node.position.y = target_y + from_y
	var tw := node.create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "modulate:a", 1.0, dur)
	tw.tween_property(node, "position:y", target_y, dur)
	tw.tween_property(node, "scale", Vector2.ONE, dur).from(Vector2(from_scale, from_scale))

static func fade_out(node: Control, dur := 0.18) -> void:
	if not node.is_inside_tree():
		return
	var tw := node.create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(node, "modulate:a", 0.0, dur)

## StyleBox 是 Resource，没有 create_tween，得借宿主节点来建补间
static func _tween_sb(host: Node, sb: StyleBoxFlat, prop: String, to, dur: float) -> void:
	if not host.is_inside_tree():
		sb.set(prop, to)
		return
	var tw := host.create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(sb, prop, to, dur)

## 一个按钮一套自己的样式盒，三种状态共用同一个实例 ——
## 这样就能像 CSS 的 transition 那样「补间背景色」，而不是状态硬切
static func style_button(b: Button, base: Color, hover: Color, press: Color,
		radius := 8, dark_text := false, pad_h := 14.0, pad_v := 7.0,
		shadow := 0, shadow_col := Color(0, 0, 0, 0),
		border := C_BTN_BORDER, border_hover := C_BTN_BORDER_HI) -> void:
	var sb := flat(base, radius, 1 if border.a > 0.0 else 0, border, pad_h, pad_v)
	if shadow > 0:
		glow(sb, shadow_col, shadow)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if dark_text:
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(k, C_DARK_TEXT)
	b.pivot_offset = b.size * 0.5
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	var top := pad_v
	b.mouse_entered.connect(func():
		_tween_sb(b, sb, "bg_color", hover, 0.14)
		_tween_sb(b, sb, "border_color", border_hover, 0.14)
		if shadow > 0:
			_tween_sb(b, sb, "shadow_size", shadow + 6, 0.14))
	b.mouse_exited.connect(func():
		_tween_sb(b, sb, "bg_color", base, 0.16)
		_tween_sb(b, sb, "border_color", border, 0.16)
		_tween_sb(b, sb, "content_margin_top", top, 0.10)
		_tween_sb(b, sb, "content_margin_bottom", top, 0.10)
		if shadow > 0:
			_tween_sb(b, sb, "shadow_size", shadow, 0.16)
		var tw := b.create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "scale", Vector2.ONE, 0.14))
	b.button_down.connect(func():
		_tween_sb(b, sb, "bg_color", press, 0.08)
		_tween_sb(b, sb, "content_margin_top", top + 1.0, 0.08)   # CSS 的 translateY(1px)
		_tween_sb(b, sb, "content_margin_bottom", top - 1.0, 0.08)
		var tw := b.create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "scale", Vector2(0.98, 0.98), 0.07))
	b.button_up.connect(func():
		var tw := b.create_tween()
		tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "scale", Vector2.ONE, 0.16))

# ================================================================ 显式套样式
# （Theme 的 type variation 在这里不生效，改成直接覆盖，稳）

static func apply_plain(b: Button) -> void:
	style_button(b, C_BTN_BG, C_BTN_HOVER, C_BTN_PRESS, 8, false, 14.0, 7.0)

static func apply_primary(b: Button) -> void:
	style_button(b, Color("6ed6ff"), Color("93e4ff"), Color("4ec9ff"), 8, true, 16.0, 7.0,
		8, Color(56 / 255.0, 189 / 255.0, 248 / 255.0, 0.35), Color.TRANSPARENT, Color.TRANSPARENT)

static func apply_pill(b: Button) -> void:
	style_button(b, Color("6ed6ff"), Color("93e4ff"), Color("4ec9ff"), 24, true, 30.0, 12.0,
		14, Color(56 / 255.0, 189 / 255.0, 248 / 255.0, 0.45), Color.TRANSPARENT, Color.TRANSPARENT)

static func apply_toggle(b: Button, on: bool) -> void:
	if on:
		style_button(b, Color(56 / 255.0, 189 / 255.0, 248 / 255.0, 0.28),
			Color(56 / 255.0, 189 / 255.0, 248 / 255.0, 0.40),
			Color(56 / 255.0, 189 / 255.0, 248 / 255.0, 0.34), 8, false, 14.0, 7.0, 0,
			Color(0, 0, 0, 0), Color(56 / 255.0, 189 / 255.0, 248 / 255.0, 0.6),
			Color(56 / 255.0, 189 / 255.0, 248 / 255.0, 0.8))
		b.add_theme_color_override("font_color", C_ACCENT_SOFT)
		b.add_theme_color_override("font_hover_color", Color("d6f3ff"))
	else:
		apply_plain(b)
		b.add_theme_color_override("font_color", C_TEXT)
		b.add_theme_color_override("font_hover_color", Color("e6f2ff"))

static func apply_card(p: PanelContainer) -> void:
	var sb := flat(C_PANEL_BG, 16, 1, C_PANEL_BORDER, 18.0, 18.0)
	glow(sb, Color(0, 0, 0, 0.6), 30, 12)
	p.add_theme_stylebox_override("panel", sb)

static func apply_floating(p: PanelContainer) -> void:
	var sb := flat(Color(10 / 255.0, 16 / 255.0, 38 / 255.0, 0.97), 12, 1,
		Color(120 / 255.0, 170 / 255.0, 255 / 255.0, 0.28), 12.0, 10.0)
	glow(sb, Color(0, 0, 0, 0.55), 22, 10)
	p.add_theme_stylebox_override("panel", sb)

## 列表行：悬停时背景色过渡（对应 .menu-row:hover）
static func apply_row(p: PanelContainer) -> void:
	var sb := flat(C_ROW_BG, 10, 1, Color.TRANSPARENT, 12.0, 9.0)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_entered.connect(func():
		_tween_sb(p, sb, "bg_color", C_ROW_HOVER, 0.15)
		_tween_sb(p, sb, "border_color", Color(120 / 255.0, 170 / 255.0, 255 / 255.0, 0.3), 0.15))
	p.mouse_exited.connect(func():
		_tween_sb(p, sb, "bg_color", C_ROW_BG, 0.15)
		_tween_sb(p, sb, "border_color", Color.TRANSPARENT, 0.15))
