extends SceneTree
const Placement = preload("../placement_math.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures <= 20:
			printerr("FAIL ",message)

func _run() -> void:
	var mix_input := [0,1,-1,20261125]
	var mix_expected := [0,1868151895,441729704,765673493]
	var rank_input := [0,1,31,4095]
	var rank_expected := [3267,3016,3306,3427]
	var salts := [11,17,23,53]
	var words := [1619583150,193340440,1851735536,1254859719]
	for i in range(4):
		check(Placement.mix31(mix_input[i])==mix_expected[i],"integer mix known vector")
		check(Placement.rank_index(-17,62,rank_input[i],20261125)==rank_expected[i],"rank known vector")
		check(Placement.word(-17,62,123,20261125,salts[i])==words[i],"word known vector")
	check(Placement.allocate([4,20,56],[1000,400,100],1,120,1800)==[[1,0,0],[1,0,0]],"cap one known vector")
	check(Placement.allocate([4,20,56],[1000,400,100],1000,120,1800)==[[4,20,56],[96,15,3]],"cap 1000 known vector")
	for radii: Array in [[8.0,12.0,16.0],[152.0,156.0,160.0],[25.0,65.0,130.0]]:
		var near := float(radii[0])
		var mid := float(radii[1])
		var far := float(radii[2])
		var margin := Placement.lod_margin(near,mid,far)
		check(margin>0 and margin*2<minf(mid-near,far-mid),"nonoverlapping LOD bands")
		for previous in [-1,0,1,2]:
			check(Placement.choose_lod(near-margin-0.1,near,mid,previous,margin)==0,"near jump")
			check(Placement.choose_lod((near+mid)*0.5,near,mid,previous,margin)==1,"mid jump")
			check(Placement.choose_lod(mid+margin+0.1,near,mid,previous,margin)==2,"far jump")
	for seed: int in [-2147483648,-1,0,1,20261125,2147483647]:
		for x: int in [-63,-17,0,62]:
			for z: int in [-63,0,62]:
				var seen := PackedByteArray()
				seen.resize(4096)
				for rank in range(4096):
					var idx := Placement.rank_index(x,z,rank,seed)
					if idx < 0 or idx >= 4096:
						check(false,"rank outside permutation")
						continue
					check(seen[idx]==0,"duplicate rank")
					seen[idx]=1
					var value := Placement.unit_random(x,z,idx,seed,11)
					check(value>=0.0 and value<1.0,"unit random bounds")
	for cap: int in [1,2,3,31,63,64,999,12000,90000]:
		for chunks: int in [1,2,3,12,360]:
			for tier: Array in [[0,0,0],[1,1,1],[4,20,56],[12,68,240]]:
				for density: Array in [[0,0,0],[100,0,0],[0,0,1],[2,2,2],[3456,1229,328]]:
					var plan := Placement.allocate(tier,density,cap,chunks,4200)
					var count := 0
					var reserved := 0
					var previous := 4096
					for lod in range(3):
						var selected := int(plan[0][lod])
						var quota := int(plan[1][lod])
						check(selected>=0 and selected<=int(tier[lod]),"eligible count")
						check(quota>=0 and quota<=mini(int(density[lod]),4200),"quota bound")
						check((selected>0)==(quota>0),"zero work exclusion")
						if selected>0:
							check(quota<=previous,"nested quotas")
							previous=quota
						count+=selected
						reserved+=selected*quota
					check(count<=mini(cap,chunks) and reserved<=cap,"total caps")
	print("[GroundCoverNumeric] ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
