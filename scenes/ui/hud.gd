class_name Hud
extends Control
## Экранный HUD: здоровье (полоска + число) слева внизу, патроны активного оружия
## справа. Всё рисуется кодом (ноль веса билда). Game Over живёт отдельно — это
## оверлей роутера (Game), HUD о нём не знает.

@export_group("Здоровье")
## Размер полоски здоровья, px.
@export var bar_size: Vector2 = Vector2(240.0, 22.0)
## Отступ от краёв экрана, px.
@export var margin: float = 24.0
## Цвет полоски при нормальном здоровье.
@export var color_ok: Color = Color(0.2, 0.8, 0.25)
## Цвет полоски при низком здоровье.
@export var color_low: Color = Color(0.85, 0.2, 0.15)
## Доля здоровья, ниже которой полоска краснеет.
@export_range(0.0, 1.0) var low_threshold: float = 0.3
## Цвет числа брони.
@export var color_armor: Color = Color(0.55, 0.72, 0.95)

@export_group("Шрифт")
@export var hp_font_size: int = 28
@export var ammo_font_size: int = 28

const _BG := Color(0.0, 0.0, 0.0, 0.5)
const _TEXT := Color(1.0, 1.0, 1.0, 0.95)

var _current: float = 0.0
var _maximum: float = 1.0
var _armor_current: float = 0.0
var _armor_max: float = 0.0

# --- Патроны активного оружия ---
# Тип, который сейчас отображаем (задаёт main по активному оружию).
var _active_type: StringName = &""
var _ammo_current: int = 0
var _ammo_max: int = 0
# Пока данных о патронах нет — рисуем «∞» (фолбэк, если система не подключена).
var _ammo_known: bool = false


func _ready() -> void:
	# Не перехватываем мышь — клики/выстрелы идут мимо HUD к игре.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Перерисовка при ресайзе окна (важно для веба).
	resized.connect(queue_redraw)


## Обновить здоровье. Подключается к HealthComponent.health_changed.
func set_health(current: float, maximum: float) -> void:
	_current = current
	_maximum = maximum
	queue_redraw()

## Обновить броню. Подключается к ArmorComponent.armor_changed.
func set_armor(current: float, maximum: float) -> void:
	_armor_current = current
	_armor_max = maximum
	queue_redraw()

## Какой тип патронов показывать. Задаёт main по активному оружию
## (при переключении стволов — активное оружие).
func set_active_ammo_type(type: StringName) -> void:
	_active_type = type
	queue_redraw()


## Обновить патроны. Подключается к AmmoComponent.ammo_changed.
## Реагируем только на активный тип — остальные пулы на HUD не показываем.
func on_ammo_changed(type: StringName, current: int, maximum: int) -> void:
	if type != _active_type:
		return
	_ammo_current = current
	_ammo_max = maximum
	_ammo_known = true
	queue_redraw()


func _draw() -> void:
	_draw_hud()


func _draw_hud() -> void:
	var font := get_theme_default_font()

	# --- Полоска здоровья (низ-слева) ---
	var bar_pos := Vector2(margin, size.y - margin - bar_size.y)
	draw_rect(Rect2(bar_pos, bar_size), _BG)

	var frac := 0.0
	if _maximum > 0.0:
		frac = clampf(_current / _maximum, 0.0, 1.0)
	var fill := color_ok if frac > low_threshold else color_low
	draw_rect(Rect2(bar_pos, Vector2(bar_size.x * frac, bar_size.y)), fill)

	# Число HP над полоской (y в draw_string — это базовая линия текста).
	var hp_text := "HP %d" % int(roundf(_current))
	draw_string(font, bar_pos - Vector2(0.0, 8.0), hp_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, hp_font_size, _TEXT)

	# Число брони — стопкой над числом HP, в том же углу.
	var arm_text := "ARM %d" % int(roundf(_armor_current))
	draw_string(font, bar_pos - Vector2(0.0, 8.0 + hp_font_size + 4.0), arm_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, hp_font_size, color_armor)

	# --- Патроны (низ-справа). Число активного типа; «∞» — пока система не подключена. ---
	var ammo := str(_ammo_current) if _ammo_known else "∞"
	var ammo_w := font.get_string_size(ammo, HORIZONTAL_ALIGNMENT_LEFT, -1, ammo_font_size).x
	draw_string(font, Vector2(size.x - margin - ammo_w, size.y - margin), ammo,
			HORIZONTAL_ALIGNMENT_LEFT, -1, ammo_font_size, _TEXT)
