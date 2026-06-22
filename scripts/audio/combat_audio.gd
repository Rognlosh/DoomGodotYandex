class_name CombatAudio
extends Node
## Центральный звук боя. Узел в дереве (создаёт main), находится по группе
## "combat_audio" — оружие и враги дёргают его, не зная деталей (как игрок ищется
## по группе "player"). Никаких autoload: состояние не глобальное, узел живёт в сцене.
##
## Принцип: источник зовёт play(id) — сервис решает, ЧЕМ озвучить. Реальные SFX
## подменяются заменой OGG-файлов по тем же путям, код не трогаем.

const _DIR := "res://assets/audio/"

# id звука -> файл. Один словарь — точка добавления нового звука.
const _LIBRARY := {
	&"pistol": "sfx_pistol.ogg",
	&"shotgun": "sfx_shotgun.ogg",
	&"machinegun": "sfx_machinegun.ogg",
	&"dry": "sfx_dry.ogg",
	&"impact_wall": "sfx_impact_wall.ogg",
	&"impact_flesh": "sfx_impact_flesh.ogg",
	&"enemy_attack": "sfx_enemy_attack.ogg",
	&"enemy_death": "sfx_enemy_death.ogg",
	&"player_hurt": "sfx_player_hurt.ogg",
	&"player_death": "sfx_player_death.ogg",
}
const _AMBIENT := "amb_level.ogg"

# Поправки громкости по id, дБ (плейсхолдеры выровнены на слух).
const _VOLUME := {
	&"impact_wall": -5.0,
	&"impact_flesh": -3.0,
	&"machinegun": -2.0,
}

# id, звучащие пачкой (по дробине дробовика) — не дублируем в одном кадре,
# иначе 7 одинаковых тиков дают мусорную «гребёнку».
const _DEDUPE := {&"impact_wall": true, &"impact_flesh": true}

# Слот оружия -> id выстрела (данные, не код: новый ствол — строчка тут).
const _WEAPON_BY_SLOT := {2: &"pistol", 3: &"shotgun", 4: &"machinegun"}

var _streams: Dictionary = {}
var _pool: SoundPool
var _ambient: AudioStreamPlayer
# id -> номер кадра последнего проигрыша (для дедупа).
var _played_frame: Dictionary = {}


func _ready() -> void:
	add_to_group(&"combat_audio")

	_pool = SoundPool.new()
	add_child(_pool)

	# Грузим в рантайме (а не preload) — устойчивее на свежем клоне до первого импорта.
	for id in _LIBRARY:
		var stream := load(_DIR + _LIBRARY[id]) as AudioStream
		if stream != null:
			_streams[id] = stream

	_ambient = AudioStreamPlayer.new()
	_ambient.bus = &"Ambient"
	add_child(_ambient)
	var amb := load(_DIR + _AMBIENT) as AudioStream
	if amb != null:
		_ambient.stream = amb  # луп включён в .import (loop=true)
		_ambient.play()


## Сыграть звук по id. Неизвестный id или незагруженный файл — тишина.
func play(id: StringName) -> void:
	var stream := _streams.get(id) as AudioStream
	if stream == null:
		return
	if _DEDUPE.has(id):
		var frame := Engine.get_process_frames()
		if _played_frame.get(id, -1) == frame:
			return
		_played_frame[id] = frame
	_pool.play(stream, _VOLUME.get(id, 0.0))


## Сыграть выстрел активного ствола по его слоту.
func play_weapon(slot: int) -> void:
	var id := _WEAPON_BY_SLOT.get(slot, &"") as StringName
	if id != &"":
		play(id)
