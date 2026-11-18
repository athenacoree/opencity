extends Camera3D
## Third-person camera with mouse and touch-drag orbit.

@export var mouse_sensitivity := 0.0032
@export var touch_sensitivity := 0.006
@export var foot_distance := 5.0
@export var car_distance := 9.0
@export var foot_height := 1.6
@export var car_height := 3.4
@export var follow_speed := 9.0
@export var min_pitch := -1.1
@export var max_pitch := 0.5

var yaw := 0.0
var _pitch := -0.15
var _game: Node

func _ready() -> void:
	_game = get_tree().get_first_node_in_group("game")
	# Mouse capture is desktop-only; it can interfere with mobile touch input.
	if not _running_self_test() and not OS.has_feature("mobile") and not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _running_self_test() -> bool:
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	for flag in ["--shot", "--walk", "--drive", "--boost", "--fly"]:
		if flag in args:
			return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, min_pitch, max_pitch)
	elif event is InputEventScreenDrag:
		yaw -= event.relative.x * touch_sensitivity
		_pitch = clampf(_pitch - event.relative.y * touch_sensitivity, min_pitch, max_pitch)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	var target := _target()
	if target == null:
		return
	var in_car := _game != null and _game.driving != null
	var distance := car_distance if in_car else foot_distance
	var height := car_height if in_car else foot_height
	var offset := Vector3(sin(yaw) * cos(_pitch), -sin(_pitch), cos(yaw) * cos(_pitch)) * distance
	var desired := target.global_position + offset + Vector3.UP * height
	global_position = global_position.lerp(desired, clampf(follow_speed * delta, 0.0, 1.0))
	var focus := target.global_position + Vector3.UP * (1.4 if in_car else 1.2)
	if global_position.distance_to(focus) > 0.05:
		look_at(focus, Vector3.UP)
	var target_fov := 72.0
	if in_car:
		target_fov += clampf((_game.driving.get_speed_kmh() - 50.0) * 0.14, 0.0, 22.0)
	fov = lerpf(fov, target_fov, clampf(3.0 * delta, 0.0, 1.0))

func _target() -> Node3D:
	if _game == null:
		_game = get_tree().get_first_node_in_group("game")
		if _game == null:
			return null
	return _game.get_active()
