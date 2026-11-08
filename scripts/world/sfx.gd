class_name Sfx
extends Node3D
## Sounds synthesized at startup: a punch thud and the ring bell. No audio files.

const RATE := 22050

var _thud := _make(0.18, func(t: float) -> float:
	return sin(TAU * 90.0 * t) * exp(-25.0 * t) + randf_range(-0.5, 0.5) * exp(-60.0 * t))
var _bell := _make(2.0, func(t: float) -> float:
	return (sin(TAU * 700.0 * t) + 0.5 * sin(TAU * 1760.0 * t) + 0.3 * sin(TAU * 2400.0 * t)) * 0.5 * exp(-2.0 * t))


func thud(at: Vector3, blocked: bool) -> void:
	_play(_thud, at, -10.0 if blocked else 0.0, 1.5 if blocked else 1.0)


func bell() -> void:
	_play(_bell, Vector3(0, 2.5, 0), 0.0, 1.0)


func _play(stream: AudioStream, at: Vector3, db: float, pitch: float) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()


static func _make(seconds: float, wave: Callable) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(wave.call(float(i) / RATE), -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav
