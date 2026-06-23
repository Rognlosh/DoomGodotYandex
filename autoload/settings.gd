extends Node
## Глобальные настройки игрока: громкости аудио-шин и чувствительность мыши.
## ПЕРВЫЙ autoload проекта (папка autoload/ под это и резервировалась).
##
## Почему синглтон, а не узел в сцене (как HealthComponent/CombatAudio):
## настройки — глобальный, переживающий смену сцен и сохраняемый на диск конфиг,
## а не игровое состояние. Громкости применяются к AudioServer (он сам глобальный),
## чувствительность нужна игроку, которого сессия пересоздаёт при каждом запуске.
##
## Хранение — локальный user://settings.cfg (в вебе Godot кладёт user:// в
## IndexedDB браузера). Облачная синхронизация настроек — стык с Yandex SDK (Этап 4).

## Чувствительность изменилась — живой игрок подхватывает значение на лету
## (правка из паузы применяется немедленно, без респавна). Сигнал, т.к. игрок
## не должен опрашивать синглтон каждый кадр.
signal mouse_sensitivity_changed(value: float)

const _CONFIG_PATH := "user://settings.cfg"
const _SECTION_AUDIO := "audio"
const _SECTION_INPUT := "input"
# Задержка перед записью на диск: частые тики ползунка схлопываются в одну запись
# (важно для веба — user:// уходит в IndexedDB, поштучные записи дороги).
const _SAVE_DELAY := 0.5

# Линейные громкости 0..1 — slider отдаёт их напрямую; в дБ переводим при применении.
var master_volume: float = 1.0
var sfx_volume: float = 1.0
# Дефолт фона = -6 дБ исходного микса (см. default_bus_layout.tres), в линейном виде.
var ambient_volume: float = db_to_linear(-6.0)
# Радиан поворота на пиксель — дефолт совпадает с @export mouse_sensitivity в player.gd.
var mouse_sensitivity: float = 0.0025

# Одноразовый таймер дебаунса записи (создаётся в _ready).
var _save_timer: Timer


func _ready() -> void:
	# ALWAYS: настройки правятся из паузы (дерево на паузе) — таймер записи и
	# применение должны работать и тогда.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = _SAVE_DELAY
	_save_timer.timeout.connect(_write_config)
	add_child(_save_timer)

	_load_config()
	_apply_all_buses()


# --------------------------------------------------------------------------
# Сеттеры: применяем сразу, запись на диск — отложенно (дебаунс).
# --------------------------------------------------------------------------

func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_bus(&"Master", master_volume)
	_request_save()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_bus(&"SFX", sfx_volume)
	_request_save()


func set_ambient_volume(value: float) -> void:
	ambient_volume = clampf(value, 0.0, 1.0)
	_apply_bus(&"Ambient", ambient_volume)
	_request_save()


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = maxf(value, 0.0)
	mouse_sensitivity_changed.emit(mouse_sensitivity)
	_request_save()


# --------------------------------------------------------------------------
# Применение к AudioServer
# --------------------------------------------------------------------------

func _apply_all_buses() -> void:
	_apply_bus(&"Master", master_volume)
	_apply_bus(&"SFX", sfx_volume)
	_apply_bus(&"Ambient", ambient_volume)


# Линейную громкость 0..1 переводим в дБ и ставим на шину по имени.
# 0 (и около) — тишина через -80 дБ: linear_to_db(0) = -inf, шине такое не годится.
func _apply_bus(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var db := -80.0 if linear <= 0.0001 else linear_to_db(linear)
	AudioServer.set_bus_volume_db(idx, db)


# --------------------------------------------------------------------------
# Хранение (ConfigFile -> user://settings.cfg)
# --------------------------------------------------------------------------

func _request_save() -> void:
	# Перезапуск таймера откладывает запись — серия тиков ползунка = одна запись.
	_save_timer.start()


func _write_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(_SECTION_AUDIO, "master", master_volume)
	cfg.set_value(_SECTION_AUDIO, "sfx", sfx_volume)
	cfg.set_value(_SECTION_AUDIO, "ambient", ambient_volume)
	cfg.set_value(_SECTION_INPUT, "mouse_sensitivity", mouse_sensitivity)
	cfg.save(_CONFIG_PATH)


func _load_config() -> void:
	var cfg := ConfigFile.new()
	# Файла нет (первый запуск) или он битый — остаёмся на дефолтах.
	if cfg.load(_CONFIG_PATH) != OK:
		return
	master_volume = clampf(cfg.get_value(_SECTION_AUDIO, "master", master_volume), 0.0, 1.0)
	sfx_volume = clampf(cfg.get_value(_SECTION_AUDIO, "sfx", sfx_volume), 0.0, 1.0)
	ambient_volume = clampf(cfg.get_value(_SECTION_AUDIO, "ambient", ambient_volume), 0.0, 1.0)
	mouse_sensitivity = maxf(cfg.get_value(_SECTION_INPUT, "mouse_sensitivity", mouse_sensitivity), 0.0)
