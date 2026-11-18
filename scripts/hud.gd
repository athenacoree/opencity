extends CanvasLayer
## Readout for the active player/vehicle and contextual enter/exit prompt.

@onready var _speed: Label = $Speed
@onready var _prompt: Label = $Prompt
var _game: Node
var _life_status: Label
var _life_simulation: Node

func _ready() -> void:
	_game = get_tree().get_first_node_in_group("game")
	_life_simulation = get_parent().get_node_or_null("../CubaLife")
	_life_status = Label.new()
	_life_status.name = "CubaLifeStatus"
	_life_status.position = Vector2(28, 154)
	_life_status.size = Vector2(900, 32)
	_life_status.add_theme_font_size_override("font_size", 18)
	_life_status.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72, 1.0))
	_life_status.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_life_status.add_theme_constant_override("shadow_offset_x", 2)
	_life_status.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_life_status)
	if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available():
		var touch_layer := Control.new()
		touch_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		touch_layer.set_script(preload("res://scripts/mobile_controls.gd"))
		add_child(touch_layer)
		var controls_hint := get_node_or_null("Controls") as Label
		if controls_hint:
			controls_hint.hide()

func _process(_delta: float) -> void:
	if _game == null:
		_game = get_tree().get_first_node_in_group("game")
	if _life_simulation != null and _game != null:
		_life_status.text = _life_simulation.get_hud_summary(_game.get_active().global_position)
	var active: Node = _game.get_active()
	if active == null:
		return
	if _game.driving != null:
		_speed.text = "%d km/h" % roundi(active.get_speed_kmh())
		if active.boosting:
			_speed.text += "   BOOST"
			_speed.modulate = Color(1.0, 0.72, 0.3)
		else:
			_speed.modulate = Color.WHITE
		_prompt.text = "E   get out"
	else:
		_speed.text = "on foot"
		_speed.modulate = Color.WHITE
		_prompt.text = "E   get in" if _game.nearest_vehicle() != null else ""
