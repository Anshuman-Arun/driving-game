class_name PhaseGrainEngine
extends Node
## Recorded multi-cycle grains, one sample-clock firing phase shared across
## every RPM and load anchor. No oscillator and no independent note retriggers.
const RATE := 32000
const SPC := 256
const VARIANTS := 6
# Overlap only the transition, preserving the original take's roughness.
const OVERLAP_FRACTION := 0.35
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
var grain := 0
var previous_grain := VARIANTS-1
var sequence := 7
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


func prepare(loops: Array, wavs: Dictionary, firing_order: float, idle: float, idle_level: float, balance_texture: bool = false) -> bool:
	rows.clear()
	on_indices.clear()
	off_indices.clear()
	diagnostics.clear()
	prepared = false
	order = firing_order
	texture_balance = balance_texture
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
		var row := build_grains(wav.data,wav.mix_rate,anchor_rpm*order/60.0, hop)
		if row.is_empty():
			return false
		if texture_balance and anchor_rpm >= 1800.0:
			var balanced := balance_recorded_texture(row["pcm"], grain_size)
			row.merge(balanced, true)
		row["rpm"] = anchor_rpm
		row["gain"] = float(entry.get("gain",1.0))
		var idx := rows.size()
		rows.append(row)
		if str(entry["layer"]) == "on":
			on_indices.append(idx)
		else:
			off_indices.append(idx)
		diagnostics.append({"file":fname,"rpm":anchor_rpm,"hz":row["hz"],"confidence":row["confidence"],"tone_before":row.get("tone_before",0.0),"tone_after":row.get("tone_after",0.0),"trim_db":row.get("trim_db",0.0)})
	on_indices.sort_custom(func(a: int,b: int) -> bool: return float(rows[a]["rpm"]) < float(rows[b]["rpm"]))
	off_indices.sort_custom(func(a: int,b: int) -> bool: return float(rows[a]["rpm"]) < float(rows[b]["rpm"]))
	if texture_balance:
		_screen_tonal_anchors(on_indices)
		_screen_tonal_anchors(off_indices)
	prepared = on_indices.size() >= 2
	reset(idle)
	print("Phase-grain engine: %d anchors, preparation %.1f ms" % [rows.size(),float(Time.get_ticks_usec()-started)/1000.0])
	return prepared


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
	var fit := fit_period(pcm,rate,expected_hz,count >> 1,mini(count/3,rate/5))
	var period := fit.x
	var room := float(count)-(hop_cycles*2.0+5.0)*period-3.0
	if room < 0.0:
		return {}
	var atlas := PackedFloat32Array()
	atlas.resize(size*VARIANTS)
	for g in range(VARIANTS):
		var start := 2.0*period+room*(float(g)+0.5)/float(VARIANTS)
		var local_fit := fit_period(pcm,rate,float(rate)/period,roundi(start+period*6.0),roundi(period*7.0))
		var local_period := clampf(local_fit.x,period*0.95,period*1.05)
		var c := 0.0
		var s := 0.0
		var n := maxi(8,roundi(local_period*3.0))
		var center := roundi(start)
		# Fundamental phase reference; preserve the complete source waveform.
		for j in range(-n,n+1):
			var a := TAU*float(j)/local_period
			var v := pcm[clampi(center+j,0,count-1)]*(0.5+0.5*cos(PI*float(j)/float(n)))
			c += v*cos(a)
			s += v*sin(a)
		var pos := float(center)+atan2(s,c)/TAU*local_period
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
	grain = 0
	previous_grain = VARIANTS-1
	sequence = 7
	generated_frames = 0
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


func render_frames(count: int, target_rpm: float, target_load: float, target_gain: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not prepared or count <= 0:
		return out
	var started := Time.get_ticks_usec()
	out.resize(count)
	var a := weights_for(rpm,load_amount)
	var b := weights_for(target_rpm,target_load)
	var sources: Array[PackedFloat32Array] = []
	var weights := PackedFloat32Array()
	var steps := PackedFloat32Array()
	for i in range(rows.size()):
		if maxf(a[i],b[i]) > 0.000001:
			var atlas: PackedFloat32Array = rows[i]["pcm"]
			sources.append(atlas)
			weights.append(a[i])
			steps.append((b[i]-a[i])/float(count))
	var source_count := sources.size()
	var p := phase
	var g := grain
	var old := previous_grain
	var seq := sequence
	var increment := rpm*order/(60.0*RATE)
	var increment_step := (target_rpm-rpm)*order/(60.0*RATE*float(count))
	var amp := gain
	var amp_step := (target_gain-gain)/float(count)
	for i in range(count):
		var offset := p*SPC
		var k := floori(offset)
		var frac := offset-float(k)
		var new_idx := g*grain_size+k
		var old_idx := old*grain_size+hop*SPC+k
		var cross := 0.5-0.5*cos(PI*minf(1.0,p/(float(hop)*OVERLAP_FRACTION)))
		var sample := 0.0
		for j in range(source_count):
			var atlas := sources[j]
			var x := lerpf(atlas[old_idx],atlas[old_idx+1],frac)
			var z := lerpf(atlas[new_idx],atlas[new_idx+1],frac)
			sample += lerpf(x,z,cross)*weights[j]
			weights[j] += steps[j]
		sample = clampf(sample*amp,-0.95,0.95)
		out[i] = Vector2(sample,sample)
		p += increment
		if p >= hop:
			p -= hop
			old = g
			# Deterministic varied take selection; never restart a pitched loop.
			seq = (seq*48271)%2147483647
			g = (g+1+seq%(VARIANTS-1))%VARIANTS
		increment += increment_step
		amp += amp_step
	phase = p
	grain = g
	previous_grain = old
	sequence = seq
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
