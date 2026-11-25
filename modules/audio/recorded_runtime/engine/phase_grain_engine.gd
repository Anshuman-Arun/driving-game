class_name PhaseGrainEngine
extends Node
## Recorded multi-cycle grains, one sample-clock firing phase shared across
## every RPM and load anchor. No oscillator and no independent note retriggers.
const RATE := 32000
const SPC := 256
const HOP := 8
const VARIANTS := 6
const SIZE := HOP * 2 * SPC + 1
const MIN_QUEUE := 2048
const HEADLESS_QUEUE := 4096
const MAX_QUEUE := 6144

var rows: Array[Dictionary] = []
var on_indices: Array[int] = []
var off_indices: Array[int] = []
var order := 6.0
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


func prepare(loops: Array, wavs: Dictionary, firing_order: float, idle: float, idle_level: float) -> bool:
	rows.clear()
	on_indices.clear()
	off_indices.clear()
	diagnostics.clear()
	prepared = false
	order = firing_order
	idle_gain = idle_level
	var started := Time.get_ticks_usec()
	for entry in loops:
		var fname := str(entry["file"])
		var wav: AudioStreamWAV = wavs.get(fname)
		if wav == null or wav.format != AudioStreamWAV.FORMAT_16_BITS or wav.stereo:
			return false
		var anchor_rpm := float(entry["rpm"])
		var row := build_grains(wav.data,wav.mix_rate,anchor_rpm*order/60.0)
		if row.is_empty():
			return false
		row["rpm"] = anchor_rpm
		row["gain"] = float(entry.get("gain",1.0))
		var idx := rows.size()
		rows.append(row)
		if str(entry["layer"]) == "on":
			on_indices.append(idx)
		else:
			off_indices.append(idx)
		diagnostics.append({"file":fname,"rpm":anchor_rpm,"hz":row["hz"],"confidence":row["confidence"]})
	on_indices.sort_custom(func(a: int,b: int) -> bool: return float(rows[a]["rpm"]) < float(rows[b]["rpm"]))
	off_indices.sort_custom(func(a: int,b: int) -> bool: return float(rows[a]["rpm"]) < float(rows[b]["rpm"]))
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


static func build_grains(data: PackedByteArray, rate: int, expected_hz: float) -> Dictionary:
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
	var room := float(count)-(HOP*2.0+5.0)*period-3.0
	if room < 0.0:
		return {}
	var atlas := PackedFloat32Array()
	atlas.resize(SIZE*VARIANTS)
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
		while pos+float(SIZE-1)*delta >= float(count-1):
			pos -= local_period
		while pos < 0.0:
			pos += local_period
		if pos+float(SIZE-1)*delta >= float(count-1):
			return {}
		for j in range(SIZE):
			var at := pos+float(j)*delta
			var k := floori(at)
			atlas[g*SIZE+j] = lerpf(pcm[k],pcm[k+1],at-float(k))
	return {"pcm":atlas,"hz":float(rate)/period,"confidence":fit.y}


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
		var new_idx := g*SIZE+k
		var old_idx := old*SIZE+HOP*SPC+k
		var cross := 0.5-0.5*cos(PI*p/float(HOP))
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
		if p >= HOP:
			p -= HOP
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
