class_name EnemyBase
extends CharacterBody3D
## Базовый враг: наземный, ближний бой. Играбелен «как есть» (наш первый враг)
## и служит базой для других типов. Расширение без копипасты — два пути:
##   1) другие цифры — меняешь @export в инспекторе унаследованной сцены;
##   2) другое поведение — extends EnemyBase и переопределяешь хук
##      (_move_towards_target / _perform_attack / _can_see_target / _on_death).

## Состояния ИИ (как enum в C#: State.IDLE и т.д.).
enum State { IDLE, CHASE, ATTACK, DEAD }

@export_group("Характеристики")
## Скорость преследования, м/с.
@export var move_speed: float = 4.0
## Радиус, в котором враг замечает игрока, м.
@export var detection_range: float = 18.0
## Дистанция, с которой враг бьёт, м.
@export var attack_range: float = 2.0
## Урон за один удар.
@export var attack_damage: float = 8.0
## Пауза между ударами, с.
@export var attack_cooldown: float = 1.2
## Гравитация, м/с².
@export var gravity: float = 24.0

@export_group("Цель")
## Группа, в которой ищем игрока. &"..." — StringName (дешёвая интернированная строка).
@export var target_group: StringName = &"player"

# $Узел — это get_node("Узел"); @onready откладывает до готовности дерева.
@onready var _health: HealthComponent = $HealthComponent
@onready var _sprite: Sprite3D = $Sprite3D

# Цель (игрок). Может исчезнуть (рестарт уровня) — ищем лениво.
var _target: Node3D
var _state: State = State.IDLE
# Обратный отсчёт до следующего удара, с.
var _attack_timer: float = 0.0
# Высота «глаз» для луча видимости и центра удара, м.
const _EYE_OFFSET := Vector3(0.0, 1.0, 0.0)


func _ready() -> void:
	# Реакция на смерть — наша (signal up).
	_health.died.connect(_on_death)
	# Плейсхолдер-текстура, если арт ещё не назначен в инспекторе (ноль веса билда).
	if _sprite.texture == null:
		_sprite.texture = _make_placeholder_texture()


# Конвенция урона: тело принимает урон и делегирует в компонент.
func take_damage(amount: float) -> void:
	_health.take_damage(amount)


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return

	if _attack_timer > 0.0:
		_attack_timer -= delta

	_acquire_target()

	# match — аналог switch.
	match _state:
		State.IDLE:
			_state_idle(delta)
		State.CHASE:
			_state_chase(delta)
		State.ATTACK:
			_state_attack(delta)


# --- Состояния ---

func _state_idle(delta: float) -> void:
	_apply_gravity(delta)
	move_and_slide()
	if _target != null and _can_see_target():
		_state = State.CHASE


func _state_chase(delta: float) -> void:
	if _target == null:
		_state = State.IDLE
		return
	var dist := global_position.distance_to(_target.global_position)
	if dist <= attack_range:
		_state = State.ATTACK
		return
	if dist > detection_range:
		_state = State.IDLE  # потеряли — назад в ожидание
		return
	_move_towards_target(delta)


func _state_attack(delta: float) -> void:
	# Стоим на месте, гасим горизонтальную скорость, бьём по кулдауну.
	_apply_gravity(delta)
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()

	if _target == null:
		_state = State.IDLE
		return
	if global_position.distance_to(_target.global_position) > attack_range:
		_state = State.CHASE
		return
	if _attack_timer <= 0.0:
		_attack_timer = attack_cooldown
		_perform_attack()


# --- Хуки для переопределения у наследников ---

## Обнаружение: в радиусе И есть прямая видимость. Переопредели под конус/360°.
func _can_see_target() -> bool:
	if _target == null:
		return false
	if global_position.distance_to(_target.global_position) > detection_range:
		return false
	return _has_line_of_sight()


## Движение к цели. По умолчанию — по земле с гравитацией. Летающий переопределит.
func _move_towards_target(delta: float) -> void:
	_apply_gravity(delta)
	var to_target := _target.global_position - global_position
	to_target.y = 0.0  # только горизонталь
	var dir := to_target.normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
	move_and_slide()


## Атака. По умолчанию — ближний бой. Стреляющий переопределит (спавн снаряда).
func _perform_attack() -> void:
	if _target != null and _target.has_method("take_damage"):
		_target.take_damage(attack_damage)


## Смерть. По умолчанию — труп: стоп ИИ, снять коллизию, «положить» спрайт, исчезнуть.
func _on_death() -> void:
	_state = State.DEAD
	velocity = Vector3.ZERO
	# set_deferred — менять параметры физики безопасно вне шага симуляции.
	set_deferred(&"collision_layer", 0)
	set_deferred(&"collision_mask", 0)
	_sprite.rotation_degrees.z = 90.0
	get_tree().create_timer(2.0).timeout.connect(queue_free)


# --- Вспомогательное ---

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta


func _acquire_target() -> void:
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group(target_group) as Node3D


func _has_line_of_sight() -> bool:
	var space_state := get_world_3d().direct_space_state
	var from := global_position + _EYE_OFFSET
	var to := _target.global_position + _EYE_OFFSET
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]  # не «видеть» собственную капсулу
	var result := space_state.intersect_ray(query)
	# Видимость есть, если луч ни во что не упёрся ИЛИ упёрся в саму цель.
	if result.is_empty():
		return true
	return result.get("collider") == _target


## Временный визуал, пока нет пиксель-арта: силуэт с тёмной рамкой. Ноль веса билда.
## Появится спрайт — назначь texture в инспекторе, эта генерация сама отключится.
func _make_placeholder_texture() -> Texture2D:
	var w := 32
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))  # прозрачный фон
	var body := Color(0.7, 0.15, 0.15)
	var border := Color(0.1, 0.0, 0.0)
	for y in h:
		for x in w:
			var is_edge := x == 0 or y == 0 or x == w - 1 or y == h - 1
			img.set_pixel(x, y, border if is_edge else body)
	return ImageTexture.create_from_image(img)
