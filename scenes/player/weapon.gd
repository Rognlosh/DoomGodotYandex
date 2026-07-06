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

## Луч попал по уязвимой цели (враг). (position, normal) — для эффекта попадания
## по врагу (звёзды-pow). Подписчик (через WeaponManager → main) играет эффект.
signal damageable_hit(position: Vector3, normal: Vector3)

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
# Звук выстрела/«пусто» — централизован в CombatAudio (по слоту ствола),
# найдётся по группе. Реальные SFX — заменой OGG, не правкой сцен оружия.

@export_group("Спрайт")
## Стрип кадров оружия (слева направо): кадр 0 — покой, дальше — выстрел.
## null — рисуется старый прямоугольный плейсхолдер (арт ещё не назначен).
@export var sprite: Texture2D
## Всего кадров в стрипе (включая кадр покоя).
@export var sprite_frames: int = 4
## Длительность одного кадра анимации выстрела, с.
@export var fire_frame_time: float = 0.06
## Высота кадра на экране, в долях высоты вьюпорта.
@export_range(0.1, 1.0) var screen_height_ratio: float = 0.42
## Доля кадра, спрятанная ЗА нижним краем экрана. КОНТРАКТ с будущей HUD-панелью:
## панель займёт нижние ~12% экрана и накроет этот запас (руки «растут» из-за неё).
@export_range(0.0, 0.5) var bottom_overhang: float = 0.10

@export_group("Покачивание (bob)")
## Амплитуда покачивания по X/Y, в долях высоты кадра на экране.
@export var bob_amplitude: Vector2 = Vector2(0.05, 0.03)
## Радиан фазы покачивания на метр пройденного пути (чаще шаг — чаще качается).
@export var bob_per_meter: float = 1.7
## Скорость нарастания/затухания покачивания (остановился — оружие плавно замирает).
@export var bob_damping: float = 8.0

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
# Звук боя (находится по группе, лениво). null — звук просто не играет.
var _combat: CombatAudio
# Боезапас игрока. null — оружие стреляет бесконечно (фолбэк/автономность).
var _ammo: AmmoComponent
# Тело игрока (CollisionObject3D) — для исключения из луча и как owner снаряда
# (используется наследниками, напр. RocketLauncher).
var _body: CollisionObject3D
# Тело игрока как CharacterBody3D (для bob: velocity/is_on_floor). null — bob выключен.
var _char: CharacterBody3D

# Анимация выстрела: время с начала, с. Отрицательное — покой (кадр 0).
var _anim_time: float = -1.0
# Текущий кадр стрипа.
var _frame: int = 0
# Фаза покачивания (радианы; наматывается от пройденного пути).
var _bob_phase: float = 0.0
# Сила покачивания 0..1 (плавный вход/выход через bob_damping).
var _bob_strength: float = 0.0


func _ready() -> void:
	# Оружие не перехватывает клики (иначе GUI «съест» выстрел).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

	# Исключаем тело игрока из луча (камера внутри его капсулы); заодно берём AmmoComponent.
	# Пиксель-арт не мылим (аналог Filter Off у Sprite3D, но для Canvas).
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var body := _find_collision_ancestor()
	if body != null:
		_body = body
		_char = body as CharacterBody3D
		_exclude = [body.get_rid()]
		_ammo = body.get_node_or_null("AmmoComponent") as AmmoComponent


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			queue_redraw()  # вспышка погасла — перерисовать без неё (плейсхолдер)
	_advance_fire_animation(delta)
	_update_bob(delta)


# Листает кадры выстрела по таймеру; по окончании возвращает кадр покоя (0).
func _advance_fire_animation(delta: float) -> void:
	if _anim_time < 0.0:
		return
	_anim_time += delta
	var next_frame: int = 1 + int(_anim_time / fire_frame_time)
	if next_frame >= sprite_frames:
		_anim_time = -1.0
		next_frame = 0
	if next_frame != _frame:
		_frame = next_frame
		queue_redraw()


# Наматывает фазу покачивания от пройденного пути; на месте/в воздухе — плавно гасит.
func _update_bob(delta: float) -> void:
	if not visible or _char == null:
		return
	var target: float = 0.0
	if _char.is_on_floor():
		var h_speed: float = Vector2(_char.velocity.x, _char.velocity.z).length()
		if h_speed > 0.5:
			_bob_phase += h_speed * bob_per_meter * delta
			target = 1.0
	var prev: float = _bob_strength
	_bob_strength = move_toward(_bob_strength, target, bob_damping * delta)
	if _bob_strength > 0.001 or prev > 0.001:
		queue_redraw()  # оружие в движении — перерисовываем


## Попытка выстрела (с проверкой кулдауна и патронов). Зовёт WeaponManager.
## true — выстрел произошёл.
func try_fire() -> bool:
	if _cooldown_timer > 0.0:
		return false
	# Нет патронов — сухой щелчок. Ставим кулдаун, чтобы в авто-режиме щелчок не спамил каждый кадр.
	if uses_ammo and _ammo != null and not _ammo.has_ammo(ammo_type, ammo_per_shot):
		var ca := _combat_audio()
		if ca != null:
			ca.play(&"dry")
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
			damageable_hit.emit(result.get("position"), result.get("normal"))
		else:
			# Неуязвимая поверхность — эффект дымка по нормали (по врагам не ставим).
			surface_hit.emit(result.get("position"), result.get("normal"))


func _show_effects() -> void:
	_flash_timer = flash_duration
	if sprite != null and sprite_frames > 1:
		_anim_time = 0.0
		_frame = 1
	queue_redraw()  # показать вспышку/первый кадр выстрела
	var ca := _combat_audio()
	if ca != null:
		ca.play_weapon(slot)  # звук выбирается по слоту ствола


# Ленивый поиск звука боя по группе (создаётся main). Кэшируем; нет — тишина.
func _combat_audio() -> CombatAudio:
	if _combat == null or not is_instance_valid(_combat):
		_combat = get_tree().get_first_node_in_group(&"combat_audio") as CombatAudio
	return _combat


func _draw() -> void:
	if sprite != null and sprite_frames > 0:
		_draw_sprite()
	else:
		_draw_placeholder()


# Текущий сдвиг покачивания в пикселях. Классика DOOM: X — маятник,
# Y — «проседание» на полушаге (частота по Y вдвое выше за счёт abs).
func _bob_offset(frame_height_px: float) -> Vector2:
	return Vector2(cos(_bob_phase), absf(sin(_bob_phase))) \
			* bob_amplitude * frame_height_px * _bob_strength


# Арт-режим: кадр стрипа по нижнему центру, с запасом за краем и покачиванием.
# Вспышку кружками не рисуем — кадры выстрела несут её в самом арте.
func _draw_sprite() -> void:
	var frame_w: float = float(sprite.get_width()) / float(sprite_frames)
	var frame_h: float = float(sprite.get_height())
	var dest_h: float = size.y * screen_height_ratio
	var dest_w: float = frame_w * (dest_h / frame_h)
	var bob: Vector2 = _bob_offset(dest_h)
	var pos := Vector2(
			size.x * 0.5 - dest_w * 0.5 + bob.x,
			size.y - dest_h * (1.0 - bottom_overhang) + bob.y)
	draw_texture_rect_region(sprite, Rect2(pos, Vector2(dest_w, dest_h)),
			Rect2(_frame * frame_w, 0.0, frame_w, frame_h))


# Плейсхолдер до назначения арта: прежние прямоугольники + вспышка, теперь с bob.
func _draw_placeholder() -> void:
	var bob: Vector2 = _bob_offset(size.y * screen_height_ratio)
	var cx: float = size.x * 0.5 + bob.x
	var bottom: float = size.y + bob.y
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
