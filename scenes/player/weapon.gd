class_name Weapon
extends Control
## Экранное оружие (screen-space, как ствол в DOOM): визуал-плейсхолдер + hitscan.
## База для всех стволов. Расширение: ЦИФРАМИ через @export (пистолет/дробовик —
## одна логика, разные значения) либо ПОВЕДЕНИЕМ через переопределение хука _fire()
## (ближний бой/ракетомёт — позже).
## Ввод оружие само НЕ читает — им управляет WeaponManager (роутит выстрел в активный
## ствол и переключает оружие).

## Луч попал в неуязвимую поверхность (стена/пол, не враг). (position, normal) —
## для эффекта попадания. Подписчик (через WeaponManager → main) играет дымок.
signal surface_hit(position: Vector3, normal: Vector3)

## Режим огня. SEMI — выстрел на нажатие; AUTO — очередь, пока зажата кнопка.
enum FireMode { SEMI, AUTO }

@export_group("Слот")
## Клавиша выбора (1–5). 0 — слот не назначен, менеджер такой ствол напрямую не активирует.
@export var slot: int = 0

@export_group("Стрельба")
## Урон за одно попадание (за одну дробину).
@export var damage: float = 10.0
## Режим огня.
@export var fire_mode: FireMode = FireMode.SEMI
## Минимальная пауза между выстрелами, с.
@export var fire_cooldown: float = 0.2
## Дальность луча, м.
@export var max_range: float = 1000.0
## Лучей за выстрел. 1 — пистолет; >1 — дробовик (веер дробин).
@export var pellets: int = 1
## Полуугол разброса дробин, градусы. 0 — строго в точку прицела.
@export_range(0.0, 45.0) var spread_degrees: float = 0.0

@export_group("Патроны")
## Тратит ли оружие патроны. false — бесконечное (напр. будущий ближний бой).
@export var uses_ammo: bool = true
## Из какого пула стреляет (id типа в AmmoComponent).
@export var ammo_type: StringName = &"bullets"
## Сколько патронов тратит один выстрел.
@export var ammo_per_shot: int = 1

@export_group("Эффекты")
## Сколько секунд горит вспышка у дула.
@export var flash_duration: float = 0.05
## Звук выстрела (опционально). Молчит, пока ресурс не назначен.
@export var shot_sound: AudioStream
## Звук «пусто» при выстреле без патронов (опционально).
@export var empty_sound: AudioStream

@export_group("Плейсхолдер-визуал")
## Размер «корпуса» ствола, px (заменим на спрайт-арт позже).
@export var body_size: Vector2 = Vector2(84.0, 60.0)
## Размер «дула», px.
@export var barrel_size: Vector2 = Vector2(26.0, 70.0)
## Цвет плейсхолдера.
@export var body_color: Color = Color(0.18, 0.18, 0.2)

const _FLASH_OUTER := Color(1.0, 0.7, 0.2, 0.9)
const _FLASH_INNER := Color(1.0, 0.95, 0.7, 1.0)

# Обратный отсчёт кулдауна, с.
var _cooldown_timer: float = 0.0
# Обратный отсчёт показа вспышки, с.
var _flash_timer: float = 0.0
# Что исключаем из луча (тело игрока) — заполняется в _ready.
var _exclude: Array[RID] = []
# Плеер звука.
var _audio: AudioStreamPlayer
# Боезапас игрока. null — оружие стреляет бесконечно (фолбэк/автономность).
var _ammo: AmmoComponent


func _ready() -> void:
	# Оружие не перехватывает клики (иначе GUI «съест» выстрел).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

	# Исключаем тело игрока из луча (камера внутри его капсулы); заодно берём AmmoComponent.
	var body := _find_collision_ancestor()
	if body != null:
		_exclude = [body.get_rid()]
		_ammo = body.get_node_or_null("AmmoComponent") as AmmoComponent

	_audio = AudioStreamPlayer.new()
	add_child(_audio)


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			queue_redraw()  # вспышка погасла — перерисовать без неё


## Попытка выстрела (с проверкой кулдауна и патронов). Зовёт WeaponManager.
## true — выстрел произошёл.
func try_fire() -> bool:
	if _cooldown_timer > 0.0:
		return false
	# Нет патронов — сухой щелчок. Ставим кулдаун, чтобы в авто-режиме щелчок не спамил каждый кадр.
	if uses_ammo and _ammo != null and not _ammo.has_ammo(ammo_type, ammo_per_shot):
		_play_sound(empty_sound)
		_cooldown_timer = fire_cooldown
		return false
	_cooldown_timer = fire_cooldown
	if uses_ammo and _ammo != null:
		_ammo.consume(ammo_type, ammo_per_shot)
	_show_effects()
	_fire()
	return true


## Хук: ЧТО делает выстрел. По умолчанию — hitscan (веер из pellets лучей с разбросом).
## Переопредели у наследника для иной атаки (снаряд, ближний бой).
func _fire() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var from: Vector3 = camera.global_position
	var cam_basis: Basis = camera.global_transform.basis
	var forward: Vector3 = -cam_basis.z  # «вперёд» камеры

	var space_state := camera.get_world_3d().direct_space_state
	for _i in pellets:
		var dir: Vector3 = forward
		if spread_degrees > 0.0:
			# Случайное отклонение в конусе: смещаем forward по осям камеры.
			var yaw: float = deg_to_rad(randf_range(-spread_degrees, spread_degrees))
			var pitch: float = deg_to_rad(randf_range(-spread_degrees, spread_degrees))
			dir = (forward + cam_basis.x * tan(yaw) + cam_basis.y * tan(pitch)).normalized()
		var to: Vector3 = from + dir * max_range

		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = _exclude
		var result: Dictionary = space_state.intersect_ray(query)
		if result.is_empty():
			continue
		var collider: Object = result.get("collider")
		if collider != null and collider.has_method("take_damage"):
			collider.take_damage(damage)  # урон за каждую попавшую дробину
		else:
			# Неуязвимая поверхность — эффект дымка по нормали (по врагам не ставим).
			surface_hit.emit(result.get("position"), result.get("normal"))


func _show_effects() -> void:
	_flash_timer = flash_duration
	queue_redraw()  # показать вспышку
	_play_sound(shot_sound)


func _play_sound(stream: AudioStream) -> void:
	if stream != null:
		_audio.stream = stream
		_audio.play()


func _draw() -> void:
	var cx: float = size.x * 0.5
	var bottom: float = size.y
	draw_rect(Rect2(cx - body_size.x * 0.5, bottom - body_size.y, body_size.x, body_size.y), body_color)
	draw_rect(Rect2(cx - barrel_size.x * 0.5, bottom - body_size.y - barrel_size.y,
			barrel_size.x, barrel_size.y), body_color)
	if _flash_timer > 0.0:
		var muzzle := Vector2(cx, bottom - body_size.y - barrel_size.y)
		draw_circle(muzzle, 26.0, _FLASH_OUTER)
		draw_circle(muzzle, 14.0, _FLASH_INNER)


# Ближайший предок-CollisionObject3D (тело игрока) вверх по дереву.
func _find_collision_ancestor() -> CollisionObject3D:
	var node: Node = get_parent()
	while node != null:
		if node is CollisionObject3D:
			return node as CollisionObject3D
		node = node.get_parent()
	return null
