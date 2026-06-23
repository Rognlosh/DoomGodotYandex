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

@export_group("Смерть")
## Через сколько секунд труп исчезает. 0 — остаётся навсегда (труп-декорация).
@export var corpse_lifetime: float = 0.0

@export_group("Отброс взрывом")
## Делитель импульса отброса (≈ масса). >1 — враг тяжелее, отлетает слабее.
@export var knockback_mass: float = 1.0
## Затухание импульса отброса, ед/с (и у живого, и при оседании трупа).
@export var knockback_damping: float = 12.0

@onready var _health: HealthComponent = $HealthComponent
@onready var _sprite: DirectionalSprite3D = $Sprite3D

var _target: Node3D
var _state: State = State.IDLE
var _attack_timer: float = 0.0
# Звук боя (находится по группе, лениво). null — звук не играет.
var _combat: CombatAudio
# Остаточный импульс отброса от взрыва (живого — гасит; труп — запускает в полёт).
var _knockback: Vector3 = Vector3.ZERO
# Труп, запущенный взрывом: летит по баллистике и оседает на пол.
var _launched: bool = false
const _EYE_OFFSET := Vector3(0.0, 1.0, 0.0)


func _ready() -> void:
	_health.died.connect(_on_death)
	# Спрайт боли при уроне (но не на добивающем — там играет смерть).
	_health.health_changed.connect(_on_health_changed)


func take_damage(amount: float) -> void:
	_health.take_damage(amount)


## Импульс отброса от взрыва (конвенция — снаряд зовёт по has_method).
## Уже лежащий труп (DEAD, не запущенный) не толкаем — но shape-запрос его и так
## не видит (на смерти collision_layer = 0), так что обычно сюда не доходит.
func apply_knockback(impulse: Vector3) -> void:
	if _state == State.DEAD and not _launched:
		return
	_knockback += impulse / maxf(knockback_mass, 0.01)


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		if _launched:
			_process_launch(delta)
		return
	# Внешний отброс взрывом — отдельным смещением поверх ИИ: ИИ каждый кадр
	# перезадаёт velocity, поэтому отброс двигаем через move_and_collide.
	if _knockback.length_squared() > 0.0001:
		move_and_collide(_knockback * delta)
		_knockback = _knockback.move_toward(Vector3.ZERO, knockback_damping * delta)
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
	_attack_movement(delta)   # по умолчанию — стоять; летун зависает/страйфит (хук)
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
		_play_combat(&"enemy_attack")  # на месте вызова — звучит у любого типа
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


## Движение во время атаки. По умолчанию — стоять на месте (наземные стрелок/рашер).
## Летун переопределяет: зависание на высоте + удержание отступа + страйф.
func _attack_movement(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _perform_attack() -> void:
	_sprite.play(&"attack")
	if _target != null and _target.has_method("take_damage"):
		_target.take_damage(attack_damage)


func _on_death() -> void:
	_state = State.DEAD
	# Труп невидим для лучей/запросов (не ловит пули, не блокирует). collision_mask
	# НЕ обнуляем: запущенный взрывом труп должен сталкиваться с полом/стенами.
	set_deferred(&"collision_layer", 0)
	_sprite.play(&"death", true)  # force — перебить возможную боль
	_play_combat(&"enemy_death")
	# Умер ОТ взрыва (есть импульс) — запускаем труп в полёт; иначе просто стоп.
	if _knockback.length() > 0.1:
		_launched = true
		velocity = _knockback
		_knockback = Vector3.ZERO
	else:
		velocity = Vector3.ZERO
	# Труп остаётся лежать; убираем, только если задан конечный срок жизни.
	if corpse_lifetime > 0.0:
		get_tree().create_timer(corpse_lifetime).timeout.connect(queue_free)


# Полёт трупа, запущенного взрывом: гаснет по горизонтали, падает, оседает на пол.
func _process_launch(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, knockback_damping * delta)
	velocity.z = move_toward(velocity.z, 0.0, knockback_damping * delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()
	# Лёг на пол и почти не движется — труп улёгся, дальше не процессим.
	if is_on_floor() and Vector2(velocity.x, velocity.z).length() < 0.4:
		velocity = Vector3.ZERO
		_launched = false


# --- Вспомогательное ---

func _on_health_changed(current: float, _maximum: float) -> void:
	# Жив после удара — кадр боли. Ноль (добили) — пропуск, играет смерть.
	if current > 0.0:
		_sprite.hurt()


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


# Ленивый поиск звука боя по группе (создаётся main). Кэшируем; нет — тишина.
func _play_combat(id: StringName) -> void:
	if _combat == null or not is_instance_valid(_combat):
		_combat = get_tree().get_first_node_in_group(&"combat_audio") as CombatAudio
	if _combat != null:
		_combat.play(id)


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
