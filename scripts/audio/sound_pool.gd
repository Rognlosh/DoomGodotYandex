class_name SoundPool
extends Node
## Пул не-позиционных проигрывателей (AudioStreamPlayer) с round-robin и
## вариацией высоты тона. Один плеер «съедал» бы хвост предыдущего звука
## (пулемёт ~10 выстр/с), поэтому держим несколько и крутим по кругу —
## как пул CPUParticles3D у эффектов (ParticleBurst3D).
##
## Не читает ввод и не знает об источниках звука: ему дают AudioStream — он играет.

## Сколько проигрывателей в пуле (одновременно звучащих хвостов).
@export var voices: int = 8
## Шина микшера, на которую играем (см. default_bus_layout.tres).
@export var bus: StringName = &"SFX"
## Полуразброс высоты тона: 1.0 ± этого. 0 — без вариации (метроном).
@export_range(0.0, 0.5) var pitch_variation: float = 0.08

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0


func _ready() -> void:
	for _i in voices:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		add_child(p)
		_players.append(p)


## Сыграть поток через следующий свободный по кругу проигрыватель.
## volume_db — поправка громкости конкретного звука.
func play(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null or _players.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = volume_db
	if pitch_variation > 0.0:
		p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.play()
