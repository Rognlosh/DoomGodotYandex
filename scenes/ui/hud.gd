class_name Hud
extends Control
## Думовская нижняя статус-панель в стиле ретро-ОС. Всё «шасси» (бевел-фаски,
## боксы-ридауты, числа) рисуется кодом в _draw — ноль веса билда. Единственный
## дорогой по арту элемент — мугшот; пока его нет, рисуется векторный плейсхолдер-
## лицо на каждое состояние HP (арт подменит стрип-текстуру позже, как у оружия).
##
## Панель якорится по нижнему краю и накрывает нижние ~panel_height_ratio экрана —
## это и есть контракт с оружием (bottom_overhang = 0.10 в weapon.gd: руки «растут»
## из-за панели). Game Over живёт отдельно (оверлей роутера) — HUD о нём не знает.

@export_group("Панель")
## Высота панели в долях высоты вьюпорта. Контракт с оружием — панель накрывает
## нижний запас (bottom_overhang). ~0.12–0.14 достаточно.
@export_range(0.08, 0.30) var panel_height_ratio: float = 0.13
## Толщина бевел-фаски, px.
@export var bevel_width: float = 3.0
## Заливка панели.
@export var panel_fill: Color = Color(0.11, 0.11, 0.14)
## Заливка утопленных боксов-ридаутов.
@export var inset_fill: Color = Color(0.05, 0.05, 0.07)
## Светлая грань фаски (верх-лево).
@export var bevel_light: Color = Color(0.42, 0.42, 0.5)
## Тёмная грань фаски (низ-право).
@export var bevel_dark: Color = Color(0.02, 0.02, 0.03)

@export_group("Цвета показателей")
## Цвет числа/полоски HP при нормальном рассудке.
@export var color_ok: Color = Color(0.35, 0.85, 0.4)
## Цвет при низком HP.
@export var color_low: Color = Color(0.9, 0.25, 0.2)
## Доля HP, ниже которой показатель краснеет.
@export_range(0.0, 1.0) var low_threshold: float = 0.3
## Цвет числа брони (щит-адблок).
@export var color_armor: Color = Color(0.5, 0.72, 0.98)
## Цвет числа активных патронов.
@export var color_ammo: Color = Color(0.98, 0.82, 0.35)
## Цвет подписей боксов.
@export var color_label: Color = Color(0.62, 0.62, 0.72)
## Цвет неактивного пула в мини-строке.
@export var color_pool_dim: Color = Color(0.5, 0.5, 0.58)

@export_group("Подписи")
@export var label_hp: String = "РАССУДОК"
@export var label_armor: String = "АДБЛОК"
## Человекочитаемые имена пулов для мини-строки (id -> подпись).
@export var pool_labels: Dictionary = {
	&"bullets": "ПУЛИ",
	&"shells": "ДРОБЬ",
	&"rockets": "РАКЕТЫ",
}

@export_group("Мугшот")
## Горизонтальный стрип кадров-лиц (слева направо, по состояниям HP; последний —
## «мёртвый»). null — рисуется векторный плейсхолдер-лицо (арт ещё не назначен).
@export var mugshot_strip: Texture2D
## Кадров в стрипе (должно совпадать с числом состояний: 5 живых + мёртвый = 6).
@export var mugshot_frames: int = 6

# --- Состояние показателей (пушится извне через сеттеры) ---
var _current: float = 0.0
var _maximum: float = 1.0
var _armor_current: float = 0.0
var _armor_max: float = 0.0

# Активный пул: id + флаг «тратит ли патроны» (меле показывает «—»).
var _active_type: StringName = &""
var _active_uses_ammo: bool = true
# Все пулы: id -> Vector2i(current, maximum). Порядок вставки сохраняется
# (main пушит в порядке ammo_types) — по нему и рисуем мини-строку.
var _pools: Dictionary = {}


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


## Какой пул показывать крупно. uses_ammo=false (меле) → крупный счётчик = «—».
func set_active_ammo_type(type: StringName, uses_ammo: bool = true) -> void:
	_active_type = type
	_active_uses_ammo = uses_ammo
	queue_redraw()


## Обновить пул. Подключается к AmmoComponent.ammo_changed. Кэшируем ВСЕ пулы
## (не только активный) — мини-строка показывает весь боезапас.
func on_ammo_changed(type: StringName, current: int, maximum: int) -> void:
	_pools[type] = Vector2i(current, maximum)
	queue_redraw()


# --------------------------------------------------------------------------
# Отрисовка
# --------------------------------------------------------------------------

func _draw() -> void:
	var font := get_theme_default_font()
	var h := size.y * panel_height_ratio
	var panel := Rect2(0.0, size.y - h, size.x, h)

	# Корпус панели: заливка + приподнятая фаска.
	draw_rect(panel, panel_fill)
	_bevel(panel, true)

	var pad := h * 0.13
	var gap := h * 0.12

	# Мугшот — квадрат по высоте панели, по центру.
	var face_side := h - pad * 2.0
	var face_rect := Rect2(
			panel.position.x + (size.x - face_side) * 0.5,
			panel.position.y + pad, face_side, face_side)

	# Левая зона: РАССУДОК + АДБЛОК (стопкой). Правая: активные патроны + мини-строка.
	var left := Rect2(
			panel.position.x + pad, panel.position.y + pad,
			face_rect.position.x - gap - (panel.position.x + pad), face_side)
	var right := Rect2(
			face_rect.end.x + gap, panel.position.y + pad,
			panel.end.x - pad - (face_rect.end.x + gap), face_side)

	_draw_vitals(left, font)
	_draw_mugshot(face_rect)
	_draw_ammo(right, font)


# Левая зона: два ридаута стопкой — HP (с полоской) и броня.
func _draw_vitals(zone: Rect2, font: Font) -> void:
	if zone.size.x <= 0.0:
		return
	var row_gap := zone.size.y * 0.08
	var row_h := (zone.size.y - row_gap) * 0.5

	var hp_frac := 0.0
	if _maximum > 0.0:
		hp_frac = clampf(_current / _maximum, 0.0, 1.0)
	var hp_col := color_ok if hp_frac > low_threshold else color_low
	_readout(Rect2(zone.position, Vector2(zone.size.x, row_h)),
			label_hp, str(int(roundf(_current))), hp_col, font, hp_frac, hp_col)

	var arm_box := Rect2(
			Vector2(zone.position.x, zone.position.y + row_h + row_gap),
			Vector2(zone.size.x, row_h))
	_readout(arm_box, label_armor, str(int(roundf(_armor_current))),
			color_armor, font, -1.0, color_armor)


# Правая зона: крупный счётчик активного пула + мини-строка всех пулов.
func _draw_ammo(zone: Rect2, font: Font) -> void:
	if zone.size.x <= 0.0:
		return
	var row_gap := zone.size.y * 0.08
	var big_h := (zone.size.y - row_gap) * 0.62
	var mini_h := zone.size.y - big_h - row_gap

	# Крупный счётчик активного пула.
	var label := _pool_label(_active_type)
	var value := "—"
	if _active_uses_ammo:
		var pool: Vector2i = _pools.get(_active_type, Vector2i(-1, 0))
		value = str(pool.x) if pool.x >= 0 else "∞"
	_readout(Rect2(zone.position, Vector2(zone.size.x, big_h)),
			label, value, color_ammo, font, -1.0, color_ammo)

	# Мини-строка: все пулы в порядке вставки, активный — ярче.
	_draw_pool_line(Rect2(
			Vector2(zone.position.x, zone.position.y + big_h + row_gap),
			Vector2(zone.size.x, mini_h)), font)


# Мини-строка боезапаса: «ПУЛИ 100  ДРОБЬ 8  РАКЕТЫ 5», активный пул выделен.
func _draw_pool_line(box: Rect2, font: Font) -> void:
	draw_rect(box, inset_fill)
	_bevel(box, false)
	if _pools.is_empty():
		return
	var pad := box.size.y * 0.16
	var fs := maxi(9, int(box.size.y * 0.5))
	var y := box.position.y + box.size.y * 0.5 + fs * 0.35
	var x := box.position.x + pad
	var space := font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	for type: StringName in _pools:
		var pool: Vector2i = _pools[type]
		var text := "%s %d" % [_pool_label(type), pool.x]
		var col := color_ammo if type == _active_type else color_pool_dim
		draw_string(font, Vector2(x, y), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		x += font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + space * 2.0


# Утопленный бокс-ридаут: подпись слева-сверху + крупное число справа + опц. полоска.
func _readout(box: Rect2, label: String, value: String, value_color: Color,
		font: Font, bar_frac: float, bar_color: Color) -> void:
	draw_rect(box, inset_fill)
	_bevel(box, false)
	var pad := box.size.y * 0.14
	var label_fs := maxi(8, int(box.size.y * 0.24))
	var value_fs := maxi(10, int(box.size.y * 0.5))

	draw_string(font, box.position + Vector2(pad, pad + label_fs), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, label_fs, color_label)

	var vw := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, value_fs).x
	draw_string(font,
			Vector2(box.end.x - pad - vw, box.position.y + box.size.y * 0.62 + value_fs * 0.35),
			value, HORIZONTAL_ALIGNMENT_LEFT, -1, value_fs, value_color)

	if bar_frac >= 0.0:
		var bar_h := maxf(3.0, box.size.y * 0.1)
		var bg := Rect2(box.position.x + pad, box.end.y - pad - bar_h,
				box.size.x - pad * 2.0, bar_h)
		draw_rect(bg, Color(0.0, 0.0, 0.0, 0.5))
		draw_rect(Rect2(bg.position, Vector2(bg.size.x * clampf(bar_frac, 0.0, 1.0), bg.size.y)),
				bar_color)


func _pool_label(type: StringName) -> String:
	return pool_labels.get(type, String(type).to_upper())


# --------------------------------------------------------------------------
# Мугшот
# --------------------------------------------------------------------------

func _draw_mugshot(rect: Rect2) -> void:
	# Рамка мугшота — утопленная (лицо «в экране»).
	draw_rect(rect, Color(0.03, 0.03, 0.05))
	_bevel(rect, false)
	var inner := rect.grow(-bevel_width)

	# Есть арт — рисуем кадр по состоянию (как стрип оружия). Иначе — векторное лицо.
	if mugshot_strip != null and mugshot_frames > 0:
		var frame := mini(_face_state(), mugshot_frames - 1)
		var tex := mugshot_strip.get_size()
		var fw := tex.x / float(mugshot_frames)
		var src := Rect2(fw * frame, 0.0, fw, tex.y)
		draw_texture_rect_region(mugshot_strip, inner, src)
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


# Векторный плейсхолдер-лицо. На каждое состояние — своё лицо (не морфинг):
# суровый сисадмин → раздражён → дёргается → брейнрот-спираль → мёртвый мем.
func _draw_face(area: Rect2, state: int) -> void:
	var c := area.get_center()
	var r := minf(area.size.x, area.size.y) * 0.42
	var skin := Color(0.85, 0.72, 0.58)
	var ink := Color(0.08, 0.06, 0.05)

	# Голова.
	draw_circle(c, r, skin)
	# Гарнитура сисадмина (states 0–1) — band над головой + микрофон.
	if state <= 1:
		draw_arc(c, r * 1.02, PI + 0.3, TAU - 0.3, 24, Color(0.15, 0.15, 0.18), r * 0.14)
		draw_line(c + Vector2(-r * 0.95, 0.0), c + Vector2(-r * 0.55, r * 0.35),
				Color(0.15, 0.15, 0.18), r * 0.08)

	var eye_l := c + Vector2(-r * 0.4, -r * 0.12)
	var eye_r := c + Vector2(r * 0.4, -r * 0.12)
	var eye_rad := r * 0.2
	var mouth := c + Vector2(0.0, r * 0.45)

	match state:
		0:  # суровый сисадмин: прямые брови, ровный взгляд, прямой рот
			_brows(eye_l, eye_r, r, ink, 0.0)
			_dots(eye_l, eye_r, eye_rad * 0.5, ink)
			draw_line(mouth + Vector2(-r * 0.35, 0.0), mouth + Vector2(r * 0.35, 0.0), ink, r * 0.08)
		1:  # напряжён: брови чуть домиком, рот прямой
			_brows(eye_l, eye_r, r, ink, -0.25)
			_dots(eye_l, eye_r, eye_rad * 0.5, ink)
			draw_line(mouth + Vector2(-r * 0.3, r * 0.05), mouth + Vector2(r * 0.3, -r * 0.05), ink, r * 0.08)
		2:  # раздражён: нахмурен, рот-зигзаг (стиснут)
			_brows(eye_l, eye_r, r, ink, -0.5)
			_dots(eye_l, eye_r, eye_rad * 0.5, ink)
			_zigzag(mouth, r * 0.4, r * 0.12, ink)
		3:  # дёргается/кринж: глаза разного размера, кривой рот, капля пота
			draw_arc(eye_l, eye_rad * 1.15, 0.0, TAU, 20, ink, r * 0.06)
			draw_circle(eye_l, eye_rad * 0.4, ink)
			draw_circle(eye_r, eye_rad * 0.35, ink)
			draw_line(mouth + Vector2(-r * 0.32, r * 0.08), mouth + Vector2(r * 0.32, -r * 0.12), ink, r * 0.08)
			draw_circle(c + Vector2(r * 0.62, -r * 0.35), r * 0.1, Color(0.5, 0.75, 0.95, 0.9))
		4:  # брейнрот: глаза-спирали, волнистый рот, язык
			_spiral(eye_l, eye_rad * 1.3, 2.5, ink, r * 0.05)
			_spiral(eye_r, eye_rad * 1.3, 2.5, ink, r * 0.05)
			_wavy(mouth, r * 0.45, r * 0.1, ink)
			draw_circle(mouth + Vector2(0.0, r * 0.2), r * 0.12, Color(0.85, 0.35, 0.4))
		_:  # мёртвый мем: глаза-крестики, прямой рот
			_cross(eye_l, eye_rad * 0.9, ink, r * 0.06)
			_cross(eye_r, eye_rad * 0.9, ink, r * 0.06)
			draw_line(mouth + Vector2(-r * 0.3, 0.0), mouth + Vector2(r * 0.3, 0.0), ink, r * 0.08)


# Пара бровей. tilt < 0 — «домиком» (внутренние концы выше), > 0 — злые.
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
# Бевел-фаска (ретро-ОС): светлая грань верх-лево, тёмная низ-право.
# raised=true — приподнятый бокс; false — утопленный (грани меняются местами).
# --------------------------------------------------------------------------
func _bevel(rect: Rect2, raised: bool) -> void:
	var top_left := bevel_light if raised else bevel_dark
	var bottom_right := bevel_dark if raised else bevel_light
	var w := bevel_width
	# Верх + лево.
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, w)), top_left)
	draw_rect(Rect2(rect.position, Vector2(w, rect.size.y)), top_left)
	# Низ + право.
	draw_rect(Rect2(Vector2(rect.position.x, rect.end.y - w), Vector2(rect.size.x, w)), bottom_right)
	draw_rect(Rect2(Vector2(rect.end.x - w, rect.position.y), Vector2(w, rect.size.y)), bottom_right)
