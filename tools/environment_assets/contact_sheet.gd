extends Node3D
## Local Forward+ comparison: two LODs for each species; optional existing scan row.
const MANIFEST := "res://assets/environment_overhaul/manifest.json"
const PremiumMesh = preload("res://scripts/integration/premium_mesh.gd")

func _ready() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#b5c5d3")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#d3deed")
	environment.ambient_light_energy = 0.65
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -34, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(12.0, 0.12, 8.5)
	var floor_instance := MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color("#716a50")
	ground.roughness = 0.95
	floor_instance.material_override = ground
	floor_instance.position = Vector3(0, -0.06, 0)
	add_child(floor_instance)
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not manifest is Dictionary:
		push_error("Missing candidate manifest")
		return
	var assets: Array = manifest["assets"]
	for i: int in range(assets.size()):
		var entry: Dictionary = assets[i]
		for lod: int in range(2):
			var x: float = (i - 2) * 2.05
			var z: float = -1.9 + lod * 2.15
			var path: String = entry["lod%d" % lod]
			var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
			if packed != null:
				var holder := Node3D.new()
				holder.position = Vector3(x, 0, z)
				add_child(holder)
				holder.add_child(packed.instantiate())
				_label("%s LOD%d" % [entry["species_id"], lod], Vector3(x, 0.025, z + 0.67))
			else:
				_label("MISSING " + str(entry["species_id"]), Vector3(x, 0.025, z + 0.67))
	for i: int in range(2):
		var species: String = "fern" if i == 0 else "fir"
		var limit := Vector3(1.05, 0.44, 1.05) if i == 0 else Vector3(0.95, 1.65, 0.95)
		var existing: ArrayMesh = null
		var raw_path: String = "res://assets/premium_runtime/%s.glb" % species
		var file := FileAccess.open(raw_path, FileAccess.READ)
		if file != null:
			var magic: String = file.get_buffer(4).get_string_from_ascii()
			file.close()
			if magic == "glTF":
				existing = PremiumMesh.fit(species, limit)
		var position_m := Vector3(-2.05 + i * 4.1, 0, 2.55)
		if existing != null:
			var display := MeshInstance3D.new()
			display.mesh = existing
			display.position = position_m
			add_child(display)
			_label("Existing " + species + " (scan)", position_m + Vector3(0, 0.025, 0.68))
		else:
			_label("Existing " + species + " unavailable", position_m + Vector3(0, 0.025, 0.68))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13.4
	add_child(camera)
	camera.position = Vector3(0, 8.5, 11)
	camera.look_at(Vector3(0, 0.35, 0.1))
	camera.current = true

func _label(value: String, location: Vector3) -> void:
	var label := Label3D.new()
	label.text = value
	label.font_size = 48
	label.pixel_size = 0.0035
	label.outline_size = 10
	label.modulate = Color.WHITE
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = location + Vector3(0, 0.13, 0)
	add_child(label)
