extends SceneTree
const Mask = preload("../biome_mask.gd")
var failures := 0
var checks := 0
var fixture_root := ""
var paths: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",message)

func write_text(relative: String, content: String) -> bool:
	var path := fixture_root.path_join(relative)
	if not DirAccess.dir_exists_absolute(path.get_base_dir()) and DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return false
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.close()
	if not paths.has(path):
		paths.append(path)
	return true

func write_source(relative: String, content: String, hashes: Dictionary) -> bool:
	if not write_text(relative,content):
		return false
	hashes[relative] = FileAccess.get_sha256(fixture_root.path_join(relative))
	return true

func finish() -> void:
	for path: String in paths:
		DirAccess.remove_absolute(path)
	var directories := ["content/scenery/packs","content/scenery/avoidance","content/scenery/lake","content/scenery","content","data/world","data","mask"]
	for directory: String in directories:
		DirAccess.remove_absolute(fixture_root.path_join(directory))
	DirAccess.remove_absolute(fixture_root)
	print("[GroundCoverMask] ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func _run() -> void:
	fixture_root = "user://ground_cover_provenance_"+str(Time.get_ticks_usec())
	if DirAccess.make_dir_recursive_absolute(fixture_root.path_join("mask")) != OK:
		check(false,"fixture directory")
		finish()
		return
	var hashes: Dictionary = {}
	for filename: String in Mask.WORLD_FILES:
		check(write_source("data/world/"+filename,"fixture "+filename,hashes),"fixture world source")
	check(write_source("data/world/vegetation.bin","fixture vegetation",hashes),"fixture vegetation")
	var pack_path := "content/scenery/packs/example.json"
	var scenery := {"region_packs":[{"path":pack_path}]}
	check(write_source("content/scenery/manifest.json",JSON.stringify(scenery),hashes),"fixture scenery manifest")
	check(write_source(pack_path,"fixture pack",hashes),"fixture scenery pack")
	check(write_source("content/scenery/avoidance/race_gate_reservations_v1.json","fixture zones",hashes),"fixture reservations")
	check(write_source("content/scenery/lake/water_cells_v1.json","fixture water",hashes),"fixture water")
	var raw := PackedByteArray()
	raw.resize(4000000)
	raw[0]=255
	raw[4]=41
	raw[4000]=82
	raw[3999996]=193
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(raw)
	var raw_path := fixture_root.path_join("mask/biome_rgba8.bin")
	var file := FileAccess.open(raw_path,FileAccess.WRITE)
	if file == null or failures > 0:
		check(false,"fixture mask creation")
		finish()
		return
	file.store_buffer(raw)
	file.close()
	paths.append(raw_path)
	var manifest := {"schema_version":1,"width":1000,"height":1000,"cell_size_m":2,"origin_x":-1000,"origin_z":-1000,"byte_order":"RGBA","channels":Mask.CHANNELS,"row_order":"z_ascending_x_ascending","source_hashes":hashes,"seed":17,"sha256":hash_context.finish().hex_encode()}
	check(write_text("mask/manifest.json",JSON.stringify(manifest)),"fixture mask manifest")
	var mask := Mask.new()
	var mask_dir := fixture_root.path_join("mask")
	var world_dir := fixture_root.path_join("data/world")
	check(mask.load_package(mask_dir),"mask read")
	check(mask.verify_production_sources(world_dir,fixture_root),"all consumed source hashes")
	check(is_equal_approx(mask.sample(-999,-999).x,1.0),"origin")
	check(is_equal_approx(mask.sample(-997,-999).x,41.0/255.0),"x fastest")
	check(is_equal_approx(mask.sample(-999,-997).x,82.0/255.0),"z next row")
	check(is_equal_approx(mask.sample(999.99,999.99).x,193.0/255.0),"positive edge")
	check(mask.sample(1000,999)==Vector4.ZERO,"exclusive upper bound")
	check(write_text("content/scenery/lake/water_cells_v1.json","modified water"),"mutate water")
	check(not mask.verify_production_sources(world_dir,fixture_root) and mask.bytes.is_empty(),"stale water fails closed")
	check(write_text("content/scenery/lake/water_cells_v1.json","fixture water"),"restore water")
	check(mask.load_package(mask_dir) and mask.verify_production_sources(world_dir,fixture_root),"restored sources")
	check(write_text("data/world/premium_foliage.bin","new premium cache"),"create formerly absent optional cache")
	check(not mask.verify_production_sources(world_dir,fixture_root),"new optional cache invalidates mask")
	DirAccess.remove_absolute(fixture_root.path_join("data/world/premium_foliage.bin"))
	check(mask.load_package(mask_dir) and mask.verify_production_sources(world_dir,fixture_root),"optional cache restored")
	scenery.region_packs=[{"path":"content/scenery/packs/../../outside.json"}]
	check(write_source("content/scenery/manifest.json",JSON.stringify(scenery),hashes),"malformed pack manifest")
	check(write_text("mask/manifest.json",JSON.stringify(manifest)),"update fixture digest")
	check(mask.load_package(mask_dir) and not mask.verify_production_sources(world_dir,fixture_root),"unsafe pack path rejected before access")
	finish()
