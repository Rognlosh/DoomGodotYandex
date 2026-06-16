extends Control
## Компонент-оружие: экранный визуал (пока рисованный плейсхолдер), hitscan, semi-auto.
## Лежит в CanvasLayer (screen-space) — как дум-овский ствол поверх камеры.
## Сам читает ввод (action "shoot") и стреляет только при захваченном курсоре.
## Логику урона напрямую не знает: при попадании вызывает take_damage(amount)
## у цели, если у той есть такой метод (задел под врагов).

@export_group("Стрельба")
## Урон за одно попадание.
@export var damage: float = 10.0
## Минимальная пауза между выстрелами, с. Semi-auto: один выстрел на клик, но не чаще.
@export var fire_cooldown: float = 0.2
## Дальность луча, м.
@export var max_range: float = 1000.0

@export_group("Эффекты")
## Сколько секунд горит вспышка у дула.
@export var flash_duration: float = 0.05
## Звук выстрела (опционально). Молчит, пока ресурс не назначен в инспекторе.
@export var shot_sound: AudioStream

# --- Плейсхолдер-визуал (временный; заменим на TextureRect со спрайтом, когда будет арт) ---
const _GUN_COLOR := Color(0.18, 0.18, 0.2)
const _FLASH_OUTER := Color(1.0, 0.7, 0.2, 0.9)
const _FLASH_INNER := Color(1.0, 0.95, 0.7, 1.0)

# Обратный отсчёт кулдауна, с.
var _cooldown_timer: float = 0.0
# Обратный отсчёт показа вспышки, с.
var _flash_timer: float = 0.0
# Что исключаем из луча (само тело игрока) — заполняется в _ready.
var _exclude: Array[RID] = []
# Плеер звука. Создаём в коде, чтобы не держать лишний узел в сцене.
var _audio: AudioStreamPlayer


func _ready() -> void:
	# Оружие не должно перехватывать клики мыши (иначе GUI «съест» выстрел).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Перерисовка при изменении размера окна (важно для веба/ресайза).
	resized.connect(queue_redraw)

	# Исключаем тело игрока из луча: луч стартует из камеры внутри его капсулы.
	var body := _find_collision_ancestor()
	if body != null:
		_exclude = [body.get_rid()]

	# Плеер звука. Играет, только если назначен shot_sound (плейсхолдер пока молчит).
	_audio = AudioStreamPlayer.new()
	add_child(_audio)


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			queue_redraw()  # вспышка погасла — перерисовать без неё


func _unhandled_input(event: InputEvent) -> void:
	# Стреляем по нажатию "shoot" и только при захваченном курсоре.
	# «Захватывающий» клик сюда не доходит — его поглощает player.gd в _input.
	if event.is_action_pressed(&"shoot") and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_try_fire()


func _try_fire() -> void:
	if _cooldown_timer > 0.0:
		return
	_cooldown_timer = fire_cooldown
	_show_effects()
	_do_hitscan()


func _show_effects() -> void:
	_flash_timer = flash_duration
	queue_redraw()  # показать вспышку
	if shot_sound != null:
		_audio.stream = shot_sound
		_audio.play()


func _do_hitscan() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	# Луч из позиции камеры (центр экрана) строго вперёд: forward = -Z базиса камеры.
	var from: Vector3 = camera.global_position
	var to: Vector3 = from - camera.global_transform.basis.z * max_range

	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = _exclude
	var result: Dictionary = space_state.intersect_ray(query)

	if result.is_empty():
		return

	var collider: Object = result.get("collider")
	# Если у цели есть take_damage — наносим урон. Врагов пока нет, поэтому
	# по геометрии (стены/препятствия) ничего не происходит.
	if collider != null and collider.has_method("take_damage"):
		collider.take_damage(damage)


func _draw() -> void:
	var cx: float = size.x * 0.5
	var bottom: float = size.y

	# --- Плейсхолдер ствола (заменить на TextureRect со спрайтом, когда будет арт) ---
	var body_w: float = 84.0
	var body_h: float = 60.0
	var barrel_w: float = 26.0
	var barrel_h: float = 70.0

	draw_rect(Rect2(cx - body_w * 0.5, bottom - body_h, body_w, body_h), _GUN_COLOR)
	draw_rect(Rect2(cx - barrel_w * 0.5, bottom - body_h - barrel_h, barrel_w, barrel_h), _GUN_COLOR)

	# Вспышка у верха ствола — только пока тикает её таймер.
	if _flash_timer > 0.0:
		var muzzle := Vector2(cx, bottom - body_h - barrel_h)
		draw_circle(muzzle, 26.0, _FLASH_OUTER)
		draw_circle(muzzle, 14.0, _FLASH_INNER)


# Ищем ближайшего предка-CollisionObject3D (тело игрока) вверх по дереву.
func _find_collision_ancestor() -> CollisionObject3D:
	var node: Node = get_parent()
	while node != null:
		if node is CollisionObject3D:
			return node as CollisionObject3D
		node = node.get_parent()
	return null
