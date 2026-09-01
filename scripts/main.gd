extends Control
## Stage-C: 50 levels, menu/select, sprites, move lock, auto-advance.

enum Screen { MENU, SELECT, PLAY }

const TILE := 40.0
const MOVE_MS := 0.2
const LEVELS_PER_PAGE := 15
const AUTO_NEXT_SEC := 2.0
const AUTO_MENU_SEC := 3.0

@onready var _board: Control = $BoardWrap/Board
@onready var _board_wrap: CenterContainer = $BoardWrap
@onready var _hud: Label = $UI/HUD
@onready var _controls: HBoxContainer = $UI/Controls
@onready var _restart_btn: Button = $UI/Controls/Restart
@onready var _menu_btn: Button = $UI/Controls/Menu
@onready var _overlay: ColorRect = $UI/Overlay
@onready var _over_msg: Label = $UI/Overlay/VBox/Msg
@onready var _retry: Button = $UI/Overlay/VBox/Retry
@onready var _next: Button = $UI/Overlay/VBox/Next
@onready var _menu: ColorRect = $UI/Menu
@onready var _start_btn: Button = $UI/Menu/VBox/Start
@onready var _select_btn: Button = $UI/Menu/VBox/Select
@onready var _select: ColorRect = $UI/Select
@onready var _select_grid: GridContainer = $UI/Select/VBox/Grid
@onready var _prev_page: Button = $UI/Select/VBox/Pager/Prev
@onready var _next_page: Button = $UI/Select/VBox/Pager/Next
@onready var _page_lbl: Label = $UI/Select/VBox/Pager/Page
@onready var _select_back: Button = $UI/Select/VBox/Back

var _screen: Screen = Screen.MENU
var _level_idx: int = 0
var _map: Array = []
var _player: Vector2i = Vector2i.ZERO
var _won: bool = false
var _moving: bool = false
var _select_page: int = 0
var _tex_wall: Texture2D
var _tex_box: Texture2D
var _tex_box_ok: Texture2D
var _tex_target: Texture2D
var _tex_player: Texture2D
var _tex_ground: Texture2D
var _auto_gen: int = 0

func _ready() -> void:
	_tex_wall = load("res://assets/wall.png") as Texture2D
	_tex_box = load("res://assets/box.png") as Texture2D
	_tex_box_ok = load("res://assets/box_on_target.png") as Texture2D
	_tex_target = load("res://assets/target.png") as Texture2D
	_tex_player = load("res://assets/player.png") as Texture2D
	_tex_ground = load("res://assets/ground.png") as Texture2D
	_retry.pressed.connect(_on_retry)
	_next.pressed.connect(_on_next)
	_restart_btn.pressed.connect(_on_retry)
	_menu_btn.pressed.connect(_show_menu)
	_start_btn.pressed.connect(func() -> void: _load_level(0))
	_select_btn.pressed.connect(_show_select)
	_prev_page.pressed.connect(func() -> void: _change_page(-1))
	_next_page.pressed.connect(func() -> void: _change_page(1))
	_select_back.pressed.connect(_show_menu)
	_show_menu()

func _show_menu() -> void:
	_cancel_auto()
	_screen = Screen.MENU
	_menu.visible = true
	_select.visible = false
	_overlay.visible = false
	_board_wrap.visible = false
	_hud.visible = false
	_controls.visible = false
	_won = false
	_moving = false

func _show_select() -> void:
	_screen = Screen.SELECT
	_menu.visible = false
	_select.visible = true
	_overlay.visible = false
	_board_wrap.visible = false
	_hud.visible = false
	_controls.visible = false
	_rebuild_select()

func _page_count() -> int:
	return int(ceili(float(PushLevels.level_count()) / float(LEVELS_PER_PAGE)))

func _change_page(delta: int) -> void:
	_select_page = clampi(_select_page + delta, 0, maxi(0, _page_count() - 1))
	_rebuild_select()

func _rebuild_select() -> void:
	for c in _select_grid.get_children():
		c.queue_free()
	var start := _select_page * LEVELS_PER_PAGE
	var end := mini(start + LEVELS_PER_PAGE, PushLevels.level_count())
	for i in range(start, end):
		var b := Button.new()
		b.text = str(i + 1)
		b.custom_minimum_size = Vector2(56, 40)
		var idx := i
		b.pressed.connect(func() -> void: _load_level(idx))
		_select_grid.add_child(b)
	_page_lbl.text = "%d / %d" % [_select_page + 1, _page_count()]
	_prev_page.disabled = _select_page <= 0
	_next_page.disabled = _select_page >= _page_count() - 1

func _load_level(idx: int) -> void:
	_cancel_auto()
	_level_idx = clampi(idx, 0, PushLevels.level_count() - 1)
	_map = PushLevels.clone_map(_level_idx)
	_player = PushLevels.find_player(_map)
	_won = false
	_moving = false
	_screen = Screen.PLAY
	_menu.visible = false
	_select.visible = false
	_overlay.visible = false
	_board_wrap.visible = true
	_hud.visible = true
	_controls.visible = true
	_next.visible = false
	_rebuild()
	_update_hud()

func _update_hud() -> void:
	_hud.text = "关卡 %d / %d\n方向键移动 · 点击屏幕中心外区域转向 · R 重开" % [
		_level_idx + 1, PushLevels.level_count()
	]

func _rebuild() -> void:
	for c in _board.get_children():
		c.queue_free()
	var rows := _map.size()
	var cols := 0
	if rows > 0:
		cols = (_map[0] as Array).size()
	# Fit board into ~300x420
	var max_w := 300.0
	var max_h := 420.0
	var tile := minf(TILE, minf(max_w / float(maxi(cols, 1)), max_h / float(maxi(rows, 1))))
	var w := float(cols) * tile
	var h := float(rows) * tile
	_board.custom_minimum_size = Vector2(w, h)
	_board.size = Vector2(w, h)
	for y in rows:
		var row: Array = _map[y]
		for x in row.size():
			var t: int = int(row[x])
			var px := float(x) * tile
			var py := float(y) * tile
			if t != 1:
				_add_tex(px, py, tile, _tex_ground)
			if t == 1:
				_add_tex(px, py, tile, _tex_wall)
			elif t == 3 or t == 5 or t == 6:
				_add_tex(px, py, tile, _tex_target)
			if t == 2:
				_add_tex(px, py, tile, _tex_box)
			elif t == 5:
				_add_tex(px, py, tile, _tex_box_ok)
			if t == 4 or t == 6:
				_add_tex(px, py, tile, _tex_player)

func _add_tex(x: float, y: float, size: float, tex: Texture2D) -> void:
	if tex == null:
		var r := ColorRect.new()
		r.position = Vector2(x, y)
		r.size = Vector2(size, size)
		r.color = Color(0.5, 0.5, 0.55)
		_board.add_child(r)
		return
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.position = Vector2(x, y)
	tr.size = Vector2(size, size)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(tr)

func _unhandled_input(event: InputEvent) -> void:
	if _screen != Screen.PLAY or _won or _moving:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_R:
			_load_level(_level_idx)
			return
		var dir := Vector2i.ZERO
		match key_event.keycode:
			KEY_UP, KEY_W:
				dir = Vector2i(0, -1)
			KEY_DOWN, KEY_S:
				dir = Vector2i(0, 1)
			KEY_LEFT, KEY_A:
				dir = Vector2i(-1, 0)
			KEY_RIGHT, KEY_D:
				dir = Vector2i(1, 0)
			_:
				return
		_try_move(dir)
	# Original: tap relative to screen center
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_dir_from_center((event as InputEventMouseButton).position)
	if event is InputEventScreenTouch and event.pressed:
		_dir_from_center((event as InputEventScreenTouch).position)

func _dir_from_center(pos: Vector2) -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.5)
	var delta := pos - center
	if delta.length() < 28.0:
		return
	var dir := Vector2i.ZERO
	if absf(delta.x) > absf(delta.y):
		dir = Vector2i(1, 0) if delta.x > 0 else Vector2i(-1, 0)
	else:
		dir = Vector2i(0, 1) if delta.y > 0 else Vector2i(0, -1)
	_try_move(dir)

func _try_move(dir: Vector2i) -> void:
	if _moving or _won:
		return
	var result: Dictionary = PushLevels.try_move(_map, _player, dir)
	if not bool(result.get("ok", false)):
		return
	_moving = true
	_map = result["map"] as Array
	_player = result["player"] as Vector2i
	_rebuild()
	await get_tree().create_timer(MOVE_MS).timeout
	_moving = false
	if PushLevels.all_boxes_on_target(_map):
		_on_level_cleared()

func _on_level_cleared() -> void:
	_won = true
	_overlay.visible = true
	_auto_gen += 1
	var gen := _auto_gen
	if _level_idx + 1 >= PushLevels.level_count():
		_over_msg.text = "恭喜通关！\n即将返回主菜单…"
		_next.visible = false
		_retry.visible = true
		await get_tree().create_timer(AUTO_MENU_SEC).timeout
		if gen == _auto_gen:
			_show_menu()
	else:
		_over_msg.text = "恭喜过关！\n准备进入下一关…"
		_next.visible = true
		_retry.visible = true
		await get_tree().create_timer(AUTO_NEXT_SEC).timeout
		if gen == _auto_gen:
			_on_next()

func _cancel_auto() -> void:
	_auto_gen += 1

func _on_retry() -> void:
	_cancel_auto()
	_load_level(_level_idx)

func _on_next() -> void:
	_cancel_auto()
	if _level_idx + 1 < PushLevels.level_count():
		_load_level(_level_idx + 1)
	else:
		_show_menu()
