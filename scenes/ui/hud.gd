class_name Hud
extends Control
## Экранный HUD: здоровье (полоска + число) слева внизу, патроны справа («∞» —
## плейсхолдер до системы патронов на Этапе 2). Всё рисуется кодом (ноль веса билда).
## Также показывает оверлей game-over и ловит клавишу рестарта — для этого работает
## даже на паузе (PROCESS_MODE_ALWAYS), т.к. при смерти игра ставится на паузу.

## Игрок нажал клавишу на экране смерти. main снимет паузу и перезагрузит сцену.
signal restart_requested

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

@export_group("Шрифт")
@export var hp_font_size: int = 28
@export var ammo_font_size: int = 28
@export var title_font_size: int = 72
@export var hint_font_size: int = 28

const _BG := Color(0.0, 0.0, 0.0, 0.5)
const _TEXT := Color(1.0, 1.0, 1.0, 0.95)
const _OVERLAY := Color(0.45, 0.0, 0.0, 0.5)

var _current: float = 0.0
var _maximum: float = 1.0
var _game_over: bool = false


func _ready() -> void:
	# Не перехватываем мышь — клики/выстрелы идут мимо HUD к игре.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Работаем даже на паузе: при смерти игра замирает, а HUD ловит клавишу рестарта.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Перерисовка при ресайзе окна (важно для веба).
	resized.connect(queue_redraw)


## Обновить здоровье. Подключается к HealthComponent.health_changed.
func set_health(current: float, maximum: float) -> void:
	_current = current
	_maximum = maximum
	queue_redraw()


## Показать экран смерти. Вызывает main по сигналу died.
func show_game_over() -> void:
	_game_over = true
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not _game_over:
		return
	# Любая клавиша или кнопка мыши — рестарт. echo (автоповтор зажатой клавиши) игнорируем.
	var key_pressed := event is InputEventKey and event.is_pressed() and not event.is_echo()
	var click_pressed := event is InputEventMouseButton and event.is_pressed()
	if key_pressed or click_pressed:
		get_viewport().set_input_as_handled()
		restart_requested.emit()


func _draw() -> void:
	if _game_over:
		_draw_game_over()
	else:
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

	# --- Патроны (низ-справа), пока «∞» ---
	var ammo := "∞"
	var ammo_w := font.get_string_size(ammo, HORIZONTAL_ALIGNMENT_LEFT, -1, ammo_font_size).x
	draw_string(font, Vector2(size.x - margin - ammo_w, size.y - margin), ammo,
			HORIZONTAL_ALIGNMENT_LEFT, -1, ammo_font_size, _TEXT)


func _draw_game_over() -> void:
	# Красная заливка поверх всей картинки.
	draw_rect(Rect2(Vector2.ZERO, size), _OVERLAY)

	var font := get_theme_default_font()
	var center := size * 0.5

	var title := "YOU DIED"
	var title_w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_font_size).x
	draw_string(font, center - Vector2(title_w * 0.5, 0.0), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, title_font_size, _TEXT)

	var hint := "Нажми любую клавишу"
	var hint_w := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hint_font_size).x
	draw_string(font, center + Vector2(-hint_w * 0.5, 48.0), hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, hint_font_size, _TEXT)
