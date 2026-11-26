extends RefCounted
## Pure integer math; no engine objects, no engine-version-dependent hash().
# Keep products below 2^53, so the source-level numeric verifier can execute
# these exact integer expressions without loss in JavaScript.
const MASK31 := 2147483647
const SHARES := [50, 32, 18]

static func mix31(value: int) -> int:
	var x: int = value & MASK31
	x = ((x ^ (x >> 16)) * 376095) & MASK31
	x = ((x ^ (x >> 13)) * 376095) & MASK31
	return (x ^ (x >> 16)) & MASK31

static func word(x: int, z: int, index: int, seed: int, salt: int) -> int:
	var a: int = mix31(seed ^ salt)
	a = mix31(a ^ (x & MASK31))
	a = mix31(a ^ (z & MASK31))
	return mix31(a ^ index)

static func rank_index(x: int, z: int, rank: int, seed: int) -> int:
	var left: int = (rank >> 6) & 63
	var right: int = rank & 63
	for round_index in range(4):
		var f: int = word(x, z, right, seed, round_index * 7919) & 63
		var next_value: int = left ^ f
		left = right
		right = next_value
	return (left << 6) | right

static func unit_random(x: int, z: int, index: int, seed: int, salt: int) -> float:
	return float(word(x, z, index, seed, salt) & 16777215) / 16777216.0

# Input: eligible chunks per LOD, maximum ranks per chunk per LOD, caps.
# Output: [selected near/mid/far chunk counts, near/mid/far rank quotas].
# Every selected chunk receives >=1 candidate; disabled tiers receive none.
# Reserve one per selected chunk, share remaining ranks, then distribute spare.
static func allocate(tiers: Array, density: Array, cap: int, chunks: int, upload_cap: int) -> Array:
	var selected: Array = [0, 0, 0]
	var limits: Array = [0, 0, 0]
	var eligible: Array = [0, 0, 0]
	var maximum: Array = [0, 0, 0]
	var available: int = mini(cap, chunks)
	for lod in range(3):
		maximum[lod] = mini(int(density[lod]), upload_cap)
		if maximum[lod] > 0:
			eligible[lod] = int(tiers[lod])
	var remaining: int = available
	for lod in range(3):
		var take: int = mini(eligible[lod], maxi(1, floori(float(available * SHARES[lod]) / 100.0)))
		take = mini(take, remaining)
		selected[lod] = take
		remaining -= take
	for lod in range(3):
		var extra: int = mini(remaining, eligible[lod] - selected[lod])
		selected[lod] += extra
		remaining -= extra
	var spare: int = cap - selected[0] - selected[1] - selected[2]
	var unallocated: int = spare
	var desired: Array = [0, 0, 0]
	var allocation: Array = [0, 0, 0]
	for lod in range(3):
		desired[lod] = selected[lod] * maxi(0, maximum[lod] - 1)
		allocation[lod] = mini(desired[lod], mini(unallocated, floori(float(spare * SHARES[lod]) / 100.0)))
		unallocated -= allocation[lod]
	for lod in range(3):
		var extra: int = mini(unallocated, desired[lod] - allocation[lod])
		allocation[lod] += extra
		unallocated -= extra
	var previous: int = 4096
	for lod in range(3):
		if selected[lod] > 0:
			var quota: int = 1 + floori(float(allocation[lod]) / selected[lod])
			if quota >= 64:
				quota = (quota >> 5) << 5
			quota = mini(quota, previous)
			limits[lod] = quota
			previous = quota
	return [selected, limits]
