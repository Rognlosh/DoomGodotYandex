class_name Hud
extends Control
## Нижняя статус-панель в классической DOOM-компоновке, рисуется целиком кодом
## в _draw (ноль веса билда). Слева направо: ПАТРОНЫ (активный ствол) · РАССУДОК
## (HP, %) · АРСЕНАЛ (сетка слотов) · мугшот · АДБЛОК (броня, %) · таблица всех
## пулов. Крупные красные числа, подписи снизу, бевел-фаски ретро-ОС — как в DOOM
## (полосок-прогрессов нет: состояние читается числом и лицом).
##
## Панель якорится по нижнему краю и накрывает нижние ~panel_height_ratio экрана —
## контракт с оружием (weapon.gd тукается за неё через ui_tuck_ratio). Game Over —
## отдельный оверлей роутера, HUD о нём не знает.

@export_group("Панель")
## Высота панели в долях высоты вьюпорта (DOOM ≈ 0.16–0.18).
@export_range(0.08, 0.30) var panel_height_ratio: float = 0.17
## Толщина бевел-фаски, px.
@export var bevel_width: float = 3.0
## Заливка панели (металл-серый, как в DOOM).
@export var panel_fill: Color = Color(0.55, 0.53, 0.5)
## Заливка утопленных боксов (мугшот, сетка).
@export var inset_fill: Color = Color(0.09, 0.09, 0.11)
## Светлая грань фаски (верх-лево).
@export var bevel_light: Color = Color(0.74, 0.72, 0.68)
## Тёмная грань фаски (низ-право).
@export var bevel_dark: Color = Color(0.24, 0.23, 0.21)
## Безопасное поле СЛЕВА (доля ширины панели): содержимое не заходит в край.
## Фон панели остаётся во всю ширину — двигается только начинка.
@export_range(0.0, 0.3, 0.005) var safe_left_ratio: float = 0.0
## Безопасное поле СПРАВА (доля ширины панели). Правая рекламная колонка портала
## Яндекса — непрозрачный оверлей поверх края канваса; правый бокс HUD уходил под
## неё. Инсет уводит таблицу пулов левее рейла. Подкрутить под фактическую ширину.
@export_range(0.0, 0.3, 0.005) var safe_right_ratio: float = 0.16

@export_group("Числа")
## Цвет крупных чисел (ПАТРОНЫ/РАССУДОК/АДБЛОК) — думовский красный.
@export var color_number: Color = Color(0.82, 0.12, 0.08)
## Цвет числа HP при низком рассудке (мигает ярче).
@export var color_number_low: Color = Color(1.0, 0.5, 0.15)
## Доля HP, ниже которой число краснеет/ярчает.
@export_range(0.0, 1.0) var low_threshold: float = 0.3

@export_group("Арсенал (ARMS)")
## Цвет номера занятого слота.
@export var color_arm_owned: Color = Color(0.88, 0.72, 0.32)
## Цвет номера незанятого слота.
@export var color_arm_off: Color = Color(0.3, 0.29, 0.27)
## Цвет номера активного слота (подсветка).
@export var color_arm_active: Color = Color(1.0, 0.95, 0.55)

@export_group("Подписи и таблица")
## Цвет подписей под числами.
@export var color_label: Color = Color(0.12, 0.11, 0.1)
## Цвет чисел в таблице пулов.
@export var color_pool: Color = Color(0.82, 0.12, 0.08)
## Цвет подписи неактивного пула в таблице.
@export var color_pool_dim: Color = Color(0.28, 0.27, 0.25)
## Цвет подписи активного пула в таблице.
@export var color_pool_active: Color = Color(0.88, 0.72, 0.32)
@export var label_ammo: String = "ПАТРОНЫ"
@export var label_hp: String = "РАССУДОК"
@export var label_arms: String = "АРСЕНАЛ"
@export var label_armor: String = "АДБЛОК"
## Короткие имена пулов для таблицы (id -> подпись).
@export var pool_labels: Dictionary = {
	&"bullets": "ПУЛИ",
	&"shells": "ДРОБЬ",
	&"rockets": "РАКЕТЫ",
}

@export_group("Мугшот")
## Стрип кадров-лиц (по состояниям HP, последний — «мёртвый»). null — векторный
## плейсхолдер-лицо на каждое состояние.
@export var mugshot_strip: Texture2D
## Кадров в стрипе (5 живых + мёртвый = 6).
@export var mugshot_frames: int = 6

# Слоты для сетки ARMS (как в DOOM: 2 3 4 / 5 6 7; слот 1 — «кулак», не показан).
const _ARMS_SLOTS: Array[int] = [2, 3, 4, 5, 6, 7]

# --- Состояние показателей (пушится извне через сеттеры) ---
var _current: float = 0.0
var _maximum: float = 1.0
var _armor_current: float = 0.0
var _armor_max: float = 0.0

var _active_type: StringName = &""
var _active_uses_ammo: bool = true
# id пула -> Vector2i(current, maximum). Порядок вставки = порядок ammo_types.
var _pools: Dictionary = {}

# Занятые слоты оружия и активный слот (для сетки ARMS).
var _owned_slots: Array[int] = []
var _active_slot: int = 0


func _ready() -> void:
	# Не перехватываем мышь — клики/выстрелы идут мимо HUD к игре.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Пиксель-арт мугшота рисуется без сглаживания (векторные фигуры не задевает).
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Перерисовка при ресайзе окна (важно для веба).
	resized.connect(queue_redraw)


# --------------------------------------------------------------------------
# Сеттеры (call down от main; сам HUD ни о ком не знает — signal up снаружи)
# --------------------------------------------------------------------------

## Обновить HP. Подключается к HealthComponent.health_changed.
func set_health(current: float, maximum: float) -> void:
	_current = current
	_maximum = maximum
	queue_redraw()


## Обновить броню. Подключается к ArmorComponent.armor_changed.
func set_armor(current: float, maximum: float) -> void:
	_armor_current = current
	_armor_max = maximum
	queue_redraw()


## Какой пул показывать в блоке ПАТРОНЫ. uses_ammo=false (меле) → «—».
func set_active_ammo_type(type: StringName, uses_ammo: bool = true) -> void:
	_active_type = type
	_active_uses_ammo = uses_ammo
	queue_redraw()


## Обновить пул. Подключается к AmmoComponent.ammo_changed. Кэшируем все пулы.
func on_ammo_changed(type: StringName, current: int, maximum: int) -> void:
	_pools[type] = Vector2i(current, maximum)
	queue_redraw()


## Занятые слоты оружия (сетка ARMS). Задаёт main из WeaponManager при привязке.
func set_owned_slots(slots: Array[int]) -> void:
	_owned_slots = slots
	queue_redraw()


## Активный слот оружия (подсветка в ARMS). Задаёт main при смене ствола.
func set_active_slot(slot: int) -> void:
	_active_slot = slot
	queue_redraw()


# --------------------------------------------------------------------------
# Отрисовка — раскладка DOOM
# --------------------------------------------------------------------------

func _draw() -> void:
	var font := get_theme_default_font()
	var h := size.y * panel_height_ratio
	var panel := Rect2(0.0, size.y - h, size.x, h)

	# Корпус панели: заливка + приподнятая фаска.
	draw_rect(panel, panel_fill)
	_bevel(panel, true)

	# Безопасная зона: фон панели во всю ширину, а содержимое (inner) уводим от
	# краёв, чтобы правый бокс не прятался под рекламный оверлей портала.
	var pad := h * 0.10
	var safe_l := panel.size.x * safe_left_ratio
	var safe_r := panel.size.x * safe_right_ratio
	var inner := Rect2(
			panel.position + Vector2(pad + safe_l, pad),
			panel.size - Vector2(pad * 2.0 + safe_l + safe_r, pad * 2.0))

	# Мугшот — квадрат по высоте, по центру панели.
	var face_side := inner.size.y
	var face_x := inner.position.x + (inner.size.x - face_side) * 0.5
	var face_rect := Rect2(face_x, inner.position.y, face_side, face_side)
	var gap := h * 0.10

	# Левая половина: ПАТРОНЫ | РАССУДОК | АРСЕНАЛ.
	var left := Rect2(inner.position,
			Vector2(face_x - gap - inner.position.x, inner.size.y))
	# Правая половина: АДБЛОК | таблица пулов.
	var right := Rect2(Vector2(face_rect.end.x + gap, inner.position.y),
			Vector2(inner.end.x - (face_rect.end.x + gap), inner.size.y))

	# --- Левая половина (веса колонок) ---
	_num_cell(_hslice(left, 0.00, 0.30), _ammo_text(), label_ammo, color_number, font)
	_num_cell(_hslice(left, 0.30, 0.66), "%d%%" % int(roundf(_current)), label_hp,
			_hp_color(), font)
	_draw_arms(_hslice(left, 0.66, 1.00), font)

	_draw_mugshot(face_rect)

	# --- Правая половина ---
	_num_cell(_hslice(right, 0.00, 0.42), "%d%%" % int(roundf(_armor_current)),
			label_armor, color_number, font)
	_draw_pool_table(_hslice(right, 0.44, 1.00), font)


# Крупное число сверху + подпись снизу (блок ПАТРОНЫ/РАССУДОК/АДБЛОК).
func _num_cell(rect: Rect2, value: String, label: String, color: Color, font: Font) -> void:
	if rect.size.x <= 0.0:
		return
	var value_fs := maxi(12, int(rect.size.y * 0.54))
	var label_fs := _fit_fs(font, label, maxi(8, int(rect.size.y * 0.18)), rect.size.x * 0.98)

	var vw := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, value_fs).x
	draw_string(font, Vector2(rect.get_center().x - vw * 0.5,
			rect.position.y + rect.size.y * 0.63), value,
			HORIZONTAL_ALIGNMENT_LEFT, -1, value_fs, color)

	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_fs).x
	draw_string(font, Vector2(rect.get_center().x - lw * 0.5, rect.end.y - label_fs * 0.15),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_fs, color_label)


# Сетка ARMS: номера слотов 2 3 4 / 5 6 7 (занятый — ярко, активный — подсвечен).
func _draw_arms(rect: Rect2, font: Font) -> void:
	if rect.size.x <= 0.0:
		return
	var label_fs := _fit_fs(font, label_arms, maxi(8, int(rect.size.y * 0.18)), rect.size.x * 0.98)
	var grid := Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.78))
	var box := grid.grow(-bevel_width)
	draw_rect(box, inset_fill)
	_bevel(box, false)

	var cw := box.size.x / 3.0
	var ch := box.size.y / 2.0
	var fs := maxi(9, int(ch * 0.7))
	for i in _ARMS_SLOTS.size():
		var s := _ARMS_SLOTS[i]
		var col := i % 3
		var row := i / 3
		var col_color := color_arm_off
		if s == _active_slot:
			col_color = color_arm_active
		elif _owned_slots.has(s):
			col_color = color_arm_owned
		var text := str(s)
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cx := box.position.x + (col + 0.5) * cw - tw * 0.5
		var cy := box.position.y + (row + 0.5) * ch + fs * 0.35
		draw_string(font, Vector2(cx, cy), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col_color)

	var lw := font.get_string_size(label_arms, HORIZONTAL_ALIGNMENT_LEFT, -1, label_fs).x
	draw_string(font, Vector2(rect.get_center().x - lw * 0.5, rect.end.y - label_fs * 0.15),
			label_arms, HORIZONTAL_ALIGNMENT_LEFT, -1, label_fs, color_label)


# Таблица всех пулов: строки «ПУЛИ 45 / 200», активный пул — ярче.
func _draw_pool_table(rect: Rect2, font: Font) -> void:
	if rect.size.x <= 0.0 or _pools.is_empty():
		return
	var box := rect.grow(-bevel_width)
	draw_rect(box, inset_fill)
	_bevel(box, false)
	var inner := box.grow(-box.size.y * 0.1)

	var n := _pools.size()
	var row_h := inner.size.y / float(n)
	var fs := maxi(8, int(row_h * 0.72))
	var col_num := inner.position.x + inner.size.x * 0.5  # где начинаются числа
	var i := 0
	for type: StringName in _pools:
		var pool: Vector2i = _pools[type]
		var y := inner.position.y + (i + 0.5) * row_h + fs * 0.35
		var lab_color := color_pool_active if type == _active_type else color_pool_dim
		# Подпись пула слева.
		draw_string(font, Vector2(inner.position.x, y), _pool_label(type),
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, lab_color)
		# «cur / max» справа.
		var nums := "%d / %d" % [pool.x, pool.y]
		var nw := font.get_string_size(nums, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(inner.end.x - nw, y), nums,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color_pool)
		i += 1


# --------------------------------------------------------------------------
# Мугшот
# --------------------------------------------------------------------------

func _draw_mugshot(rect: Rect2) -> void:
	draw_rect(rect, Color(0.04, 0.04, 0.06))
	_bevel(rect, false)
	var inner := rect.grow(-bevel_width)

	if mugshot_strip != null and mugshot_frames > 0:
		var frame := mini(_face_state(), mugshot_frames - 1)
		var tex := mugshot_strip.get_size()
		var fw := tex.x / float(mugshot_frames)
		draw_texture_rect_region(mugshot_strip, inner, Rect2(fw * frame, 0.0, fw, tex.y))
		return

	_draw_face(inner, _face_state())


# Состояние лица по HP: 0 (100–81%) … 4 (≤25%), 5 — мёртвый.
func _face_state() -> int:
	if _current <= 0.0:
		return 5
	var f := 1.0
	if _maximum > 0.0:
		f = clampf(_current / _maximum, 0.0, 1.0)
	if f > 0.8:
		return 0
	if f > 0.6:
		return 1
	if f > 0.4:
		return 2
	if f > 0.25:
		return 3
	return 4


# Векторный плейсхолдер-лицо (фолбэк при mugshot_strip == null). Своё лицо на
# каждое состояние: сисадмин → раздражён → дёргается → брейнрот → мёртвый.
func _draw_face(area: Rect2, state: int) -> void:
	var c := area.get_center()
	var r := minf(area.size.x, area.size.y) * 0.42
	var skin := Color(0.85, 0.72, 0.58)
	var ink := Color(0.08, 0.06, 0.05)

	draw_circle(c, r, skin)
	if state <= 1:
		draw_arc(c, r * 1.02, PI + 0.3, TAU - 0.3, 24, Color(0.15, 0.15, 0.18), r * 0.14)
		draw_line(c + Vector2(-r * 0.95, 0.0), c + Vector2(-r * 0.55, r * 0.35),
				Color(0.15, 0.15, 0.18), r * 0.08)

	var eye_l := c + Vector2(-r * 0.4, -r * 0.12)
	var eye_r := c + Vector2(r * 0.4, -r * 0.12)
	var eye_rad := r * 0.2
	var mouth := c + Vector2(0.0, r * 0.45)

	match state:
		0:
			_brows(eye_l, eye_r, r, ink, 0.0)
			_dots(eye_l, eye_r, eye_rad * 0.5, ink)
			draw_line(mouth + Vector2(-r * 0.35, 0.0), mouth + Vector2(r * 0.35, 0.0), ink, r * 0.08)
		1:
			_brows(eye_l, eye_r, r, ink, -0.25)
			_dots(eye_l, eye_r, eye_rad * 0.5, ink)
			draw_line(mouth + Vector2(-r * 0.3, r * 0.05), mouth + Vector2(r * 0.3, -r * 0.05), ink, r * 0.08)
		2:
			_brows(eye_l, eye_r, r, ink, -0.5)
			_dots(eye_l, eye_r, eye_rad * 0.5, ink)
			_zigzag(mouth, r * 0.4, r * 0.12, ink)
		3:
			draw_arc(eye_l, eye_rad * 1.15, 0.0, TAU, 20, ink, r * 0.06)
			draw_circle(eye_l, eye_rad * 0.4, ink)
			draw_circle(eye_r, eye_rad * 0.35, ink)
			draw_line(mouth + Vector2(-r * 0.32, r * 0.08), mouth + Vector2(r * 0.32, -r * 0.12), ink, r * 0.08)
			draw_circle(c + Vector2(r * 0.62, -r * 0.35), r * 0.1, Color(0.5, 0.75, 0.95, 0.9))
		4:
			_spiral(eye_l, eye_rad * 1.3, 2.5, ink, r * 0.05)
			_spiral(eye_r, eye_rad * 1.3, 2.5, ink, r * 0.05)
			_wavy(mouth, r * 0.45, r * 0.1, ink)
			draw_circle(mouth + Vector2(0.0, r * 0.2), r * 0.12, Color(0.85, 0.35, 0.4))
		_:
			_cross(eye_l, eye_rad * 0.9, ink, r * 0.06)
			_cross(eye_r, eye_rad * 0.9, ink, r * 0.06)
			draw_line(mouth + Vector2(-r * 0.3, 0.0), mouth + Vector2(r * 0.3, 0.0), ink, r * 0.08)


func _brows(eye_l: Vector2, eye_r: Vector2, r: float, col: Color, tilt: float) -> void:
	var dy := r * 0.32
	var half := r * 0.24
	var lift := r * tilt
	draw_line(eye_l + Vector2(-half, -dy), eye_l + Vector2(half, -dy + lift), col, r * 0.07)
	draw_line(eye_r + Vector2(-half, -dy + lift), eye_r + Vector2(half, -dy), col, r * 0.07)


func _dots(a: Vector2, b: Vector2, rad: float, col: Color) -> void:
	draw_circle(a, rad, col)
	draw_circle(b, rad, col)


func _cross(center: Vector2, s: float, col: Color, w: float) -> void:
	draw_line(center + Vector2(-s, -s), center + Vector2(s, s), col, w)
	draw_line(center + Vector2(-s, s), center + Vector2(s, -s), col, w)


func _zigzag(center: Vector2, half_w: float, amp: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var n := 6
	for i in n + 1:
		var t := float(i) / n
		var x := center.x - half_w + half_w * 2.0 * t
		var y := center.y + (amp if i % 2 == 0 else -amp)
		pts.append(Vector2(x, y))
	draw_polyline(pts, col, half_w * 0.18, true)


func _wavy(center: Vector2, half_w: float, amp: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var n := 16
	for i in n + 1:
		var t := float(i) / n
		var x := center.x - half_w + half_w * 2.0 * t
		var y := center.y + sin(t * TAU) * amp
		pts.append(Vector2(x, y))
	draw_polyline(pts, col, half_w * 0.16, true)


func _spiral(center: Vector2, max_r: float, turns: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	var n := 40
	for i in n + 1:
		var t := float(i) / n
		var ang := t * turns * TAU
		pts.append(center + Vector2(cos(ang), sin(ang)) * (max_r * t))
	draw_polyline(pts, col, w, true)


# --------------------------------------------------------------------------
# Утилиты
# --------------------------------------------------------------------------

func _ammo_text() -> String:
	if not _active_uses_ammo:
		return "—"
	var pool: Vector2i = _pools.get(_active_type, Vector2i(-1, 0))
	return str(pool.x) if pool.x >= 0 else "∞"


func _hp_color() -> Color:
	var frac := 1.0
	if _maximum > 0.0:
		frac = clampf(_current / _maximum, 0.0, 1.0)
	return color_number_low if frac <= low_threshold else color_number


func _pool_label(type: StringName) -> String:
	return pool_labels.get(type, String(type).to_upper())


# Горизонтальный подпрямоугольник rect по долям [a, b] ширины.
func _hslice(rect: Rect2, a: float, b: float) -> Rect2:
	return Rect2(rect.position.x + rect.size.x * a, rect.position.y,
			rect.size.x * (b - a), rect.size.y)


# Ужать кегль подписи, чтобы влезла в max_w.
func _fit_fs(font: Font, text: String, base_fs: int, max_w: float) -> int:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, base_fs).x
	if w <= max_w or w <= 0.0:
		return base_fs
	return maxi(7, int(base_fs * max_w / w))


# Бевел-фаска: светлая грань верх-лево, тёмная низ-право. raised=false инвертирует.
func _bevel(rect: Rect2, raised: bool) -> void:
	var top_left := bevel_light if raised else bevel_dark
	var bottom_right := bevel_dark if raised else bevel_light
	var w := bevel_width
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, w)), top_left)
	draw_rect(Rect2(rect.position, Vector2(w, rect.size.y)), top_left)
	draw_rect(Rect2(Vector2(rect.position.x, rect.end.y - w), Vector2(rect.size.x, w)), bottom_right)
	draw_rect(Rect2(Vector2(rect.end.x - w, rect.position.y), Vector2(w, rect.size.y)), bottom_right)
