extends Node
## Offline Cuban daily-life simulation. Values are fictional gameplay tuning,
## not live statistics or official Cuban prices/salaries.

signal world_state_changed

const CONFIG_PATH := "res://world/cuba_life_config.json"
const SAVE_PATH := "user://guira_life_profile.json"

var config: Dictionary = {}
var game_minutes := 8.0 * 60.0
var game_day := 1
var player_money_cup := 3500
var selected_house_id := ""
var selected_job_id := "teacher"
var mission_index := 0
var intro_seen := false
var _save_timer := 0.0
var _last_hour := -1


func _ready() -> void:
	_load_config()
	_load_profile()


func _process(delta: float) -> void:
	var world: Dictionary = config.get("world", {})
	game_minutes += delta * float(world.get("time_scale_game_minutes_per_real_second", 0.5))
	while game_minutes >= 1440.0:
		game_minutes -= 1440.0
		game_day += 1
		world_state_changed.emit()
	var hour := int(game_minutes / 60.0)
	if hour != _last_hour:
		_last_hour = hour
		world_state_changed.emit()
	_save_timer += delta
	if _save_timer >= 30.0:
		_save_timer = 0.0
		_save_profile()


func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_warning("Cuban life config missing; simulation will use safe defaults.")
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		config = parsed
		var world: Dictionary = config.get("world", {})
		game_minutes = 8.0 * 60.0
		player_money_cup = int(config.get("economy", {}).get("starting_money_cup", 3500))


func _load_profile() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	player_money_cup = int(parsed.get("money_cup", player_money_cup))
	selected_house_id = str(parsed.get("house_id", ""))
	selected_job_id = str(parsed.get("job_id", selected_job_id))
	mission_index = int(parsed.get("mission_index", 0))
	intro_seen = bool(parsed.get("intro_seen", false))
	game_day = maxi(1, int(parsed.get("day", 1)))
	game_minutes = clampf(float(parsed.get("minutes", game_minutes)), 0.0, 1439.99)


func _save_profile() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"money_cup": player_money_cup,
		"house_id": selected_house_id,
		"job_id": selected_job_id,
		"mission_index": mission_index,
		"intro_seen": intro_seen,
		"day": game_day,
		"minutes": game_minutes
	}))
	file.flush()


func get_clock_text() -> String:
	var hour := int(game_minutes / 60.0)
	var minute := int(fmod(game_minutes, 60.0))
	return "%02d:%02d" % [hour, minute]


func get_exchange_rate() -> float:
	var world: Dictionary = config.get("world", {})
	var base := float(world.get("base_exchange_cup_per_usd", 420.0))
	var variation := float(world.get("exchange_daily_variation", 0.025))
	return base * (1.0 + sin(float(game_day) * 0.71) * variation)


func get_price_index() -> float:
	var world: Dictionary = config.get("world", {})
	var variation := float(world.get("price_daily_variation", 0.018))
	return 1.0 + sin(float(game_day) * 0.43 + 0.8) * variation + float(game_day - 1) * 0.001


func get_product_price(product_id: String) -> int:
	var economy: Dictionary = config.get("economy", {})
	for product in economy.get("products", []):
		if str(product.get("id", "")) == product_id:
			return maxi(1, roundi(float(product.get("base_price_cup", 1)) * get_price_index()))
	return 0


func get_job_salary(job_id: String) -> int:
	var economy: Dictionary = config.get("economy", {})
	for job in economy.get("jobs", []):
		if str(job.get("id", "")) == job_id:
			return int(job.get("monthly_salary_cup", 0))
	return 0


func get_sector_power(position: Vector3) -> bool:
	# Outages rotate by 1 km map sector. This is a fictional gameplay model,
	# not a claim about the real electricity schedule of a specific block.
	var world: Dictionary = config.get("world", {})
	var rotation := maxi(1, int(world.get("outage_rotation_game_minutes", 180)))
	var outage_share := clampf(float(world.get("outage_share_of_sectors", 0.4)), 0.0, 0.9)
	var sector_x := int(floor(position.x / 1000.0))
	var sector_z := int(floor(position.z / 1000.0))
	var sector_code := posmod(sector_x * 31 + sector_z * 17, 10)
	var rotation_slot := int(floor((float(game_day - 1) * 1440.0 + game_minutes) / float(rotation)))
	var outage_slots := roundi(outage_share * 10.0)
	return posmod(sector_code + rotation_slot, 10) >= outage_slots


func get_mobile_signal(position: Vector3) -> int:
	# Weak power areas and rural distance reduce simulated signal quality.
	var bars := 4
	if not get_sector_power(position):
		bars -= 2
	if Vector2(position.x, position.z).length() > 7000.0:
		bars -= 1
	if Vector2(position.x, position.z).length() > 11500.0:
		bars -= 1
	return clampi(bars, 0, 4)


func is_shop_open(shop_id: String) -> bool:
	var hour := int(game_minutes / 60.0)
	for shop in config.get("shops", []):
		if str(shop.get("id", "")) != shop_id:
			continue
		var opens := int(shop.get("opens", 8))
		var closes := int(shop.get("closes", 17))
		if opens <= closes:
			return hour >= opens and hour < closes
		return hour >= opens or hour < closes
	return false


func get_story_title() -> String:
	return str(config.get("story", {}).get("title", "Güira de Melena"))


func get_story_intro() -> String:
	return str(config.get("story", {}).get("intro", ""))


func mark_intro_seen() -> void:
	intro_seen = true
	_save_profile()


func get_house_options() -> Array:
	return config.get("houses", [])


func get_job_options() -> Array:
	return config.get("economy", {}).get("jobs", [])


func select_house(house_id: String) -> bool:
	for house in config.get("houses", []):
		if str(house.get("id", "")) == house_id:
			selected_house_id = house_id
			_save_profile()
			world_state_changed.emit()
			return true
	return false


func set_job(job_id: String) -> bool:
	if get_job_salary(job_id) <= 0:
		return false
	selected_job_id = job_id
	_save_profile()
	world_state_changed.emit()
	return true


func get_current_mission() -> Dictionary:
	var story: Dictionary = config.get("story", {})
	var missions: Array = story.get("missions", [])
	if mission_index < 0 or mission_index >= missions.size():
		return {}
	return missions[mission_index]


func complete_current_mission() -> bool:
	var mission := get_current_mission()
	if mission.is_empty():
		return false
	player_money_cup += int(mission.get("reward_cup", 0))
	mission_index += 1
	_save_profile()
	world_state_changed.emit()
	return true


func get_hud_summary(position: Vector3) -> String:
	var powered := get_sector_power(position)
	var signal_bars := get_mobile_signal(position)
	var power_text := "Luz: sí" if powered else "Luz: no"
	var signal_text := "Señal: " + "▮".repeat(signal_bars) + "▯".repeat(4 - signal_bars)
	return "%s   %s   %s   %s CUP   1 USD ≈ %d CUP   Día %d" % [
		get_clock_text(), power_text, signal_text, _format_money(player_money_cup), roundi(get_exchange_rate()), game_day
	]


func _format_money(value: int) -> String:
	return str(value)
