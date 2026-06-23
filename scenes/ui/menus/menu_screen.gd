class_name MenuScreen
extends CanvasLayer
## Переиспользуемый экран меню/оверлея. Заголовок, опциональный текст и список
## кнопок строятся КОДОМ (ноль веса билда, как HUD/крестик). Один и тот же узел
## обслуживает главное меню, паузу, Game Over и заглушки — различие только в
## данных, которые роутер задаёт ПЕРЕД add_child.
##
## Работает на паузе (PROCESS_MODE_ALWAYS): когда роутер ставит дерево на паузу
## ради оверлея, само меню должно остаться живым и кликабельным.

## Игрок выбрал пункт-кнопку. Несёт id пункта (или back_id при Esc). Роутер разбирает.
signal selected(id: StringName)
## Игрок подвинул ползунок. Несёт id пункта и новое значение. Роутер разбирает
## (параллельно selected — кнопки шлют одно, ползунки другое).
signal value_changed(id: StringName, value: float)

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

	# Каждый пункт — кнопка (по умолчанию) или ползунок (type == &"slider").
	# Фокус ставим на первый фокусируемый элемент — навигация стрелками/Enter.
	var first_focus: Control = null
	for item: Dictionary in items:
		var focusable: Control
		if StringName(item.get("type", &"button")) == &"slider":
			focusable = _add_slider(column, item)
		else:
			focusable = _add_button(column, item)
		if first_focus == null:
			first_focus = focusable

	if first_focus != null:
		first_focus.grab_focus()


# Пункт-кнопка: эмитит свой id по нажатию.
func _add_button(column: VBoxContainer, item: Dictionary) -> Button:
	var button := Button.new()
	button.text = String(item["label"])
	button.custom_minimum_size = Vector2(280.0, 46.0)
	button.add_theme_font_size_override("font_size", 24)
	# Захват id в лямбду: каждая кнопка эмитит свой пункт.
	var id: StringName = item["id"]
	button.pressed.connect(func() -> void: selected.emit(id))
	column.add_child(button)
	return button


# Пункт-ползунок: подпись с процентом заполнения + HSlider, эмитит value_changed.
# Конфиг пункта: {id, label, min, max, value, step}.
func _add_slider(column: VBoxContainer, item: Dictionary) -> HSlider:
	var id: StringName = item["id"]
	var label_text := String(item["label"])
	var lo := float(item["min"])
	var hi := float(item["max"])

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var caption := Label.new()
	caption.add_theme_font_size_override("font_size", 20)
	caption.add_theme_color_override("font_color", _TEXT_COLOR)
	row.add_child(caption)

	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(320.0, 0.0)
	slider.min_value = lo
	slider.max_value = hi
	slider.step = float(item.get("step", 0.01))
	slider.value = float(item["value"])
	row.add_child(slider)
	column.add_child(row)

	# Читалку и обработчик держим именованными методами (без многострочных лямбд —
	# их парсер капризнее; bind() надёжнее). Сигнал value_changed отдаёт value
	# первым аргументом, остальное добавляет bind().
	_update_slider_caption(caption, label_text, lo, hi, slider.value)
	slider.value_changed.connect(
		_on_slider_changed.bind(id, caption, label_text, lo, hi)
	)
	return slider


# Ползунок сдвинут: обновить подпись и пробросить значение наверх.
func _on_slider_changed(value: float, id: StringName, caption: Label,
		label_text: String, lo: float, hi: float) -> void:
	_update_slider_caption(caption, label_text, lo, hi, value)
	value_changed.emit(id, value)


# Подпись ползунка — процент заполнения диапазона (универсально для любого ползунка:
# громкость 0..1 даёт 0..100%, чувствительность — % своего диапазона).
func _update_slider_caption(caption: Label, label_text: String,
		lo: float, hi: float, value: float) -> void:
	var pct := 0
	if hi > lo:
		pct = int(round((value - lo) / (hi - lo) * 100.0))
	caption.text = "%s: %d%%" % [label_text, pct]


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
