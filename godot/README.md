# 弹球闯关 · Godot 版

把桌面上的 `cd.html`（平台跳跃 + 关卡编辑器，单文件网页游戏）完整移植成 Godot 4 项目。

用 **Godot 4.7** 打开这个文件夹，按 **F5** 就能跑。

---

## 玩法

金色小球，左右移动 + 二段跳，躲开尖刺、吃金币，碰到发光的终点圈过关。

| 操作 | 按键 |
|---|---|
| 左右移动 | `← →` 或 `A D` |
| 跳跃 / 二段跳 | `空格` / `↑` / `W`（松开可截断跳跃高度） |
| 变速 | `[` `]`（0.1x ~ 3x），`\` 重置为 1x |
| 冻结 | `P` |
| 逐帧 | `F`（冻结状态下单步） |
| 菜单 / 返回 | `Esc` |

## 关卡元素

| 元素 | 说明 |
|---|---|
| 平台 | 实心方块，四周都能站 |
| 尖刺 | 四个朝向（↑↓←→），在编辑器里改 |
| 弹簧 | 踩上去弹到 1180 的速度（约 316px 高） |
| 加速带 | 把水平速度推到设定值，方向可左右 |
| 金币 | 吃满计数，通关界面显示 `x/y` |
| 传送门 | 两两配对（1A↔1B、2A↔2B…），进去从配对的另一个出来 |
| 存档点 | 碰到后死亡从存档点复活 |
| 起点 / 终点 | 出生位置、过关位置 |

## 关卡编辑器

主菜单 →「＋ 新建关卡」或某一关的「编辑」。

- **工具**：移动 / 平台 / 尖刺 / 弹簧 / 加速带 / 金币 / 传送门 / 存档点 / 起点 / 终点 / 橡皮
- **画**：选好工具直接在画布上拖拽出矩形，点一下放点状物件
- **改**：用「移动」点选后，右侧属性面板能改坐标 / 宽高 / 半径 / 力度 / 朝向；拖动可以搬家
- **删**：橡皮工具，或直接在物件上点右键
- **吸附**：默认 10px 网格吸附，可关
- **试玩**：`▶ 试玩` 直接跑一遍当前编辑内容（不进关卡列表），通关或按 Esc 回到编辑器
- **保存**：存到 `user://balljump_levels.json`
- **JSON**：当前关卡的 JSON 导入 / 导出，或复制到剪贴板

## 和网页版的兼容性

关卡的 JSON 结构和 `cd.html` **完全一致**（字段名、取值范围、默认值、坐标上限都照搬），所以：

- 网页版里「导出全部」出来的 `balljump-levels.json`，在 Godot 版菜单里点「导入全部」直接能用
- 反过来 Godot 版导出的 JSON 也能喂给网页版

## 界面（和网页版同一套视觉语言）

原版那套「圆润丝滑」是靠 CSS 做的，这里在 `scripts/ui_theme.gd` 里一一对应搬了过来：

| 原版 CSS | Godot 实现 |
|---|---|
| `border-radius: 8px` 按钮 / 16px 面板 | `StyleBoxFlat.set_corner_radius_all()` |
| `background: rgba(40,60,120,.55)` + 蓝色描边 | `StyleBoxFlat.bg_color` + `border_width/color` |
| 主按钮 `linear-gradient(180deg,#9fe4ff,#38bdf8)` | 亮蓝底 + `shadow_color` 发光（StyleBoxFlat 不支持渐变） |
| `box-shadow: 0 8px 24px rgba(56,189,248,.45)` | `StyleBoxFlat.shadow_color/size/offset` |
| `transition: background .14s, transform .1s` | 每个按钮持有**同一个** `StyleBoxFlat` 实例，用 `Tween` 补间它的 `bg_color`／`border_color`／阴影和边距 —— 和 CSS 一样是「颜色渐变」而不是状态硬切；按下时内容边距 +1px 模拟 `translateY(1px)` |
| `backdrop-filter: blur(10px)` | `BackBufferCopy` + 13 抽样高斯 `ShaderMaterial`（`hint_screen_texture`），菜单和通关浮层底下真的是糊的 |
| 面板 `transition: opacity .25s`、弹层 | `UITheme.pop_in` / `pop_in_free`（淡入 + 轻微放大 + 滑入） |
| 通关标题 `text-shadow: 0 0 26px` | Label 的 `font_outline_color` + `outline_size` |
| 胶囊 toast（`border-radius: 999px`） | 圆角 999 的 Label stylebox + 顶部滑入淡出 |
| 球 / 金币 / 终点 / 尖刺的 `shadowBlur` 光晕 | `GradientTexture2D`（FILL_RADIAL）贴图，边缘完全平滑 |
| `roundRectPath()` + `createLinearGradient()` 的组合到处都是 | `_round_rect_pts()`（等价 roundRectPath）+ `_round_grad_v/h()`：**加速带是 h/2 圆角的胶囊**、平台是 `#5b7cfa→#293a91` 竖直渐变、弹簧顶盖 3.5 圆角，都不是方块 |
| 传送门编号 `strokeText` 黑描边 | `_draw_text_outlined()`：先描一圈 1px 黑边再填白字 |
| 球的径向渐变圆心偏左上 `(-5,-6)` | 偏移的径向渐变贴图叠在底色上 |
| 平台顶部的白线 | 按需求**比原版更淡更圆**：`x+6, y+1.5, w-12, 2.5`、圆角 1.25（两端全圆）、`rgba(199,227,255,.42)` |
| 球的 `createRadialGradient(x-5, y-6, 1.5, x, y, r)` | `_make_radial()` 在 CPU 上烘一张 128² 贴图：色标 `#fffbe6→#ffd75e→#f59e0b`、渐变圆心偏移 `(-5,-6)`、按球心半径裁圆——是**真正的径向渐变**，不是同心圆叠的 |
| 金币的 `createRadialGradient`（圆心偏移 `(-0.35r, -0.4r)`） | 同样烘贴图，缩放绘制 |
| 小圆点（眼睛、跳跃点、关卡进度点） | `_disc()`：`draw_circle` 半径小时分段太少，放大看是方块 |
| 每根刺 `shadowBlur 14`、弹簧 16、金币 18、传送门 24、球 26、终点 30 | `_circle_glow(位置, 半径, 颜色, blur)` / `_rect_glow(矩形, 圆角, 颜色, blur)` —— **blur 是"向外扩散多少像素"，固定值**，不是按形状尺寸缩放 |
| `layoutCanvas()`：窗口占屏幕 96% × 94% 居中 | `_fit_window()`：同样按可用屏幕算缩放（0.6×~1.9×），设窗口大小并居中 |
| 画布外的页面底色 `#070a18` | `default_clear_color` 设成同色，等比缩放的留白不会露出一圈灰边 |

HUD 的位置也按原版摆回来：`跳跃 ●●` 和 `关卡 n / N` 在右上、进度点在 y=88、`☰` 按钮在右下角 40px 处。

⚠️ 两个 Godot 特有的坑（都在代码注释里标了）：

1. **不要在 `_draw()` 里新建贴图**。局部变量会在这一帧结束前释放，渲染时纹理工就没了，画面直接变白。
   所有渐变贴图都在 `_ready` 里建好缓存。
2. **不要用 Tween 去动容器里子控件的 `position`**。容器每次排版会把它按回去，两边打架的结果是所有子控件叠在 `(0,0)`。
   `pop_in` 只动 `modulate` 和 `scale`，需要滑入的自由面板才用 `pop_in_free`。

## 目录结构

```
cd_godot/
├── project.godot            项目配置（900×560，canvas_items 拉伸，保证缩放不糊）
├── scenes/main.tscn         主场景：Main(Node2D) + World(Node2D)
├── scripts/
│   ├── level_io.gd          关卡数据结构 / 归一化 / 存档（class_name LevelIO）
│   ├── ui_theme.gd          界面主题：圆角 / 半透明蓝 / 发光 / 过渡动画（class_name UITheme）
│   ├── world.gd             物理模拟 + 全部画面绘制（class_name World）
│   ├── editor.gd            编辑器：工具栏 / 属性面板 / 鼠标拖拽 / 保存
│   └── main.gd              流程、输入、菜单、通关浮层、JSON 面板
├── tests/physics_test.gd    无头物理自检
└── docs/                    截图（preview-play / preview-editor / preview-menu / preview-overlay）
```

## 自检

```bash
godot --headless --path . --script res://tests/physics_test.gd   # 物理 22 项
godot --headless --path . --script res://tests/editor_test.gd    # 编辑器 10 项
```

物理：自由落体与终端速度、落地、跳跃高度（离散积分 156.25px）、尖刺致死、金币、
传送门、弹簧、终点判定、关卡 JSON 往返与越界钳制。

编辑器：新建关卡、拖拽画平台、点放金币、移动工具拖物件、右键擦除，
以及「在工具栏 / 属性面板上拖拽不会误画到关卡里」和「自检不写玩家存档」。

> 编辑器鼠标走 `_unhandled_input`：点在工具栏或属性面板上的那一下会被 Control 吃掉，
> 不会顺手在画布上画一笔（另外编辑器里还挡了一层 `over_ui()` 矩形判断，双保险）。

调试用启动参数：`--play` 直接进第一关，`--edit-level` 直接进编辑器。

## 移植说明

物理常量和网页版逐字节对齐（重力 2200、最大速度 340、跳跃 820/760、
终端速度 1050、土狼时间 0.10s、跳跃缓冲 0.12s、固定步长 1/120），
主循环也是同样的「累加器 + 变速 + 冻结/逐帧」结构，
所以手感和原版一致；绘制部分用 `_draw()` 重写，
渐变用逐顶点着色的 `draw_polygon`、圆角用 `StyleBoxFlat`、
中文用 `SystemFont`（微软雅黑）保证任何机器都不会变方块。
