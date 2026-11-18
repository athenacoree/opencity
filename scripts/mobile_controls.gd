extends Control
## Touch controls that inject the same key events used by the desktop controllers.

const BUTTON_SIZE := Vector2(66.0, 66.0)
const MARGIN := 22.0
const GAP := 9.0
var _held_keys: Dictionary = {}
var _buttons: Array[Button] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_button("W", KEY_W)
	_build_button("A", KEY_A)
	_build_button("S", KEY_S)
	_build_button("D", KEY_D)
	_build_button("SALTO / FRENO", KEY_SPACE, Vector2(104.0, 58.0))
	_build_button("CORRER", KEY_SHIFT, Vector2(104.0, 58.0))
	_build_button("ENTRAR", KEY_E, Vector2(104.0, 58.0))
	_layout_buttons()

func _build_button(caption: String, keycode: int, custom_size: Vector2 = BUTTON_SIZE) -> void:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = custom_size
	button.size = custom_size
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_size_override("font_size", 15 if caption.length() > 2 else 23)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.055, 0.07, 0.09, 0.72)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.12, 0.16, 0.2, 0.88)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.22, 0.38, 0.48, 0.96)))
	button.button_down.connect(_press_key.bind(keycode))
	button.button_up.connect(_release_key.bind(keycode))
	add_child(button)
	_buttons.append(button)

func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	style.set_border_width_all(1)
	style.border_color = Color(1, 1, 1, 0.24)
	return style

func _layout_buttons() -> void:
	if _buttons.size() != 7:
		return
	var view := get_viewport_rect().size
	_buttons[0].position = Vector2(MARGIN + BUTTON_SIZE.x + GAP, view.y - MARGIN - BUTTON_SIZE.y * 3.0 - GAP * 2.0)
	_buttons[1].position = Vector2(MARGIN, view.y - MARGIN - BUTTON_SIZE.y * 2.0 - GAP)
	_buttons[2].position = Vector2(MARGIN + BUTTON_SIZE.x + GAP, view.y - MARGIN - BUTTON_SIZE.y - GAP)
	_buttons[3].position = Vector2(MARGIN + (BUTTON_SIZE.x + GAP) * 2.0, view.y - MARGIN - BUTTON_SIZE.y * 2.0 - GAP)
	_buttons[4].position = Vector2(view.x - MARGIN - _buttons[4].size.x, view.y - MARGIN - _buttons[4].size.y)
	_buttons[5].position = Vector2(view.x - MARGIN - _buttons[5].size.x, view.y - MARGIN - _buttons[5].size.y * 2.0 - GAP)
	_buttons[6].position = Vector2(view.x - MARGIN - _buttons[6].size.x, view.y - MARGIN - _buttons[6].size.y * 3.0 - GAP * 2.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_inside_tree():
		_layout_buttons()

func _press_key(keycode: int) -> void:
	if _held_keys.has(keycode):
		return
	_held_keys[keycode] = true
	_send_key(keycode, true)

func _release_key(keycode: int) -> void:
	if not _held_keys.has(keycode):
		return
	_held_keys.erase(keycode)
	_send_key(keycode, false)

func _send_key(keycode: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)

func _exit_tree() -> void:
	for keycode in _held_keys.keys():
		_send_key(int(keycode), false)
	_held_keys.clear()
