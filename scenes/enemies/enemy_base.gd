class_name EnemyBase
extends CharacterBody3D
## Базовый враг: наземный, ближний бой. Играбелен «как есть» и служит базой.
## Расширение без копипасты: (1) другие цифры — @export в наследнике;
## (2) другое поведение — переопределить хук.

enum State { IDLE, CHASE, ATTACK, DEAD }

@export_group("Характеристики")
@export var move_speed: float = 4.0
@export var detection_range: float = 18.0
@export var attack_range: float = 2.0
@export var attack_damage: float = 8.0
@export var attack_cooldown: float = 1.2
@export var gravity: float = 24.0

@export_group("Цель")
@export var target_group: StringName = &"player"

@onready var _health: HealthComponent = $HealthComponent
@onready var _sprite: DirectionalSprite3D = $Sprite3D

var _target: Node3D
var _state: State = State.IDLE
var _attack_timer: float = 0.0
const _EYE_OFFSET := Vector3(0.0, 1.0, 0.0)


func _ready() -> void:
	_health.died.connect(_on_death)
	# Вспышка боли при уроне (но не на добивающем — там играет смерть).
	_health.health_changed.connect(_on_health_changed)


func take_damage(amount: float) -> void:
	_health.take_damage(amount)


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	if _attack_timer > 0.0:
		_attack_timer -= delta
	_acquire_target()
	match _state:
		State.IDLE: _state_idle(delta)
		State.CHASE: _state_chase(delta)
		State.ATTACK: _state_attack(delta)


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
		_state = State.IDLE
		return
	_sprite.play(&"walk")
	_move_towards_target(delta)


func _state_attack(delta: float) -> void:
	_apply_gravity(delta)
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()
	if _target == null:
		_state = State.IDLE
		return
	# Бьём — значит смотрим на цель.
	_face_dir(_target.global_position - global_position)
	if global_position.distance_to(_target.global_position) > attack_range:
		_state = State.CHASE
		return
	if _attack_timer <= 0.0:
		_attack_timer = attack_cooldown
		_perform_attack()


# --- Хуки для переопределения у наследников ---

func _can_see_target() -> bool:
	if _target == null:
		return false
	if global_position.distance_to(_target.global_position) > detection_range:
		return false
	return _has_line_of_sight()


func _move_towards_target(delta: float) -> void:
	_apply_gravity(delta)
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	var dir := to_target.normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
	_face_dir(dir)  # смотрим, куда идём — отсюда и берутся думовские ракурсы
	move_and_slide()


func _perform_attack() -> void:
	_sprite.play(&"attack")
	if _target != null and _target.has_method("take_damage"):
		_target.take_damage(attack_damage)


func _on_death() -> void:
	_state = State.DEAD
	velocity = Vector3.ZERO
	set_deferred(&"collision_layer", 0)
	set_deferred(&"collision_mask", 0)
	_sprite.play(&"death")
	get_tree().create_timer(2.0).timeout.connect(queue_free)


# --- Вспомогательное ---

func _on_health_changed(current: float, _maximum: float) -> void:
	# Жив после удара — вспышка. Ноль (добили) — пропуск, играет смерть.
	if current > 0.0:
		_sprite.flash_pain()


## Повернуть тело по горизонтали в сторону d (его -Z станет смотреть туда).
## Спрайт-биллборд это не вращает визуально — поворот нужен лишь как «взгляд»
## для выбора ракурса в DirectionalSprite3D. Капсула симметрична — физике всё равно.
func _face_dir(d: Vector3) -> void:
	var flat := Vector3(d.x, 0.0, d.z)
	if flat.length() < 0.01:
		return
	look_at(global_position + flat, Vector3.UP)


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
	query.exclude = [get_rid()]
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return true
	return result.get("collider") == _target
