class_name MeleeWeapon
extends Weapon
## Ближний бой (бан-хаммер): ОДИН кадр спрайта, замах анимируется КОДОМ —
## поворот кадра вокруг «кулака» (занос вверх → мах по дуге вниз → возврат).
## Покадровая раскадровка не нужна; движение выходит плавнее (угол считается
## каждый тик, а не 3 рывковых кадра). Урон наносится с задержкой hit_delay —
## в визуальный момент удара, а не по клику.

@export_group("Замах")
## Полная длительность замаха, с.
@export var swing_time: float = 0.38
## Занос назад перед ударом, градусы (голова молота приподнимается вправо).
@export var windup_degrees: float = 16.0
## Угол удара, градусы (голова молота проносится по дуге вниз-влево).
@export var swing_degrees: float = 70.0
## Точка вращения (кулак) в долях кадра: (0,0) — левый верх, (1,1) — правый низ.
@export var pivot_ratio: Vector2 = Vector2(0.72, 0.95)
## Задержка нанесения урона от начала замаха, с (совпадает с «бум» в sfx_melee).
@export var hit_delay: float = 0.16

# Время с начала замаха, с. Отрицательное — покой.
var _swing_elapsed: float = -1.0


func _process(delta: float) -> void:
	super._process(delta)  # кулдаун/анимация/боб базы
	if _swing_elapsed < 0.0:
		return
	_swing_elapsed += delta
	if _swing_elapsed >= swing_time:
		_swing_elapsed = -1.0
	queue_redraw()


# Замах стартует вместе с эффектами выстрела (звук свиста/удара уже там).
func _show_effects() -> void:
	super._show_effects()
	_swing_elapsed = 0.0


# Урон — не мгновенно по клику, а в визуальный момент удара молота.
# Таймер уважает паузу (2-й аргумент false); связь с освобождённым узлом
# Godot рвёт сам, так что смерть игрока во время замаха безопасна.
func _fire() -> void:
	if hit_delay <= 0.0:
		super._fire()
		return
	get_tree().create_timer(hit_delay, false).timeout.connect(_do_hit)


func _do_hit() -> void:
	super._fire()


# Текущий угол замаха, радианы.
# Профиль по фазам: занос (0..0.28) → удар (0.28..0.55) → возврат (0.55..1).
func _swing_angle() -> float:
	if _swing_elapsed < 0.0:
		return 0.0
	var t: float = _swing_elapsed / swing_time
	var up: float = deg_to_rad(windup_degrees)
	var down: float = -deg_to_rad(swing_degrees)
	if t < 0.28:
		return up * smoothstep(0.0, 1.0, t / 0.28)          # плавный занос
	if t < 0.55:
		var u: float = (t - 0.28) / 0.27
		return lerpf(up, down, u * u)                        # ускоряющийся мах
	return lerpf(down, 0.0, smoothstep(0.0, 1.0, (t - 0.55) / 0.45))  # возврат


# Как базовый рендер кадра, но с поворотом вокруг кулака во время замаха.
func _draw_sprite() -> void:
	var angle: float = _swing_angle()
	if absf(angle) < 0.0001:
		super._draw_sprite()  # покой — обычная отрисовка базы (с бобом)
		return
	var dest: Rect2 = _frame_dest_rect()  # позиция/размер — общий расчёт базы
	# draw_set_transform: система координат последующих draw-вызовов
	# переносится в pivot и поворачивается — рисуем кадр ОТНОСИТЕЛЬНО кулака.
	var pivot: Vector2 = dest.position + dest.size * pivot_ratio
	draw_set_transform(pivot, angle, Vector2.ONE)
	draw_texture_rect_region(sprite, Rect2(dest.position - pivot, dest.size),
			_frame_src_rect())
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
