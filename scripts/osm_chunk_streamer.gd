extends Node3D
## Offline OSM sector streamer. OSM is imported before export; the game itself
## never requests map data from the internet.

@export var chunk_size := 1000.0
@export_range(0, 4) var load_radius := 1
@export var refresh_interval := 0.5

const MANIFEST_PATH := "res://world/manifest.json"
const CHUNK_DIR := "res://world/chunks/"

var _player: Node3D
var _timer := 0.0
var _loaded: Dictionary = {}
var _manifest: Dictionary = {}
var _map_available := false
var _road_material: StandardMaterial3D
var _ground_material: StandardMaterial3D
var _area_materials: Dictionary = {}


func _ready() -> void:
	_road_material = _make_material(Color(0.16, 0.17, 0.18), 0.94)
	_ground_material = _make_material(Color(0.31, 0.39, 0.25), 1.0)
	_player = get_parent().get_node_or_null("Player") as Node3D
	_load_manifest()
	if _map_available:
		_disable_procedural_city()


func _load_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("World manifest is invalid; keeping the procedural fallback.")
		return
	_manifest = parsed
	chunk_size = float(_manifest.get("chunk_size_m", chunk_size))
	_map_available = bool(_manifest.get("boundary_verified", false)) and DirAccess.open(CHUNK_DIR) != null
	if not _map_available:
		push_warning("OSM sectors are missing or their municipal boundary is unverified; keeping the fallback city.")


func _disable_procedural_city() -> void:
	for node_name in ["City", "Traffic", "Peds", "Props", "ParkedCars"]:
		var old_node := get_parent().get_node_or_null(node_name)
		if old_node:
			old_node.visible = false
			old_node.process_mode = Node.PROCESS_MODE_DISABLED


func _process(delta: float) -> void:
	if not _map_available or _player == null:
		return
	_timer += delta
	if _timer < refresh_interval:
		return
	_timer = 0.0
	_update_visible_chunks()


func _update_visible_chunks() -> void:
	var centre_x := int(floor(_player.global_position.x / chunk_size))
	var centre_z := int(floor(_player.global_position.z / chunk_size))
	var wanted: Dictionary = {}
	for x in range(centre_x - load_radius, centre_x + load_radius + 1):
		for z in range(centre_z - load_radius, centre_z + load_radius + 1):
			var key := "%d_%d" % [x, z]
			wanted[key] = true
			if not _loaded.has(key):
				_load_chunk(x, z, key)
	for key in _loaded.keys():
		if not wanted.has(key):
			_loaded[key].queue_free()
			_loaded.erase(key)


func _load_chunk(x: int, z: int, key: String) -> void:
	var path := CHUNK_DIR + key + ".json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("Invalid OSM chunk: " + path)
		return
	var root := Node3D.new()
	root.name = "Chunk_" + key
	add_child(root)
	_build_ground(root, x, z)
	var features: Variant = parsed.get("features", [])
	if features is Array:
		for feature in features:
			if feature is Dictionary:
				_build_feature(root, feature)
	_loaded[key] = root


func _build_ground(parent: Node3D, x: int, z: int) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3((x + 0.5) * chunk_size, -0.28, (z + 0.5) * chunk_size)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(chunk_size, chunk_size)
	mesh.mesh = plane
	mesh.material_override = _ground_material
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(chunk_size, 0.5, chunk_size)
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)


func _build_feature(parent: Node3D, feature: Dictionary) -> void:
	var kind := str(feature.get("kind", ""))
	var points: Variant = feature.get("points", [])
	if not points is Array or points.size() < 2:
		return
	if kind == "road":
		for i in range(points.size() - 1):
			_build_road_segment(parent, points[i], points[i + 1], str(feature.get("highway", "residential")))
	elif kind == "building":
		_build_building(parent, points, feature)
	elif kind == "area":
		_build_area(parent, points, str(feature.get("category", "")))


func _build_road_segment(parent: Node3D, a: Variant, b: Variant, highway: String) -> void:
	if not a is Array or not b is Array or a.size() < 2 or b.size() < 2:
		return
	var start := Vector3(float(a[0]), 0.0, float(a[1]))
	var finish := Vector3(float(b[0]), 0.0, float(b[1]))
	var delta := finish - start
	var length := delta.length()
	if length < 1.0:
		return
	var width := 5.5
	if highway in ["motorway", "trunk", "primary"]:
		width = 8.0
	elif highway in ["secondary", "tertiary"]:
		width = 7.0
	elif highway in ["service", "track", "path", "footway"]:
		width = 3.0
	var body := StaticBody3D.new()
	body.position = (start + finish) * 0.5
	body.rotation.y = atan2(delta.x, delta.z)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, 0.12, length + 0.35)
	mesh.mesh = box
	mesh.material_override = _road_material
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 0.18, length + 0.35)
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)


func _build_area(parent: Node3D, raw_points: Array, category: String) -> void:
	var polygon := PackedVector2Array()
	for point in raw_points:
		if point is Array and point.size() >= 2:
			polygon.append(Vector2(float(point[0]), float(point[1])))
	if polygon.size() > 2 and polygon[0].is_equal_approx(polygon[polygon.size() - 1]):
		polygon.remove_at(polygon.size() - 1)
	if polygon.size() < 3:
		return
	var indices := Geometry2D.triangulate_polygon(polygon)
	if indices.is_empty():
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in indices:
		var point := polygon[index]
		surface.add_vertex(Vector3(point.x, -0.12, point.y))
	surface.generate_normals()
	var mesh := surface.commit()
	if mesh == null:
		return
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	if not _area_materials.has(category):
		_area_materials[category] = _make_material(_area_colour(category), 1.0)
	var material: StandardMaterial3D = _area_materials[category]
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = material
	parent.add_child(instance)


func _area_colour(category: String) -> Color:
	match category:
		"water", "riverbank", "reservoir":
			return Color(0.16, 0.36, 0.48)
		"farmland", "orchard", "vineyard", "plant_nursery":
			return Color(0.39, 0.46, 0.25)
		"forest", "wood":
			return Color(0.19, 0.34, 0.21)
		"grass", "meadow", "scrub":
			return Color(0.37, 0.46, 0.28)
		"residential":
			return Color(0.43, 0.43, 0.38)
		"industrial", "commercial", "retail":
			return Color(0.40, 0.41, 0.40)
		"wetland", "marsh":
			return Color(0.30, 0.42, 0.35)
		_:
			return Color(0.34, 0.40, 0.27)



func _build_building(parent: Node3D, points: Array, feature: Dictionary) -> void:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for point in points:
		if not point is Array or point.size() < 2:
			continue
		min_x = minf(min_x, float(point[0]))
		max_x = maxf(max_x, float(point[0]))
		min_z = minf(min_z, float(point[1]))
		max_z = maxf(max_z, float(point[1]))
	var width := maxf(max_x - min_x, 3.0)
	var depth := maxf(max_z - min_z, 3.0)
	if width > 100.0 or depth > 100.0:
		return
	var levels := float(feature.get("levels", 1.0))
	var height := clampf(float(feature.get("height", levels * 3.2)), 3.0, 45.0)
	var body := StaticBody3D.new()
	body.position = Vector3((min_x + max_x) * 0.5, height * 0.5, (min_z + max_z) * 0.5)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, height, depth)
	mesh.mesh = box
	var material := _make_material(_building_colour(str(feature.get("building", "yes"))), 0.88)
	mesh.material_override = material
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)


func _building_colour(category: String) -> Color:
	match category:
		"house", "residential", "detached":
			return Color(0.69, 0.62, 0.51)
		"industrial", "warehouse":
			return Color(0.52, 0.55, 0.56)
		"commercial", "retail":
			return Color(0.72, 0.68, 0.58)
		_:
			return Color(0.66, 0.64, 0.58)


func _make_material(colour: Color, roughness_value: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness_value
	return material
