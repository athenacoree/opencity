extends Node3D
## Owns the on-foot / in-car state.

signal active_changed(node: Node3D)

@export var enter_distance := 4.5
@onready var player: CharacterBody3D = $Player
var driving: RigidBody3D = null

func _ready() -> void:
	add_to_group("game")
	for vehicle in get_tree().get_nodes_in_group("vehicle"):
		vehicle.active = false
	# Load only after the world and player nodes have completed _ready().
	call_deferred("_load_local_position")

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
