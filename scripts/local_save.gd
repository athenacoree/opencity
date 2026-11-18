extends Node
## Minimal offline save: stores the last controlled position on this device.

const SAVE_PATH := "user://guira_save.json"
const SAVE_VERSION := 1

func save_position(target: Node3D) -> bool:
	if target == null:
		return false
	var data := {
		"version": SAVE_VERSION,
		"player": {
			"position": [target.global_position.x, target.global_position.y, target.global_position.z],
			"rotation_y": target.global_rotation.y
		},
		"saved_at_utc": Time.get_datetime_string_from_system(true)
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not open local save file for writing.")
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	return true

func load_position(target: Node3D) -> bool:
	if target == null or not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("Could not open local save file.")
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("Local save is invalid; starting at the default spawn.")
		return false
	if int(parsed.get("version", 0)) != SAVE_VERSION:
		push_warning("Local save version is unsupported; starting at the default spawn.")
		return false
	var player_data: Variant = parsed.get("player", {})
	if not player_data is Dictionary:
		return false
	var position_data: Variant = player_data.get("position", [])
	if not position_data is Array or position_data.size() != 3:
		return false
	target.global_position = Vector3(float(position_data[0]), float(position_data[1]), float(position_data[2]))
	target.rotation.y = float(player_data.get("rotation_y", 0.0))
	if target is CharacterBody3D:
		target.velocity = Vector3.ZERO
	return true
