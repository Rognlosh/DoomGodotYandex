class_name SpriteAnimation
extends Resource
## Описание одной анимации в атласе (стиль ScriptableObject, как AmmoType).
## Атлас — единая сетка: столбцы = ракурсы (5 шт.), строки = кадры.
## Набор таких ресурсов лежит массивом в инспекторе DirectionalSprite3D.

## Имя для вызова из кода: play(&"walk"). &"..." — StringName.
@export var name: StringName = &""
## Со скольки строки атласа начинается (0 — самая верхняя).
@export var row_start: int = 0
## Сколько кадров (строк) занимает.
@export var frame_count: int = 1
## Скорость, кадров в секунду.
@export var fps: float = 8.0
## Зациклить (ходьба — да; атака/смерть — нет, замирают на последнем кадре).
@export var loop: bool = true
## Направленная ли: true — столбец = ракурс, кадры идут ВНИЗ по строкам
## (ходьба/атака); false — один ряд row_start, кадры идут ВПРАВО по столбцам
## (смерть — один ракурс, как в DOOM; не больше columns кадров в ряд).
@export var directional: bool = true
