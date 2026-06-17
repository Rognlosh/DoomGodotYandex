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
## Направленная ли: true — кадр по ракурсу (ходьба/атака);
## false — всегда столбец 0 «фронт» (смерть, как в DOOM — один ракурс).
@export var directional: bool = true
