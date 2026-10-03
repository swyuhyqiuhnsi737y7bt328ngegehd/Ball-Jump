class_name LevelIO
extends RefCounted

## 关卡数据层：结构 / 归一化 / 存取
## JSON 结构和网页版 cd.html 完全一致，两边导出的关卡可以直接互导。

const W := 900.0
const H := 560.0

const ITEM_DEFAULTS := {
	"spring":     {"w": 42.0,  "h": 18.0, "power": 1180.0},
	"boost":      {"w": 130.0, "h": 22.0, "power": 540.0, "dir": 1},
	"coin":       {"r": 13.0},
	"portal":     {"r": 24.0},
	"checkpoint": {"r": 22.0},
}

const ITEM_NAMES := {
	"spring": "弹簧",
	"boost": "加速带",
	"coin": "金币",
	"portal": "传送门",
	"checkpoint": "存档点",
}

const SPIKE_DIRS := ["up", "down", "left", "right"]

const SPIKE_DIR_LABEL := {
	"up": "↑ 上", "down": "↓ 下", "left": "← 左", "right": "→ 右",
}

const PORTAL_COLORS := [
	Color("c084fc"), Color("38bdf8"), Color("4ade80"), Color("fb923c"),
	Color("f472b6"), Color("facc15"), Color("22d3ee"), Color("a78bfa"),
]

const SAVE_PATH := "user://balljump_levels.json"

# ---------------------------------------------------------------- 数值工具

static func num(v, lo: float, hi: float, def: float) -> float:
	var n := def
	if v is float or v is int:
		n = float(v)
	elif v is String and (v as String).is_valid_float():
		n = (v as String).to_float()
	else:
		return def
	if is_nan(n) or is_inf(n):
		return def
	return clampf(n, lo, hi)

static func dict_num(d: Dictionary, key: String, lo: float, hi: float, def: float) -> float:
	return num(d.get(key, null), lo, hi, def)

# ---------------------------------------------------------------- 归一化

static func normalize_item(raw) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var d: Dictionary = raw
	var t := str(d.get("type", ""))
	if not ITEM_DEFAULTS.has(t):
		return {}

	if t == "coin" or t == "portal" or t == "checkpoint":
		return {
			"type": t,
			"x": dict_num(d, "x", -800.0, 1800.0, 0.0),
			"y": dict_num(d, "y", -800.0, 1400.0, 0.0),
			"r": dict_num(d, "r", 6.0, 90.0, float(ITEM_DEFAULTS[t]["r"])),
		}

	var o := {
		"type": t,
		"x": dict_num(d, "x", -800.0, 1800.0, 0.0),
		"y": dict_num(d, "y", -800.0, 1400.0, 0.0),
		"w": dict_num(d, "w", 16.0, 600.0, float(ITEM_DEFAULTS[t]["w"])),
		"h": dict_num(d, "h", 10.0, 300.0, float(ITEM_DEFAULTS[t]["h"])),
		"power": dict_num(d, "power", 100.0, 3000.0, float(ITEM_DEFAULTS[t]["power"])),
	}
	if t == "boost":
		o["dir"] = -1 if float(d.get("dir", 1)) < 0.0 else 1
	return o

static func normalize_level(raw) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var d: Dictionary = raw

	var spawn_raw = d.get("spawn", {})
	var goal_raw = d.get("goal", {})
	var spawn_d: Dictionary = spawn_raw if spawn_raw is Dictionary else {}
	var goal_d: Dictionary = goal_raw if goal_raw is Dictionary else {}

	var lv := {
		"name": str(d.get("name", "自定义关卡")).substr(0, 24),
		"spawn": {
			"x": dict_num(spawn_d, "x", -400.0, W + 400.0, 70.0),
			"y": dict_num(spawn_d, "y", -400.0, H + 400.0, 460.0),
		},
		"goal": {
			"x": dict_num(goal_d, "x", -400.0, W + 400.0, 800.0),
			"y": dict_num(goal_d, "y", -400.0, H + 400.0, 460.0),
			"r": dict_num(goal_d, "r", 10.0, 60.0, 22.0),
		},
		"platforms": [],
		"spikes": [],
		"items": [],
	}

	var plats = d.get("platforms", [])
	if plats is Array:
		for p in (plats as Array).slice(0, 400):
			if not (p is Dictionary):
				continue
			(lv["platforms"] as Array).append({
				"x": dict_num(p, "x", -800.0, 1800.0, 0.0),
				"y": dict_num(p, "y", -800.0, 1400.0, 0.0),
				"w": dict_num(p, "w", 20.0, 2400.0, 100.0),
				"h": dict_num(p, "h", 8.0, 600.0, 16.0),
			})

	var spks = d.get("spikes", [])
	if spks is Array:
		for s in (spks as Array).slice(0, 400):
			if not (s is Dictionary):
				continue
			var dir := str(s.get("dir", "up"))
			if not SPIKE_DIRS.has(dir):
				dir = "up"
			(lv["spikes"] as Array).append({
				"x": dict_num(s, "x", -800.0, 1800.0, 0.0),
				"y": dict_num(s, "y", -800.0, 1400.0, 0.0),
				"w": dict_num(s, "w", 16.0, 900.0, 40.0),
				"h": dict_num(s, "h", 12.0, 400.0, 28.0),
				"dir": dir,
			})

	var its = d.get("items", [])
	if its is Array:
		for it in (its as Array).slice(0, 400):
			var n := normalize_item(it)
			if not n.is_empty():
				(lv["items"] as Array).append(n)

	return lv

static func blank_level() -> Dictionary:
	return {
		"name": "我的关卡",
		"spawn": {"x": 80.0, "y": 440.0},
		"goal": {"x": 800.0, "y": 440.0, "r": 22.0},
		"platforms": [{"x": 0.0, "y": 520.0, "w": 900.0, "h": 40.0}],
		"spikes": [],
		"items": [],
	}

static func clone_level(lv: Dictionary) -> Dictionary:
	return normalize_level(lv)

# ---------------------------------------------------------------- 存档

static func load_levels() -> Array:
	var out: Array = []
	if not FileAccess.file_exists(SAVE_PATH):
		return out
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return out
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed is Array:
		for raw in parsed:
			var lv := normalize_level(raw)
			if not lv.is_empty():
				out.append(lv)
	return out

static func save_levels(levels: Array) -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(levels, "  "))
	f.close()
	return true

static func levels_to_json(levels: Array) -> String:
	return JSON.stringify(levels, "  ")
