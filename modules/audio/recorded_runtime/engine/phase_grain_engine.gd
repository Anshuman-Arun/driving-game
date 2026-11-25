class_name PhaseGrainEngine
extends Node
## Recorded multi-cycle grains, one sample-clock firing phase shared across
## every RPM and load anchor. No oscillator and no independent note retriggers.
const RATE := 32000
const SPC := 256
const VARIANTS := 6
# Overlap only the transition, preserving the original take's roughness.
const OVERLAP_FRACTION := 0.5
const MIN_QUEUE := 2048
const HEADLESS_QUEUE := 4096
const MAX_QUEUE := 6144

var rows: Array[Dictionary] = []
var on_indices: Array[int] = []
var off_indices: Array[int] = []
var order := 6.0
var hop := 12
var grain_size := 12 * 2 * SPC + 1
var phase := 0.0
## Unwrapped firing-cycle clock, shared by all active anchors.
var rpm := 900.0
var load_amount := 0.0
var gain := 0.0
var idle_gain := 0.58
var direct: AudioStreamPlayer
var mirror: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var wet_playback: AudioStreamGeneratorPlayback
var capacity := 0
var target_queue := MIN_QUEUE
var mirror_resyncs := 0
var push_failures := 0
var prepared := false
var generated_frames := 0
var max_render_usec := 0
var diagnostics: Array[Dictionary] = []
var texture_balance := false
var native_stable := false
var clipped_frames := 0
var cruise_enabled := false
var cruise_target := 0.0
var cruise_mix := 0.0


func prepare(loops: Array, wavs: Dictionary, firing_order: float, idle: float, idle_level: float, balance_texture: bool = false, extended_grains: bool = true, stable_native: bool = false) -> bool:
	rows.clear()
	on_indices.clear()
	off_indices.clear()
	diagnostics.clear()
	prepared = false
	order = firing_order
	texture_balance = balance_texture
	native_stable = stable_native
	cruise_enabled = stable_native and OS.get_environment("ASTER_CRUISE_STABLE") != "0"
	# Each hop is a complete 720-degree combustion cycle, not an arbitrary
	# number of firing pulses. V12 and V8 retain their own cadence.
	hop = maxi(2, roundi(order * 2.0))
	grain_size = hop * 2 * SPC + 1
	idle_gain = idle_level
	var started := Time.get_ticks_usec()
	for entry in loops:
		var fname := str(entry["file"])
		var wav: AudioStreamWAV = wavs.get(fname)
		if wav == null or wav.format != AudioStreamWAV.FORMAT_16_BITS or wav.stereo:
			return false
		var anchor_rpm := float(entry["rpm"])
		# At high RPM a one-engine-cycle hop replaces the take 60–70 times/s.
		# Prefer 8 whole engine cycles when the recording has sufficient room;
		# fall back gracefully for the very short coast source recordings.
		var row_hop := hop
		if extended_grains and (native_stable or anchor_rpm >= 4000.0):
			for multiplier in [8, 4, 2]:
				var candidate := hop * int(multiplier)
				var required := (2.0*candidate+6.0)*float(wav.mix_rate)/(anchor_rpm*order/60.0)*1.10
				if float(wav.data.size() >> 1) > required and (not native_stable or float(candidate)/(anchor_rpm*order/60.0) <= 0.17):
					row_hop = candidate
					break
		var row := build_grains(wav.data,wav.mix_rate,anchor_rpm*order/60.0,row_hop)
		if row.is_empty():
			return false
		row["hop"] = row_hop
		row["size"] = row_hop*2*SPC+1
		if texture_balance and anchor_rpm >= 1800.0:
			var balanced := balance_recorded_texture(row["pcm"], int(row["size"]))
			row.merge(balanced, true)
		row["rpm"] = anchor_rpm
		row["gain"] = float(entry.get("gain",1.0))
		if native_stable:
			calibrate_native_row(row, str(entry["layer"]))
			if cruise_enabled:
				row["cruise_pcm"] = build_cruise_cycle(row, hop)
		var idx := rows.size()
		rows.append(row)
		if str(entry["layer"]) == "on":
			on_indices.append(idx)
		else:
			off_indices.append(idx)
		diagnostics.append({"file":fname,"rpm":anchor_rpm,"hz":row["hz"],"confidence":row["confidence"],"hop_cycles":row_hop,"tone_before":row.get("tone_before",0.0),"tone_after":row.get("tone_after",0.0),"trim_db":row.get("trim_db",0.0),"stable_take":row.get("stable_take",-1),"playback_gain":row["gain"]})
	on_indices.sort_custom(func(a: int,b: int) -> bool: return float(rows[a]["rpm"]) < float(rows[b]["rpm"]))
	off_indices.sort_custom(func(a: int,b: int) -> bool: return float(rows[a]["rpm"]) < float(rows[b]["rpm"]))
	if texture_balance:
		_screen_tonal_anchors(on_indices)
		_screen_tonal_anchors(off_indices)
	prepared = on_indices.size() >= 2
	reset(idle)
	print("Phase-grain engine: %d anchors, preparation %.1f ms" % [rows.size(),float(Time.get_ticks_usec()-started)/1000.0])
	return prepared

 
# Stable native audition: select a representative sustained portion instead
# of randomly alternating six different RPM-ramp excerpts at steady speed.
# Only playback gain changes; the installed PCM is untouched.
static func calibrate_native_row(row: Dictionary, layer: String) -> void:
	var pcm: PackedFloat32Array = row["pcm"]
	var size := int(row["size"])
	var levels := PackedFloat32Array()
	var peak := 0.0
	for take in range(VARIANTS):
		var energy := 0.0
		for j in range(size-1):
			var sample := pcm[take*size+j]
			energy += sample*sample
			peak = maxf(peak,absf(sample))
		levels.append(sqrt(energy/float(size-1)))
	var sorted := levels.duplicate()
	sorted.sort()
	var median := (sorted[2]+sorted[3])*0.5
	var best := 0
	var cost := INF
	for take in range(VARIANTS):
		var distance := absf(log(maxf(levels[take],0.00001)/maxf(median,0.00001)))
		# Prefer a central portion of a real ramp when levels are comparable.
		distance += 0.035*absf(float(take)-2.5)
		if distance < cost:
			best = take
			cost = distance
	row["stable_take"] = best
	var rpm_fraction := smoothstep(1000.0,7500.0,float(row["rpm"]))
	var target := lerpf(0.052,0.10,rpm_fraction) if layer == "on" else lerpf(0.035,0.065,rpm_fraction)
	var common := float(row["gain"])
	# Bounded static matching reduces huge accidental recording-level gaps
	# without pumping, limiter action, or normalizing every PCM sample.
	var trim := clampf(target/maxf(levels[best]*common,0.00001),0.65,4.0)
	row["gain"] = minf(common*trim,0.44/maxf(peak,0.00001))
	row["calibrated_rms"] = levels[best]*float(row["gain"])
 
 
# The long grains were cut from acceleration/deceleration ramps, so even
# repeating one grain can repeatedly sweep the pitch and harmonic balance.
# For steady cruise use one actual 720-degree recorded cycle on the SAME
# phase clock. Choose a representative adjacent pair and crossfade only
# the last firing pulse into the preceding cycle. No generated tone.
static func build_cruise_cycle(row: Dictionary, cycle_hop: int) -> PackedFloat32Array:
	var pcm: PackedFloat32Array = row["pcm"]
	var size := int(row["size"])
	var n := cycle_hop*SPC
	var origin := int(row["stable_take"])*size
	var cycles := int((size-1)/n)
	var best := origin+n
	var best_score := -INF
	for k in range(1,cycles):
		var at := origin+k*n
		var xx := 0.0
		var yy := 0.0
		var xy := 0.0
		for j in range(0,n,8):
			var x := pcm[at+j]
			var y := pcm[at-n+j]
			xx += x*x
			yy += y*y
			xy += x*y
		var score := xy/sqrt(maxf(xx*yy,0.000000001))
		# Penalize an atypically quiet/loud cycle as well as phase mismatch.
		var relative := sqrt(xx/maxf(yy,0.000000001))
		score -= 0.20*absf(log(maxf(relative,0.001)))
		if score > best_score:
			best_score = score
			best = at
	var loop := PackedFloat32Array()
	loop.resize(n+1)
	var energy := 0.0
	var peak := 0.0
	for j in range(n):
		var value := pcm[best+j]
		if j >= n-SPC:
			var t := float(j-(n-SPC))/float(SPC-1)
			value = lerpf(value,pcm[best-n+j],0.5-0.5*cos(PI*t))
		loop[j] = value
		energy += value*value
		peak = maxf(peak,absf(value))
	var target_rms := float(row["calibrated_rms"])/maxf(float(row["gain"]),0.00001)
	var scale := clampf(target_rms/maxf(sqrt(energy/n),0.00001),0.75,1.25)
	scale = minf(scale,0.44/maxf(peak*float(row["gain"]),0.00001))
	for j in range(n):
		loop[j] *= scale
	loop[n] = loop[0]
	return loop


# Fit fractional period near the supplied firing frequency, never an
# unconstrained dominant harmonic. A low-confidence fit keeps nominal pitch.
static func fit_period(pcm: PackedFloat32Array, rate: int, hz: float, center: int, window: int) -> Vector2:
	var nominal := float(rate)/maxf(hz,1.0)
	var best := nominal
	var best_score := -1.0
	var first := maxi(roundi(nominal*3.0)+2,center-window)
	var last := mini(pcm.size()-2,center+window)
	var stride := maxi(1,floori(float(last-first)/180.0))
	for step in range(-12,13):
		var p := nominal*(1.0+float(step)*0.0075)
		var xy := 0.0
		var xx := 0.0
		var yy := 0.0
		for i in range(first,last,stride):
			var pos := float(i)-p*2.0
			var k := floori(pos)
			if k < 0:
				continue
			var a := pcm[i]
			var b := lerpf(pcm[k],pcm[k+1],pos-float(k))
			xy += a*b
			xx += a*a
			yy += b*b
		var score := xy/sqrt(maxf(xx*yy,0.000000001))-absf(float(step))*0.0015
		if score > best_score:
			best_score = score
			best = p
	return Vector2(best if best_score >= 0.18 else nominal,best_score)


# The upstream high-RPM clips have been pitch-flattened to annotated RPM.
# A broadband autocorrelation maximum can instead lock to a subharmonic
# mixture (e.g. 744 Hz in the SVJ's measured ~800 Hz anchor). Use a narrow
# Hann-windowed projection at the expected firing order, with fractional
# frequency resolution. Reject weak estimates instead of warping the take.
static func fit_high_rpm_period(pcm: PackedFloat32Array,rate: int,hz: float,center: int) -> Vector2:
	var radius := mini(roundi(float(rate)*0.06),mini(center,pcm.size()-1-center))
	if radius < 64:
		return Vector2(float(rate)/hz,0.0)
	var stride := maxi(1,floori(float(rate)/(hz*12.0)))
	var weighted := PackedFloat32Array()
	var energy := 0.0
	var weight_sum := 0.0
	for i in range(-radius,radius+1,stride):
		var w := 0.5+0.5*cos(PI*float(i)/radius)
		var v := pcm[center+i]
		weighted.append(v*w)
		energy += v*v*w
		weight_sum += w
	var best := hz
	var best_power := -1.0
	for step in range(-15,16):
		var frequency := hz*(1.0+float(step)*0.002)
		var coefficient := 2.0*cos(TAU*frequency*stride/float(rate))
		var s1 := 0.0
		var s2 := 0.0
		for v in weighted:
			var q := v+coefficient*s1-s2
			s2 = s1
			s1 = q
		var power := maxf(0.0,s1*s1+s2*s2-coefficient*s1*s2)
		if power > best_power:
			best_power = power
			best = frequency
	var confidence := clampf(2.0*best_power/maxf(energy*weight_sum,0.000000001),0.0,1.0)
	return Vector2(float(rate)/(best if confidence >= 0.025 else hz),confidence)


static func build_grains(data: PackedByteArray, rate: int, expected_hz: float, hop_cycles: int = 8) -> Dictionary:
	var size := hop_cycles * 2 * SPC + 1
	var count := data.size() >> 1
	if rate < 16000 or expected_hz < 25.0 or count < 128:
		return {}
	var pcm := PackedFloat32Array()
	pcm.resize(count)
	var dc := 0.0
	for i in range(count):
		dc += float(data.decode_s16(i*2))/32768.0
	dc /= float(count)
	# Gentle forward/backward anti-alias smoothing retains phase.
	var alpha := 1.0-exp(-TAU*10000.0/float(rate))
	var y := float(data.decode_s16(0))/32768.0-dc
	for i in range(count):
		y = lerpf(y,float(data.decode_s16(i*2))/32768.0-dc,alpha)
		pcm[i] = y
	for i in range(count-1,-1,-1):
		y = lerpf(y,pcm[i],alpha)
		pcm[i] = y
	var high_rpm := expected_hz >= 260.0
	var fit := fit_high_rpm_period(pcm,rate,expected_hz,count >> 1) if high_rpm else fit_period(pcm,rate,expected_hz,count >> 1,mini(count/3,rate/5))
	var period := fit.x
	var room := float(count)-(hop_cycles*2.0+5.0)*period-3.0
	if room < 0.0:
		return {}
	var atlas := PackedFloat32Array()
	atlas.resize(size*VARIANTS)
	for g in range(VARIANTS):
		var start := 2.0*period+room*(float(g)+0.5)/float(VARIANTS)
		var fit_center := roundi(start+period*float(hop_cycles))
		var local_fit := fit_high_rpm_period(pcm,rate,expected_hz,fit_center) if high_rpm else fit_period(pcm,rate,float(rate)/period,fit_center,roundi(period*float(hop_cycles)))
		var nominal_period := float(rate)/expected_hz
		var local_period := clampf(local_fit.x,nominal_period*0.97,nominal_period*1.03) if high_rpm else clampf(local_fit.x,period*0.95,period*1.05)
		var c := 0.0
		var s := 0.0
		var n := maxi(8,roundi(local_period*minf(24.0,float(hop_cycles)*0.5)))
		var center := roundi(start+local_period*float(hop_cycles)*0.5) if high_rpm else roundi(start)
		# Fundamental phase reference; preserve the complete source waveform.
		for j in range(-n,n+1):
			var a := TAU*float(j)/local_period
			var v := pcm[clampi(center+j,0,count-1)]*(0.5+0.5*cos(PI*float(j)/float(n)))
			c += v*cos(a)
			s += v*sin(a)
		var pos := float(center)+atan2(s,c)/TAU*local_period
		if high_rpm:
			pos -= roundf((pos-start)/local_period)*local_period
		var delta := local_period/float(SPC)
		while pos+float(size-1)*delta >= float(count-1):
			pos -= local_period
		while pos < 0.0:
			pos += local_period
		if pos+float(size-1)*delta >= float(count-1):
			return {}
		for j in range(size):
			var at := pos+float(j)*delta
			var k := floori(at)
			atlas[g*size+j] = lerpf(pcm[k],pcm[k+1],at-float(k))
	# Modest take-to-take level matching prevents gratuitous amplitude flutter.
	# Preserve natural within-take dynamics and all recorded harmonics.
	if hop_cycles >= 32:
		var energies := PackedFloat32Array()
		var mean_energy := 0.0
		for g in range(VARIANTS):
			var energy := 0.0
			for j in range(size-1):
				var v := atlas[g*size+j]
				energy += v*v
			energies.append(energy)
			mean_energy += energy/float(VARIANTS)
		for g in range(VARIANTS):
			var scale := clampf(sqrt(mean_energy/maxf(energies[g],0.000001)),0.80,1.25)
			for j in range(size):
				atlas[g*size+j] *= scale
	return {"pcm":atlas,"hz":float(rate)/period,"confidence":fit.y}


# Measure the coherent firing component in recorded grains. Attenuate
# only where it overwhelms the recorded residual, by at most 6 dB.
# No generated engine oscillator/noise is added to the output.
static func balance_recorded_texture(atlas: PackedFloat32Array, size: int) -> Dictionary:
	var period_cos := PackedFloat32Array()
	var period_sin := PackedFloat32Array()
	for i in range(SPC):
		period_cos.append(cos(TAU*float(i)/SPC))
		period_sin.append(sin(TAU*float(i)/SPC))
	var fits: Array[Vector2] = []
	var total_energy := 0.0
	var tone_energy := 0.0
	var n := size-1
	for g in range(VARIANTS):
		var c := 0.0
		var s := 0.0
		for i in range(n):
			var v := atlas[g*size+i]
			c += v*period_cos[i%SPC]
			s += v*period_sin[i%SPC]
			total_energy += v*v
		var fit := Vector2(2.0*c/n,2.0*s/n)
		fits.append(fit)
		tone_energy += float(n)*fit.length_squared()*0.5
	var fraction := clampf(tone_energy/maxf(total_energy,0.000000001),0.0,1.0)
	var trim := 1.0
	if fraction > 0.66:
		trim = clampf(sqrt(0.66*(1.0-fraction)/(0.34*fraction)),0.5,1.0)
	var after_energy := maxf(0.000000001,total_energy-tone_energy*(1.0-trim*trim))
	var after_fraction := clampf(tone_energy*trim*trim/after_energy,0.0,1.0)
	if trim < 0.999:
		var compensation := minf(1.16,sqrt(total_energy/after_energy))
		for g in range(VARIANTS):
			var fit := fits[g]
			for i in range(size):
				var component := fit.x*period_cos[i%SPC]+fit.y*period_sin[i%SPC]
				atlas[g*size+i] = (atlas[g*size+i]-(1.0-trim)*component)*compensation
	return {"pcm":atlas,"tone_before":fraction,"tone_after":after_fraction,"trim_db":20.0*log(trim)/log(10.0)}


# Extremely tonal anchors retain at least 35% of their recording and blend
# with one nearby, less tonal anchor from the same recorded load layer.
func _screen_tonal_anchors(indices: Array[int]) -> void:
	for idx in indices:
		var fraction := float(rows[idx].get("tone_before",0.0))
		if fraction <= 0.85:
			continue
		var best := -1
		var best_cost := INF
		for other in indices:
			if other == idx or float(rows[other]["rpm"]) < 1800.0:
				continue
			var other_fraction := float(rows[other].get("tone_before",0.0))
			var distance := absf(log(float(rows[other]["rpm"])/float(rows[idx]["rpm"])))
			if other_fraction <= 0.75 and distance <= log(1.5)+0.0001:
				var cost := distance+other_fraction*0.25
				if cost < best_cost:
					best = other
					best_cost = cost
		if best >= 0:
			rows[idx]["texture_neighbor"] = best
			rows[idx]["texture_share"] = lerpf(0.35,0.65,smoothstep(0.85,0.96,fraction))
			diagnostics[idx]["texture_neighbor_rpm"] = rows[best]["rpm"]
			diagnostics[idx]["texture_share"] = rows[idx]["texture_share"]
		print("Recorded texture anchor %d RPM: tone %.3f -> %.3f, trim %.1f dB, neighbor %s" % [int(rows[idx]["rpm"]),fraction,float(rows[idx].get("tone_after",fraction)),float(rows[idx].get("trim_db",0.0)),str(rows[idx].get("texture_neighbor",-1))])


func reset(idle: float) -> void:
	rpm = idle
	load_amount = 0.0
	gain = 0.0
	phase = 0.0
	cruise_mix = 0.0
	cruise_target = 0.0
	generated_frames = 0
	clipped_frames = 0
	max_render_usec = 0
	mirror_resyncs = 0
	push_failures = 0
	if is_instance_valid(playback):
		playback.clear_buffer()
	if is_instance_valid(wet_playback):
		wet_playback.clear_buffer()


func layer_weights(weights: PackedFloat32Array, indices: Array[int], target_rpm: float, level: float) -> void:
	if indices.is_empty() or level <= 0.000001:
		return
	var low := indices[0]
	var high := low
	for idx in indices:
		high = idx
		if target_rpm <= float(rows[idx]["rpm"]):
			break
		low = idx
	var a := float(rows[low]["rpm"])
	var b := float(rows[high]["rpm"])
	var t := smoothstep(log(a),log(b),log(maxf(target_rpm,1.0))) if high != low and b > a else 0.0
	# Complementary amplitude weights: equal-power exaggerates correlated notes.
	weights[low] += (1.0-t)*level*float(rows[low]["gain"])
	if high != low:
		weights[high] += t*level*float(rows[high]["gain"])


func weights_for(target_rpm: float, target_load: float) -> PackedFloat32Array:
	var weights := PackedFloat32Array()
	weights.resize(rows.size())
	var l := clampf(target_load,0.0,1.0)
	var available := 0.0
	if not off_indices.is_empty():
		var first := float(rows[off_indices[0]]["rpm"])
		available = smoothstep(first*0.75,first,target_rpm)
	var off := (1.0-l)*available
	if native_stable:
		# At light load keep a bed of the loaded exhaust; coast character
		# remains the dominant layer at zero pedal. No hard tone switches.
		off *= 0.72
	var level := lerpf(lerpf(idle_gain,1.0,l),1.0,available)
	layer_weights(weights,on_indices,target_rpm,(1.0-off)*level)
	layer_weights(weights,off_indices,target_rpm,off*level)
	if texture_balance:
		for i in range(rows.size()):
			var neighbor := int(rows[i].get("texture_neighbor",-1))
			if neighbor >= 0 and weights[i] > 0.0:
				var share := weights[i]*float(rows[i]["texture_share"])
				weights[i] -= share
				weights[neighbor] += share
	return weights


## Stateless take selection means a newly weighted anchor joins the shared
## firing clock at its correct phase instead of restarting its grain.
static func _take_index(epoch: int) -> int:
	return posmod((epoch*48271) ^ (epoch >> 3),VARIANTS)


func render_frames(count: int, target_rpm: float, target_load: float, target_gain: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not prepared or count <= 0:
		return out
	var started := Time.get_ticks_usec()
	out.resize(count)
	var a := weights_for(rpm,load_amount)
	var b := weights_for(target_rpm,target_load)
	var sources: Array[PackedFloat32Array] = []
	var cruise_sources: Array[PackedFloat32Array] = []
	var weights := PackedFloat32Array()
	var steps := PackedFloat32Array()
	var hops := PackedInt32Array()
	var sizes := PackedInt32Array()
	var local_phases := PackedFloat64Array()
	var epochs := PackedInt64Array()
	var grains := PackedInt32Array()
	var old_grains := PackedInt32Array()
	var fixed_takes := PackedInt32Array()
	for i in range(rows.size()):
		if maxf(a[i],b[i]) > 0.000001:
			var atlas: PackedFloat32Array = rows[i]["pcm"]
			sources.append(atlas)
			if cruise_enabled:
				var cruise: PackedFloat32Array = rows[i]["cruise_pcm"]
				cruise_sources.append(cruise)
			weights.append(a[i])
			steps.append((b[i]-a[i])/float(count))
			var h := int(rows[i]["hop"])
			var epoch := floori(phase/float(h))
			hops.append(h)
			sizes.append(int(rows[i]["size"]))
			local_phases.append(phase-float(epoch*h))
			epochs.append(epoch)
			var fixed_take := int(rows[i].get("stable_take",-1))
			fixed_takes.append(fixed_take)
			grains.append(fixed_take if fixed_take >= 0 else _take_index(epoch))
			old_grains.append(fixed_take if fixed_take >= 0 else _take_index(epoch-1))
	var source_count := sources.size()
	var p := phase
	var increment := rpm*order/(60.0*RATE)
	var increment_step := (target_rpm-rpm)*order/(60.0*RATE*float(count))
	var amp := gain
	var amp_step := (target_gain-gain)/float(count)
	var blend := cruise_mix
	var blend_step := (clampf(cruise_target,0.0,1.0)-blend)/float(count) if cruise_enabled else 0.0
	var cruise_active := cruise_enabled and maxf(cruise_mix,cruise_target) > 0.000001
	for i in range(count):
		var sample := 0.0
		var cycle_offset := fposmod(p,float(hop))*SPC if cruise_active else 0.0
		var cycle_index := mini(hop*SPC-1,floori(cycle_offset))
		var cycle_frac := clampf(cycle_offset-float(cycle_index),0.0,1.0)
		for j in range(source_count):
			var h := hops[j]
			var local := local_phases[j]
			var offset := local*SPC
			var k := floori(offset)
			var frac := offset-float(k)
			var new_idx := grains[j]*sizes[j]+k
			var atlas := sources[j]
			var z := lerpf(atlas[new_idx],atlas[new_idx+1],frac)
			# Only evaluate the outgoing grain during the overlap.
			if local < float(h)*OVERLAP_FRACTION:
				var old_idx := old_grains[j]*sizes[j]+h*SPC+k
				var x := lerpf(atlas[old_idx],atlas[old_idx+1],frac)
				var cross := 0.5-0.5*cos(PI*local/(float(h)*OVERLAP_FRACTION))
				z = lerpf(x,z,cross)
			if cruise_active:
				var cycle: PackedFloat32Array = cruise_sources[j]
				var stable := lerpf(cycle[cycle_index],cycle[cycle_index+1],cycle_frac)
				z = lerpf(z,stable,clampf(blend,0.0,1.0))
			sample += z*weights[j]
			weights[j] += steps[j]
			local += increment
			if local >= float(h):
				local -= float(h)
				epochs[j] += 1
				old_grains[j] = grains[j]
				grains[j] = fixed_takes[j] if fixed_takes[j] >= 0 else _take_index(epochs[j])
			local_phases[j] = local
		sample *= amp
		if absf(sample) >= 0.95:
			clipped_frames += 1
		sample = clampf(sample,-0.95,0.95)
		out[i] = Vector2(sample,sample)
		p += increment
		increment += increment_step
		amp += amp_step
		blend += blend_step
	cruise_mix = clampf(blend,0.0,1.0)
	phase = p
	rpm = target_rpm
	load_amount = target_load
	gain = target_gain
	generated_frames += count
	max_render_usec = maxi(max_render_usec,Time.get_ticks_usec()-started)
	return out


func make_voice(bus: StringName) -> AudioStreamPlayer:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = RATE
	stream.buffer_length = 0.24
	var voice := AudioStreamPlayer.new()
	voice.bus = bus
	voice.stream = stream
	add_child(voice)
	voice.play()
	return voice


func ensure_streams(exhaust_bus: StringName, reflection_bus: StringName) -> bool:
	if not is_inside_tree():
		return false
	if not is_instance_valid(direct):
		direct = make_voice(exhaust_bus)
		direct.name = "ContinuousExhaust"
		if AudioServer.get_bus_index(reflection_bus) >= 0:
			mirror = make_voice(reflection_bus)
			mirror.name = "ContinuousWetReflection"
	if not is_instance_valid(playback):
		playback = direct.get_stream_playback() as AudioStreamGeneratorPlayback
		if playback == null:
			return false
		capacity = playback.get_frames_available()
		# Dummy audio drains 4096 output samples at a time. 2048 source
		# frames starved every 92 ms in actual 44.1 kHz CI captures.
		# Real drivers use their reported output latency plus a frame margin.
		var driver_queue := ceili((maxf(0.0,AudioServer.get_output_latency())+0.045)*RATE)
		var floor_queue := HEADLESS_QUEUE if DisplayServer.get_name() == "headless" else MIN_QUEUE
		target_queue = mini(capacity,clampi(driver_queue,floor_queue,MAX_QUEUE))
		print("Phase grain queue: %d/%d frames (%.1f ms), driver latency %.1f ms" % [target_queue,capacity,1000.0*target_queue/RATE,1000.0*AudioServer.get_output_latency()])
	if is_instance_valid(mirror) and not is_instance_valid(wet_playback):
		wet_playback = mirror.get_stream_playback() as AudioStreamGeneratorPlayback
	return true


func pump(target_rpm: float, target_load: float, target_gain: float, exhaust_bus: StringName, reflection_bus: StringName) -> void:
	if not prepared or not ensure_streams(exhaust_bus,reflection_bus):
		return
	var writable := playback.get_frames_available()
	var queued := maxi(0,capacity-writable)
	var count := mini(writable,maxi(0,target_queue-queued))
	if count <= 0:
		return
	var frames := render_frames(count,target_rpm,target_load,target_gain)
	if not playback.push_buffer(frames):
		push_failures += 1
		return
	if is_instance_valid(wet_playback):
		if wet_playback.get_frames_available() < count:
			mirror_resyncs += 1
			wet_playback.clear_buffer()
		if wet_playback.get_frames_available() >= count:
			wet_playback.push_buffer(frames)


func stream_skips() -> int:
	return playback.get_skips() if is_instance_valid(playback) else 0


func stop_audio() -> void:
	if is_instance_valid(direct):
		direct.stop()
	if is_instance_valid(mirror):
		mirror.stop()
	playback = null
	wet_playback = null
