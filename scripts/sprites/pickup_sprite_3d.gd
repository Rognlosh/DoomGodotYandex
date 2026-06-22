@tool
class_name PickupSprite3D
extends Sprite3D
## Визуал пикапа: спрайт-биллборд с процедурной силуэт-иконкой.
## Иконка генерится КОДОМ в ImageTexture (ноль веса билда) по форме (shape)
## и цвету (color) — приём как у DirectionalSprite3D/ImpactSmoke.
## Появится настоящий арт — снять auto_icon и назначить texture; генерация
## сама отключится. @tool: иконка видна и в редакторе (для расстановки),
## но в .tscn не сохраняется (стрипается перед записью — сцены чистые).

## Силуэт иконки. SHELL/ROCKET — задел под будущие патроны.
enum Shape { CLIP, SHELL, ROCKET, VIAL, MEDKIT, SPHERE, VEST, HELMET }

## Размер холста иконки в пикселях (квадрат). Маленький — это плейсхолдер.
const RES: int = 32

## Какую иконку рисовать.
@export var shape: Shape = Shape.MEDKIT:
	set(value):
		shape = value
		if is_node_ready() or Engine.is_editor_hint():
			_rebuild()
## Основной цвет силуэта (тинт). Контур/блики берутся от него автоматически.
@export var color: Color = Color(0.8, 0.8, 0.85):
	set(value):
		color = value
		if is_node_ready() or Engine.is_editor_hint():
			_rebuild()
## true — рисуем процедурную иконку. false — оставляем назначенный texture (арт).
@export var auto_icon: bool = true:
	set(value):
		auto_icon = value
		if is_node_ready() or Engine.is_editor_hint():
			_rebuild()

@export_group("Bob")
## Амплитуда покачивания по Y, м. 0 — выключить.
@export var bob_height: float = 0.08
## Скорость покачивания.
@export var bob_speed: float = 2.0

# Базовая высота для bob (запоминается в рантайме) и фаза.
var _base_y: float = 0.0
var _bob_t: float = 0.0


func _ready() -> void:
	_rebuild()
	if not Engine.is_editor_hint():
		_base_y = position.y
		# Случайная фаза, чтобы пикапы рядом не качались синхронно.
		_bob_t = randf() * TAU


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or bob_height <= 0.0:
		return
	_bob_t += delta * bob_speed
	position.y = _base_y + sin(_bob_t) * bob_height


func _notification(what: int) -> void:
	# В редакторе храним иконку только в памяти: убираем texture перед
	# сохранением сцены и возвращаем после — .tscn остаётся без встроенной картинки.
	if not Engine.is_editor_hint() or not auto_icon:
		return
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		texture = null
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_rebuild()


# Перестроить иконку (если включён auto_icon).
func _rebuild() -> void:
	if not auto_icon:
		return
	texture = _build_icon()


# --- Генерация иконки -------------------------------------------------------

func _build_icon() -> ImageTexture:
	var img: Image = Image.create_empty(RES, RES, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match shape:
		Shape.CLIP: _draw_clip(img)
		Shape.SHELL: _draw_shell(img)
		Shape.ROCKET: _draw_rocket(img)
		Shape.VIAL: _draw_vial(img)
		Shape.MEDKIT: _draw_medkit(img)
		Shape.SPHERE: _draw_sphere(img)
		Shape.VEST: _draw_vest(img)
		Shape.HELMET: _draw_helmet(img)
	_add_outline(img, color.darkened(0.6))
	return ImageTexture.create_from_image(img)


func _draw_clip(img: Image) -> void:
	var brass: Color = Color(0.95, 0.8, 0.4)
	var dark: Color = color.darkened(0.4)
	_rect(img, 12, 6, 3, 5, brass)   # носик пули
	_rect(img, 17, 6, 3, 5, brass)
	_rect(img, 11, 11, 10, 16, color)  # корпус магазина
	_rect(img, 11, 15, 10, 1, dark)    # рёбра
	_rect(img, 11, 19, 10, 1, dark)
	_rect(img, 11, 23, 10, 1, dark)


func _draw_shell(img: Image) -> void:
	_rect(img, 11, 18, 10, 8, Color(0.85, 0.7, 0.3))  # латунное донце
	_rect(img, 11, 8, 10, 10, color)                  # гильза


func _draw_rocket(img: Image) -> void:
	_disc(img, 16, 9, 3, Color(0.85, 0.2, 0.2))   # боеголовка
	_rect(img, 13, 9, 6, 14, color)               # корпус
	_rect(img, 10, 20, 3, 4, color.darkened(0.3)) # стабилизаторы
	_rect(img, 19, 20, 3, 4, color.darkened(0.3))


func _draw_vial(img: Image) -> void:
	_rect(img, 14, 7, 4, 3, Color(0.55, 0.4, 0.25))   # пробка
	_rect(img, 14, 9, 4, 4, color)                    # горлышко
	_disc(img, 16, 21, 6, color)                      # округлое дно
	_rect(img, 11, 15, 10, 7, color)                  # тело
	_rect(img, 13, 16, 1, 7, Color(0.95, 0.95, 0.95)) # блик


func _draw_medkit(img: Image) -> void:
	var white: Color = Color(0.95, 0.95, 0.95)
	_rect(img, 7, 8, 18, 18, color)    # коробка
	_rect(img, 14, 11, 4, 12, white)   # крест (вертикаль)
	_rect(img, 11, 15, 10, 4, white)   # крест (горизонталь)


func _draw_sphere(img: Image) -> void:
	_disc(img, 16, 16, 11, color)
	_disc(img, 13, 13, 4, color.lightened(0.5))      # подсветка
	_disc(img, 12, 12, 2, Color(1, 1, 1, 0.95))      # блик


func _draw_vest(img: Image) -> void:
	# Силуэт щита: плечи, корпус, заострённый низ.
	for y in range(8, 26):
		var hw: int
		if y < 18:
			hw = 7 if y < 10 else 8  # лёгкий скос плеч
		else:
			hw = max(0, 8 - (y - 17))
		if hw > 0:
			_rect(img, 16 - hw, y, hw * 2, 1, color)
	_rect(img, 15, 9, 2, 14, color.darkened(0.35))   # центральный шов
	_rect(img, 8, 16, 16, 1, color.lightened(0.25))  # поясок


func _draw_helmet(img: Image) -> void:
	var dark: Color = color.darkened(0.45)
	_disc(img, 16, 15, 9, color)                          # купол
	_rect(img, 0, 18, RES, RES - 18, Color(0, 0, 0, 0))   # срезать низ купола
	_rect(img, 6, 17, 20, 3, color)                       # козырёк
	_rect(img, 9, 12, 14, 4, dark)                        # визор


# --- Растровые примитивы ----------------------------------------------------

func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and x < RES and y >= 0 and y < RES:
		img.set_pixel(x, y, c)


func _rect(img: Image, x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			_px(img, x, y, c)


func _disc(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			var dx: int = x - cx
			var dy: int = y - cy
			if dx * dx + dy * dy <= r * r:
				_px(img, x, y, c)


# Обвести весь силуэт 1-пиксельным контуром (прозрачные пиксели у края → contour).
func _add_outline(img: Image, contour: Color) -> void:
	var edges: Array[Vector2i] = []
	for y in RES:
		for x in RES:
			if img.get_pixel(x, y).a > 0.0:
				continue
			if _touches_filled(img, x, y):
				edges.append(Vector2i(x, y))
	for e in edges:
		img.set_pixel(e.x, e.y, contour)


func _touches_filled(img: Image, x: int, y: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + d.x
		var ny: int = y + d.y
		if nx >= 0 and nx < RES and ny >= 0 and ny < RES:
			if img.get_pixel(nx, ny).a > 0.0:
				return true
	return false
