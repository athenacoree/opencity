extends Node3D
## Owns the on-foot / in-car state.

signal active_changed(node: Node3D)

@export var enter_distance := 4.5
@onready var player: CharacterBody3D = $Player
var driving: RigidBody3D = null

var _quality_timer := 0.0
var _slow_fps_windows := 0
var _fast_fps_windows := 0
var _adaptive_quality_active := false
var _initial_ssao := true
var _initial_glow := true
var _initial_shadows := true
var _initial_shadow_distance := 260.0
var _initial_msaa := Viewport.MSAA_2X
var _world_environment: WorldEnvironment
var _sun: DirectionalLight3D

func _ready() -> void:
	_configure_adaptive_quality()
	add_to_group("game")
	for vehicle in get_tree().get_nodes_in_group("vehicle"):
		vehicle.active = false
	# Load only after the world and player nodes have completed _ready().
	call_deferred("_load_local_position")

func _configure_adaptive_quality() -> void:
	if not OS.has_feature("mobile") and not DisplayServer.is_touchscreen_available():
		return
	_world_environment = get_node_or_null("WorldEnvironment") as WorldEnvironment
	_sun = get_node_or_null("Sun") as DirectionalLight3D
	if _world_environment != null and _world_environment.environment != null:
		_initial_ssao = _world_environment.environment.ssao_enabled
		_initial_glow = _world_environment.environment.glow_enabled
	if _sun != null:
		_initial_shadows = _sun.shadow_enabled
		_initial_shadow_distance = _sun.directional_shadow_max_distance
	_initial_msaa = get_viewport().msaa_3d


func _process(delta: float) -> void:
	if not OS.has_feature("mobile") and not DisplayServer.is_touchscreen_available():
		return
	_quality_timer += delta
	if _quality_timer < 5.0:
		return
	_quality_timer = 0.0
	var fps := Engine.get_frames_per_second()
	if fps < 28:
		_slow_fps_windows += 1
		_fast_fps_windows = 0
	elif fps > 42:
		_fast_fps_windows += 1
		_slow_fps_windows = 0
	else:
		_slow_fps_windows = 0
		_fast_fps_windows = 0
	if _slow_fps_windows >= 3 and not _adaptive_quality_active:
		_set_mobile_quality_reduced(true)
	elif _fast_fps_windows >= 6 and _adaptive_quality_active:
		_set_mobile_quality_reduced(false)


func _set_mobile_quality_reduced(reduced: bool) -> void:
	_adaptive_quality_active = reduced
	if _world_environment != null and _world_environment.environment != null:
		_world_environment.environment.ssao_enabled = false if reduced else _initial_ssao
		_world_environment.environment.glow_enabled = false if reduced else _initial_glow
	if _sun != null:
		_sun.shadow_enabled = false if reduced else _initial_shadows
		_sun.directional_shadow_max_distance = 100.0 if reduced else _initial_shadow_distance
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED if reduced else _initial_msaa
	_slow_fps_windows = 0
	_fast_fps_windows = 0


func _load_local_position() -> void:
	if has_node("/root/LocalSave"):
		LocalSave.load_position(player)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_save_local_position()

func _save_local_position() -> void:
	if not has_node("/root/LocalSave"):
		return
	# If the player closes the app while driving, resume near the last vehicle.
	LocalSave.save_position(get_active())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		if driving != null:
			exit_vehicle()
		else:
			enter_nearest_vehicle()

func get_active() -> Node3D:
	return driving if driving != null else player

func nearest_vehicle() -> RigidBody3D:
	var best: RigidBody3D = null
	var best_distance := enter_distance
	for vehicle in get_tree().get_nodes_in_group("vehicle"):
		var distance := player.global_position.distance_to(vehicle.global_position)
		if distance < best_distance:
			best_distance = distance
			best = vehicle
	return best

func enter_nearest_vehicle() -> void:
	var vehicle := nearest_vehicle()
	if vehicle == null:
		return
	driving = vehicle
	vehicle.active = true
	_set_player_present(false)
	active_changed.emit(vehicle)

func exit_vehicle() -> void:
	if driving == null:
		return
	var side := driving.global_transform.basis.x.normalized()
	player.global_position = driving.global_position - side * 2.2 + Vector3.UP * 0.4
	player.velocity = Vector3.ZERO
	driving.active = false
	if driving is VehicleBody3D:
		driving.engine_force = 0.0
	driving = null
	_set_player_present(true)
	active_changed.emit(player)

func _set_player_present(present: bool) -> void:
	player.visible = present
	player.set_physics_process(present)
	player.get_node("Collision").set_deferred("disabled", not present)
