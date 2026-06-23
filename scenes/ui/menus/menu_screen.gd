class_name MenuScreen
extends CanvasLayer
## Переиспользуемый экран меню/оверлея. Заголовок, опциональный текст и список
## кнопок строятся КОДОМ (ноль веса билда, как HUD/крестик). Один и тот же узел
## обслуживает главное меню, паузу, Game Over и заглушки — различие только в
## данных, которые роутер задаёт ПЕРЕД add_child.
##
## Работает на паузе (PROCESS_MODE_ALWAYS): когда роутер ставит дерево на паузу
## ради оверлея, само меню должно остаться живым и кликабельным.

## Игрок выбрал пункт. Несёт id пункта (или back_id при Esc). Роутер разбирает.
signal selected(id: StringName)

# --- Конфиг: роутер задаёт эти поля до add_child, _ready их читает ---
## Заголовок вверху. Пусто — не рисуется.
var title_text: String = ""
## Абзац под заголовком (для заглушек). Пусто — не рисуется.
var body_text: String = ""
## Кнопки: массив словарей {"id": StringName, "label": String}.
var items: Array = []
## Затемнение фона: 0 — прозрачный (виден геймплей), 1 — непрозрачный.
var dim: float = 0.85
## Что эмитим по Esc. Пусто — Esc игнорируется (главное меню, Game Over).
var back_id: StringName = &""
## Слой CanvasLayer. HUD на 1, меню — заметно выше, оверлеи ещё выше.
var layer_index: int = 20

const _TITLE_COLOR := Color(0.85, 0.22, 0.16)
const _TEXT_COLOR := Color(0.92, 0.92, 0.92)

# Корневой Control (полный экран): ловит клики, не пускает их в геймплей под собой.
var _root: Control = null
# Активен ли экран: только активный (верхний) реагирует на Esc.
var _active: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = layer_index
	_build()


# Построить интерфейс кодом: фон + центрированная колонка (заголовок/текст/кнопки).
func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# STOP — клики по экрану меню не проваливаются в 3D-сцену/нижние слои.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, dim)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)

	if not title_text.is_empty():
		var title := Label.new()
		title.text = title_text
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 56)
		title.add_theme_color_override("font_color", _TITLE_COLOR)
		column.add_child(title)
		column.add_child(_spacer(16))

	if not body_text.is_empty():
		var body := Label.new()
		body.text = body_text
		body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(440.0, 0.0)
		body.add_theme_font_size_override("font_size", 22)
		body.add_theme_color_override("font_color", _TEXT_COLOR)
		column.add_child(body)
		column.add_child(_spacer(16))

	var first_button: Button = null
	for item: Dictionary in items:
		var button := Button.new()
		button.text = String(item["label"])
		button.custom_minimum_size = Vector2(280.0, 46.0)
		button.add_theme_font_size_override("font_size", 24)
		# Захват id в лямбду: каждая кнопка эмитит свой пункт.
		var id: StringName = item["id"]
		button.pressed.connect(func() -> void: selected.emit(id))
		column.add_child(button)
		if first_button == null:
			first_button = button

	# Фокус на первую кнопку — навигация стрелками/Enter с клавиатуры.
	if first_button != null:
		first_button.grab_focus()


func _spacer(height: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0.0, height)
	return s


# Активным остаётся только верхний оверлей — чтобы Esc уходил ему одному.
func set_active(active: bool) -> void:
	_active = active
	set_process_unhandled_input(active)


func _unhandled_input(event: InputEvent) -> void:
	if not _active or back_id.is_empty():
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		selected.emit(back_id)
