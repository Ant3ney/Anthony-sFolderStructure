extends AudioStreamPlayer3D
class_name PlaceholderAudioCue

const SAMPLE_RATE := 22050

@export var cue_name: String = "placeholder"
@export var cue_role: String = "ambient"
@export_range(90.0, 2200.0, 1.0) var frequency_hz: float = 440.0
@export_range(0.05, 1.5, 0.01) var duration_seconds: float = 0.24
@export_range(0.0, 1.0, 0.01) var gain: float = 0.16
@export var autoplay_on_ready: bool = false

func _ready() -> void:
	name = "AudioCue_%s" % cue_name.replace(" ", "_")
	add_to_group("placeholder_audio_cues")
	set_meta("cue_name", cue_name)
	set_meta("cue_role", cue_role)
	set_meta("placeholder_audio", true)
	stream = _make_tone_stream()
	volume_db = -22.0
	max_distance = maxf(max_distance, 28.0)
	if autoplay_on_ready:
		play()

func _make_tone_stream() -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	var frames: int = max(1, int(float(SAMPLE_RATE) * duration_seconds))
	var data: PackedByteArray = PackedByteArray()
	data.resize(frames * 2)

	for i in range(frames):
		var t := float(i) / float(SAMPLE_RATE)
		var fade_in := clampf(t / 0.025, 0.0, 1.0)
		var fade_out := clampf((duration_seconds - t) / 0.08, 0.0, 1.0)
		var envelope := minf(fade_in, fade_out)
		var tone := sin(TAU * frequency_hz * t) * envelope * gain
		var sample: int = int(clampf(tone * 32767.0, -32768.0, 32767.0))
		if sample < 0:
			sample += 65536
		var index: int = i * 2
		data[index] = sample & 0xff
		data[index + 1] = (sample >> 8) & 0xff

	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav
