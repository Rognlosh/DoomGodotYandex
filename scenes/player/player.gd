extends CharacterBody3D
## Контроллер игрока в стиле DOOM/GZDoom: быстрый, резкий, с малой инерцией.
## Отвечает ТОЛЬКО за перемещение и обзор мышью.
## Здоровье, оружие и прочее добавляются отдельными дочерними компонентами
## (композиция), а не дописываются в этот скрипт.

@export_group("Движение")
## Максимальная скорость перемещения по земле, м/с.
@export var speed: float = 9.0
## Ускорение разгона (высокое значение = резкий старт, малая инерция).
@export var acceleration: float = 90.0
## Торможение при отсутствии ввода.
@export var friction: float = 90.0
## Управляемость в воздухе: 0 — нет контроля, 1 — как на земле.
@export_range(0.0, 1.0) var air_control: float = 0.4

@export_group("Прыжок и гравитация")
## Начальная вертикальная скорость прыжка, м/с.
@export var jump_velocity: float = 7.0
## Сила гравитации, м/с². Больше дефолтных 9.8 — прыжок резче, без «лунного» зависания.
@export var gravity: float = 24.0

@export_group("Отзывчивость прыжка")
## Буфер прыжка: если нажать прыжок за это время ДО приземления — он сработает при касании земли, с.
@export var jump_buffer_time: float = 0.1
## Койот-тайм: можно прыгнуть ещё это время ПОСЛЕ схода с края, с. 0 — выключить.
@export var coyote_time: float = 0.1

@export_group("Обзор мышью")
## Чувствительность мыши: радиан поворота на пиксель смещения курсора.
@export var mouse_sensitivity: float = 0.0025
## Предел наклона камеры вверх/вниз, градусы (чтобы не перевернуться через голову).
@export var pitch_limit_deg: float = 89.0

# Узел-«голова»: точка наклона (pitch). Камера висит на нём.
@onready var head: Node3D = $Head
# Здоровье игрока — тот же переиспользуемый компонент, что у врага.
@onready var _health: HealthComponent = $HealthComponent
# Боезапас игрока — переиспользуемый компонент (пулы патронов по типам).
@onready var _ammo: AmmoComponent = $AmmoComponent
# Броня игрока — отдельное звено перед HP (модель DOOM). Опциональна.
@onready var _armor: ArmorComponent = get_node_or_null("ArmorComponent")

# Таймеры отзывчивости прыжка (обратный отсчёт в секундах).
var _jump_buffer_timer: float = 0.0
var _coyote_timer: float = 0.0


func _ready() -> void:
	# На старте курсор свободен. В браузере захват (pointer lock) разрешён
	# только после клика пользователя — поэтому захватываем по клику мыши.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Чувствительность — из глобальных настроек (а не только из @export):
	# берём текущее значение и слушаем изменения, чтобы правка ползунка в паузе
	# применялась к живому игроку сразу. @export остаётся дефолтом-фолбэком.
	mouse_sensitivity = Settings.mouse_sensitivity
	Settings.mouse_sensitivity_changed.connect(_on_sensitivity_changed)


func _on_sensitivity_changed(value: float) -> void:
	mouse_sensitivity = value


# Конвенция урона: тело принимает урон и делегирует в компонент (как у врага).
# Реакцию на died/health_changed решают снаружи (main → пауза+оверлей, HUD → бар).
func take_damage(amount: float) -> void:
	# Урон сперва идёт в броню (если есть): она снимает свою долю, остаток — в HP.
	if _armor != null:
		amount = _armor.absorb(amount)
	_health.take_damage(amount)

# Конвенция пополнения: тело принимает патроны и делегирует в AmmoComponent
# (как take_damage — в HealthComponent). Пикап не знает о внутренностях игрока.
func add_ammo(type: StringName, amount: int) -> int:
	return _ammo.add_ammo(type, amount)

# Конвенция лечения: тело лечится и делегирует в HealthComponent.
# allow_overheal пробрасывает пикап (бонус-склянка/сфера души).
func heal(amount: float, allow_overheal: bool = false) -> bool:
	return _health.heal(amount, allow_overheal)

# Конвенция брони: тело принимает броню и делегирует в ArmorComponent.
# set_mode=true — комплект (установка до points класса klass); false — бонус (+points).
func add_armor(points: float, klass: int, set_mode: bool) -> bool:
	if _armor == null:
		return false
	if set_mode:
		return _armor.give_armor(points, klass)
	return _armor.add_bonus(points)


func _input(event: InputEvent) -> void:
	# Захват курсора по клику обрабатываем здесь, в _input (раньше _unhandled_input),
	# и поглощаем событие — чтобы «захватывающий» клик только захватил курсор
	# и не дошёл до оружия как выстрел.
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# Обзор мышью работает только при захваченном курсоре.
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_aim(motion.relative)


func _aim(mouse_delta: Vector2) -> void:
	# Поворот (yaw) вращает всё тело по оси Y — задаёт направление движения.
	rotate_y(-mouse_delta.x * mouse_sensitivity)
	# Наклон (pitch) вращает только голову по оси X — на движение не влияет.
	head.rotation.x -= mouse_delta.y * mouse_sensitivity
	var limit: float = deg_to_rad(pitch_limit_deg)
	head.rotation.x = clampf(head.rotation.x, -limit, limit)


## Поставить игрока в точку спавна (нового уровня/рестарта): позиция и поворот
## из маркера, обнулить скорость и наклон головы — иначе перенесётся инерция
## и наклон взгляда с прошлого места. Зовётся сессией после add_child.
func teleport_to(xform: Transform3D) -> void:
	global_transform = xform
	velocity = Vector3.ZERO
	head.rotation.x = 0.0


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()

	# --- Вертикаль: гравитация ---
	if not on_floor:
		velocity.y -= gravity * delta

	# Койот-тайм: на земле окно полное, в воздухе — обратный отсчёт.
	if on_floor:
		_coyote_timer = coyote_time
	else:
		_coyote_timer -= delta

	# Буфер прыжка: запоминаем нажатие на короткое окно.
	if Input.is_action_just_pressed(&"jump"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer -= delta

	# Прыжок: было недавнее нажатие (буфер) И мы недавно были на земле (койот).
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0  # сброс, чтобы не прыгнуть дважды

	# --- Горизонталь: WASD относительно поворота тела ---
	var input_dir: Vector2 = Input.get_vector(
		&"move_left", &"move_right", &"move_forward", &"move_back"
	)
	# transform.basis переводит локальный ввод в мировое направление с учётом yaw.
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var target_velocity: Vector3 = direction * speed
	var current_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)

	# Резкий разгон при вводе, резкое торможение без ввода.
	var rate: float = acceleration if direction != Vector3.ZERO else friction
	# В воздухе управляемость ослаблена.
	if not on_floor:
		rate *= air_control

	var new_velocity: Vector3 = current_velocity.move_toward(target_velocity, rate * delta)
	velocity.x = new_velocity.x
	velocity.z = new_velocity.z

	move_and_slide()
