extends CanvasLayer
## Readout for the active player/vehicle and contextual enter/exit prompt.

@onready var _speed: Label = $Speed
@onready var _prompt: Label = $Prompt
var _game: Node
var _life_status: Label
var _house_picker: OptionButton
var _job_picker: OptionButton
var _job_ids: Array[String] = []
var _mission_status: Label
var _house_ids: Array[String] = []
var _life_simulation: Node

func _ready() -> void:
	_game = get_tree().get_first_node_in_group("game")
	_life_simulation = get_parent().get_node_or_null("CubaLife")
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
	if _life_simulation != null:
		_house_picker = OptionButton.new()
		_house_picker.position = Vector2(28, 192)
		_house_picker.size = Vector2(330, 42)
		_house_picker.add_item("Elegir vivienda")
		for house in _life_simulation.get_house_options():
			_house_ids.append(str(house.get("id", "")))
			_house_picker.add_item(str(house.get("name", "Casa")))
		_house_picker.item_selected.connect(_on_house_selected)
		add_child(_house_picker)
		_job_picker = OptionButton.new()
		_job_picker.position = Vector2(370, 192)
		_job_picker.size = Vector2(330, 42)
		_job_picker.add_item("Elegir oficio")
		for job in _life_simulation.get_job_options():
			_job_ids.append(str(job.get("id", "")))
			_job_picker.add_item(str(job.get("name", "Oficio")))
		_job_picker.item_selected.connect(_on_job_selected)
		add_child(_job_picker)
		var selected_job := str(_life_simulation.selected_job_id)
		var selected_job_index := _job_ids.find(selected_job)
		if selected_job_index >= 0:
			_job_picker.select(selected_job_index + 1)
		_mission_status = Label.new()
		_mission_status.position = Vector2(28, 240)
		_mission_status.size = Vector2(900, 46)
		_mission_status.add_theme_font_size_override("font_size", 16)
		_mission_status.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		_mission_status.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		_mission_status.add_theme_constant_override("shadow_offset_x", 2)
		_mission_status.add_theme_constant_override("shadow_offset_y", 2)
		add_child(_mission_status)
		var selected_house := str(_life_simulation.selected_house_id)
		if selected_house != "":
			var selected_index := _house_ids.find(selected_house)
			if selected_index >= 0:
				_house_picker.select(selected_index + 1)
	if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available():
		var touch_layer := Control.new()
		touch_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		touch_layer.set_script(preload("res://scripts/mobile_controls.gd"))
		add_child(touch_layer)
		var controls_hint := get_node_or_null("Controls") as Label
		if controls_hint:
			controls_hint.hide()

func _on_house_selected(index: int) -> void:
	if index > 0 and index <= _house_ids.size() and _life_simulation != null:
		_life_simulation.select_house(_house_ids[index - 1])

func _on_job_selected(index: int) -> void:
	if index > 0 and index <= _job_ids.size() and _life_simulation != null:
		_life_simulation.set_job(_job_ids[index - 1])

func _process(_delta: float) -> void:
	if _game == null:
		_game = get_tree().get_first_node_in_group("game")
	if _life_simulation != null and _game != null:
		_life_status.text = _life_simulation.get_hud_summary(_game.get_active().global_position)
		var mission: Dictionary = _life_simulation.get_current_mission()
		if _mission_status != null:
			_mission_status.text = "Misión: " + str(mission.get("title", "Historia completada")) + "  |  " + str(mission.get("description", ""))
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
