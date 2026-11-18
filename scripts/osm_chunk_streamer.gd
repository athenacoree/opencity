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
var _dirt_road_material: StandardMaterial3D
var _sidewalk_material: StandardMaterial3D
var _window_material: StandardMaterial3D
var _lamp_material: StandardMaterial3D
var _ground_material: StandardMaterial3D
var _waterway_material: StandardMaterial3D
var _area_materials: Dictionary = {}
var _point_materials: Dictionary = {}
var _building_materials: Dictionary = {}
var _life_simulation: Node
var _last_power_state := true


func _ready() -> void:
	_road_material = _make_material(Color(0.16, 0.17, 0.18), 0.94)
	_dirt_road_material = _make_material(Color(0.34, 0.29, 0.20), 1.0)
	_sidewalk_material = _make_material(Color(0.48, 0.47, 0.43), 0.96)
	_window_material = _make_material(Color(0.12, 0.25, 0.32), 0.28)
	_window_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_lamp_material = _make_material(Color(0.96, 0.78, 0.40), 0.35)
	_lamp_material.emission_enabled = true
	_lamp_material.emission = Color(0.95, 0.62, 0.24)
	_ground_material = _make_material(Color(0.31, 0.39, 0.25), 1.0)
	_waterway_material = _make_material(Color(0.12, 0.36, 0.50), 0.28)
	_player = get_parent().get_node_or_null("Player") as Node3D
	_life_simulation = get_parent().get_node_or_null("CubaLife")
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
	_update_neighborhood_lighting()


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


func _update_neighborhood_lighting() -> void:
	if _life_simulation == null or _player == null:
		return
	var powered: bool = _life_simulation.get_sector_power(_player.global_position)
	if powered == _last_power_state:
		return
	_last_power_state = powered
	_window_material.emission_enabled = powered
	_window_material.emission = Color(0.92, 0.67, 0.32) if powered else Color(0, 0, 0)
	_window_material.emission_energy_multiplier = 0.55 if powered else 0.0
	_window_material.albedo_color = Color(0.38, 0.30, 0.18) if powered else Color(0.035, 0.045, 0.06)
	for material in _point_materials.values():
		if material is StandardMaterial3D and material.emission_enabled:
			material.emission_energy_multiplier = 0.9 if powered else 0.0


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
	if not points is Array:
		return
	if kind == "poi" or kind == "vegetation":
		if points.is_empty() or not points[0] is Array or points[0].size() < 2:
			return
		_build_point_feature(parent, points[0], feature, kind)
		return
	if points.size() < 2:
		return
	if kind == "road":
		for i in range(points.size() - 1):
			_build_road_segment(parent, points[i], points[i + 1], str(feature.get("highway", "residential")), str(feature.get("surface", "")))
	elif kind == "waterway":
		for i in range(points.size() - 1):
			_build_waterway_segment(parent, points[i], points[i + 1])
	elif kind == "building":
		_build_building(parent, points, feature)
	elif kind == "area":
		_build_area(parent, points, str(feature.get("category", "")))


func _build_road_segment(parent: Node3D, a: Variant, b: Variant, highway: String, surface: String = "") -> void:
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
	elif highway in ["service", "track", "path", "footway", "cycleway"]:
		width = 3.0
	var road := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, 0.12, length + 0.35)
	road.mesh = box
	road.material_override = _dirt_road_material if surface in ["dirt", "ground", "gravel", "unpaved", "sand"] or highway == "track" else _road_material
	road.position = (start + finish) * 0.5
	road.rotation.y = atan2(delta.x, delta.z)
	parent.add_child(road)

	# Add restrained sidewalks only to streets where pedestrians are expected.
	if highway in ["primary", "secondary", "tertiary", "residential", "living_street", "unclassified"] and length >= 5.0:
		var side := Vector3(delta.z, 0.0, -delta.x).normalized()
		for sign in [-1.0, 1.0]:
			var sidewalk := MeshInstance3D.new()
			var slab := BoxMesh.new()
			slab.size = Vector3(1.35, 0.10, length + 0.25)
			sidewalk.mesh = slab
			sidewalk.material_override = _sidewalk_material
			sidewalk.position = (start + finish) * 0.5 + side * sign * (width * 0.5 + 0.82)
			sidewalk.position.y = 0.015
			sidewalk.rotation.y = road.rotation.y
			parent.add_child(sidewalk)

	# One low-cost decorative lamp on sufficiently long main-road segments.
	if highway in ["primary", "secondary", "tertiary"] and length >= 32.0:
		_build_street_lamp(parent, (start + finish) * 0.5, delta, width)


func _build_street_lamp(parent: Node3D, centre: Vector3, road_delta: Vector3, road_width: float) -> void:
	var side := Vector3(road_delta.z, 0.0, -road_delta.x).normalized()
	var base := centre + side * (road_width * 0.5 + 2.0)
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.055
	pole_mesh.bottom_radius = 0.09
	pole_mesh.height = 5.2
	pole.mesh = pole_mesh
	pole.material_override = _point_material("street_lamp_pole", Color(0.18, 0.19, 0.20))
	pole.position = base + Vector3(0.0, 2.6, 0.0)
	parent.add_child(pole)
	var arm := MeshInstance3D.new()
	var arm_mesh := CylinderMesh.new()
	arm_mesh.top_radius = 0.045
	arm_mesh.bottom_radius = 0.045
	arm_mesh.height = 1.15
	arm.mesh = arm_mesh
	arm.material_override = pole.material_override
	arm.position = base + Vector3(0.0, 5.05, 0.0) - side * 0.52
	arm.rotation.z = PI * 0.5
	parent.add_child(arm)
	var lamp := MeshInstance3D.new()
	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(0.38, 0.12, 0.22)
	lamp.mesh = lamp_mesh
	lamp.material_override = _lamp_material
	lamp.position = base + Vector3(0.0, 5.02, 0.0) - side * 1.0
	parent.add_child(lamp)

func _build_waterway_segment(parent: Node3D, a: Variant, b: Variant) -> void:
	if not a is Array or not b is Array or a.size() < 2 or b.size() < 2:
		return
	var start := Vector3(float(a[0]), -0.015, float(a[1]))
	var finish := Vector3(float(b[0]), -0.015, float(b[1]))
	var delta := finish - start
	var length := delta.length()
	if length < 1.0:
		return
	var channel := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.2, 0.06, length + 0.25)
	channel.mesh = box
	channel.material_override = _waterway_material
	channel.position = (start + finish) * 0.5
	channel.rotation.y = atan2(delta.x, delta.z)
	parent.add_child(channel)


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


func _build_point_feature(parent: Node3D, point: Array, feature: Dictionary, kind: String) -> void:
	var category := str(feature.get("category", ""))
	var marker := Node3D.new()
	marker.position = Vector3(float(point[0]), 0.0, float(point[1]))
	marker.name = "%s_%s" % [kind, str(feature.get("osm_id", "unknown"))]
	parent.add_child(marker)
	if kind == "vegetation":
		var species := str(feature.get("species", "")).to_lower()
		var genus := str(feature.get("genus", "")).to_lower()
		var taxon := str(feature.get("taxon", "")).to_lower()
		var leaf_type := str(feature.get("leaf_type", "")).to_lower()
		var is_palm := "palm" in species or "palma" in species or "cocos" in species or "phoenix" in species or "arecaceae" in taxon or "arecaceae" in genus or leaf_type == "palm"
		var trunk := MeshInstance3D.new()
		var trunk_mesh := CylinderMesh.new()
		trunk_mesh.top_radius = 0.08 if is_palm else 0.10
		trunk_mesh.bottom_radius = 0.15
		var tree_height := clampf(float(feature.get("height", 5.0)), 2.0, 18.0)
		trunk_mesh.height = tree_height * (0.78 if is_palm else 0.38)
		trunk.mesh = trunk_mesh
		trunk.position.y = trunk_mesh.height * 0.5
		trunk.material_override = _point_material("tree_trunk", Color(0.30, 0.20, 0.12))
		marker.add_child(trunk)
		if is_palm:
			for i in range(7):
				var frond := MeshInstance3D.new()
				var frond_mesh := CylinderMesh.new()
				frond_mesh.top_radius = 0.015
				frond_mesh.bottom_radius = 0.055
				frond_mesh.height = tree_height * 0.38
				frond.mesh = frond_mesh
				frond.position.y = tree_height * 0.78
				frond.rotation = Vector3(deg_to_rad(58.0), TAU * float(i) / 7.0, 0.0)
				frond.material_override = _point_material("palm_leaf", Color(0.17, 0.36, 0.17))
				marker.add_child(frond)
		else:
			for i in range(3):
				var crown := MeshInstance3D.new()
				var crown_mesh := SphereMesh.new()
				crown_mesh.radius = tree_height * (0.15 if i == 0 else 0.12)
				crown_mesh.height = tree_height * 0.28
				crown.mesh = crown_mesh
				crown.position = Vector3(0.0, tree_height * 0.68 + float(i % 2) * tree_height * 0.04, (float(i) - 1.0) * tree_height * 0.07)
				crown.material_override = _point_material("tree_crown", Color(0.16, 0.34, 0.17))
				marker.add_child(crown)
	else:
		var post := MeshInstance3D.new()
		var post_mesh := CylinderMesh.new()
		post_mesh.top_radius = 0.20
		post_mesh.bottom_radius = 0.28
		post_mesh.height = 0.9
		post.mesh = post_mesh
		post.position.y = 0.45
		var colour := Color(0.78, 0.62, 0.28)
		if category in ["amenity", "healthcare"]:
			colour = Color(0.30, 0.58, 0.78)
		elif category in ["shop", "craft"]:
			colour = Color(0.72, 0.42, 0.30)
		elif category in ["tourism", "leisure"]:
			colour = Color(0.48, 0.66, 0.42)
		elif category == "office":
			colour = Color(0.48, 0.50, 0.72)
		post.material_override = _point_material("poi_" + category, colour)
		marker.add_child(post)
		var place_name := str(feature.get("name", "")).strip_edges()
		if not place_name.is_empty():
			var label := Label3D.new()
			label.text = place_name
			label.font_size = 28
			label.pixel_size = 0.006
			label.position.y = 2.0
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.outline_size = 5
			label.modulate = Color(1.0, 0.96, 0.84)
			marker.add_child(label)

func _point_material(key: String, colour: Color) -> StandardMaterial3D:
	if not _point_materials.has(key):
		_point_materials[key] = _make_material(colour, 0.9)
	return _point_materials[key]


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
		"park", "garden", "playground", "pitch", "nature_reserve":
			return Color(0.25, 0.43, 0.24)
		_:
			return Color(0.34, 0.40, 0.27)



func _build_building(parent: Node3D, points: Array, feature: Dictionary) -> void:
	var polygon := PackedVector2Array()
	for point in points:
		if point is Array and point.size() >= 2:
			polygon.append(Vector2(float(point[0]), float(point[1])))
	if polygon.size() > 2 and polygon[0].is_equal_approx(polygon[polygon.size() - 1]):
		polygon.remove_at(polygon.size() - 1)
	if polygon.size() < 3:
		return
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for point in polygon:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_z = minf(min_z, point.y)
		max_z = maxf(max_z, point.y)
	var width := max_x - min_x
	var depth := max_z - min_z
	if width < 1.0 or depth < 1.0 or width > 100.0 or depth > 100.0:
		return
	var levels := float(feature.get("levels", 1.0))
	var height := clampf(float(feature.get("height", levels * 3.2)), 3.0, 45.0)
	var category := str(feature.get("building", "yes"))
	var body := StaticBody3D.new()
	body.name = "Building_%s" % str(feature.get("osm_id", "unknown"))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roof_indices := Geometry2D.triangulate_polygon(polygon)
	if roof_indices.is_empty():
		return
	for index in roof_indices:
		var p := polygon[index]
		surface.add_vertex(Vector3(p.x, height, p.y))
	for i in range(polygon.size()):
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		surface.add_vertex(Vector3(a.x, 0.0, a.y))
		surface.add_vertex(Vector3(b.x, 0.0, b.y))
		surface.add_vertex(Vector3(b.x, height, b.y))
		surface.add_vertex(Vector3(a.x, 0.0, a.y))
		surface.add_vertex(Vector3(b.x, height, b.y))
		surface.add_vertex(Vector3(a.x, height, a.y))
	surface.generate_normals()
	var building_mesh := surface.commit()
	if building_mesh == null:
		return
	var instance := MeshInstance3D.new()
	instance.mesh = building_mesh
	if not _building_materials.has(category):
		var material := _make_material(_building_colour(category), 0.88)
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_building_materials[category] = material
	instance.material_override = _building_materials[category]
	body.add_child(instance)
	_build_building_windows(body, polygon, height, levels)
	var building_name := str(feature.get("name", "")).strip_edges()
	if not building_name.is_empty():
		var sign := Label3D.new()
		sign.text = building_name
		sign.font_size = 30
		sign.pixel_size = 0.007
		sign.position = Vector3((min_x + max_x) * 0.5, height + 1.2, (min_z + max_z) * 0.5)
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sign.outline_size = 5
		sign.modulate = Color(1.0, 0.96, 0.84)
		body.add_child(sign)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, depth)
	collision.shape = shape
	collision.position = Vector3((min_x + max_x) * 0.5, height * 0.5, (min_z + max_z) * 0.5)
	body.add_child(collision)
	parent.add_child(body)


func _build_building_windows(parent: Node3D, polygon: PackedVector2Array, height: float, levels_value: float) -> void:
	var floors := clampi(int(ceil(levels_value)), 1, 10)
	var centre := Vector2.ZERO
	for point in polygon:
		centre += point
	centre /= float(polygon.size())
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var window_count := 0
	for i in range(polygon.size()):
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var edge := b - a
		var length := edge.length()
		if length < 4.5:
			continue
		var direction := edge.normalized()
		var outward := ((a + b) * 0.5 - centre).normalized() * 0.025
		var count := mini(12, maxi(1, int(length / 3.2)))
		for floor_index in range(floors):
			var y := 1.25 + float(floor_index) * 3.0
			if y + 1.0 > height - 0.35:
				continue
			for window_index in range(count):
				var t := (float(window_index) + 0.5) / float(count)
				var half_width := minf(0.42, length / float(count) * 0.22)
				var centre_point := a + edge * t
				var left := centre_point - direction * half_width
				var right := centre_point + direction * half_width
				var bottom_left := Vector3(left.x + outward.x, y, left.y + outward.y)
				var bottom_right := Vector3(right.x + outward.x, y, right.y + outward.y)
				var top_right := Vector3(right.x + outward.x, y + 0.95, right.y + outward.y)
				var top_left := Vector3(left.x + outward.x, y + 0.95, left.y + outward.y)
				surface.add_vertex(bottom_left)
				surface.add_vertex(bottom_right)
				surface.add_vertex(top_right)
				surface.add_vertex(bottom_left)
				surface.add_vertex(top_right)
				surface.add_vertex(top_left)
				window_count += 1
	if window_count == 0:
		return
	surface.generate_normals()
	var mesh := surface.commit()
	if mesh == null:
		return
	var windows := MeshInstance3D.new()
	windows.mesh = mesh
	windows.material_override = _window_material
	parent.add_child(windows)

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
