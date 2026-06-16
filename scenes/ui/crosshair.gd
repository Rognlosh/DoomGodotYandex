extends Control
## Простой прицел: рисуется кодом (без текстуры — ноль веса для билда).
## Лежит в CanvasLayer, растянут на весь экран; крестик — по центру.

## Цвет линий прицела.
@export var color: Color = Color(1.0, 1.0, 1.0, 0.85)
## Длина каждого штриха, px.
@export var line_length: float = 8.0
## Зазор в центре (пустота вокруг точки прицеливания), px.
@export var gap: float = 4.0
## Толщина линий, px.
@export var thickness: float = 2.0


func _ready() -> void:
	# Прицел не должен перехватывать клики мыши.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Перерисовываемся при изменении размера окна.
	resized.connect(queue_redraw)


func _draw() -> void:
	var center: Vector2 = size * 0.5
	# Горизонтальные штрихи.
	draw_line(center + Vector2(gap, 0.0), center + Vector2(gap + line_length, 0.0), color, thickness)
	draw_line(center - Vector2(gap, 0.0), center - Vector2(gap + line_length, 0.0), color, thickness)
	# Вертикальные штрихи.
	draw_line(center + Vector2(0.0, gap), center + Vector2(0.0, gap + line_length), color, thickness)
	draw_line(center - Vector2(0.0, gap), center - Vector2(0.0, gap + line_length), color, thickness)
