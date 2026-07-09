#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Генератор демо-карт кампании (level_E1_L2, E2_L1, E2_L2, E3_L1, E3_L2).

Раскладка: scenes/levels/episode_<N>/level_E<N>_L<уровень>.tscn — папка на
эпизод (snake_case), в имени файла эпизод+уровень продублированы для поиска.
Первый уровень кампании (E1_L1) — episode_1/level_E1_L1.tscn, его собирает
build_doom_kit.gd, не этот генератор.

Пишет .tscn в формате, идентичном level_E1_L1.tscn (эталон — сборщик
build_doom_kit.gd + ручные правки в редакторе): корень Node3D, свет/окружение,
GridMap-геометрия на doom_kit.tres, потолок CeilingGridMap (строится в рантайме),
слой Entities (EntitySpawner) с маркерами спавна/выхода/врагов/пикапов.

Кодировка клетки GridMap в "data/cells" (3 int32 на клетку, y всегда 0):
  int0 = x & 0xFFFF            (низкие 16 бит; y=0 в верхних)
  int1 = z & 0xFFFF
  int2 = item | (rot << 16)    (rot — ортогональный индекс поворота)

Повороты вокруг Y: 0 = 0°, 16 = -90° (вперёд +X), 10 = 180° (вперёд +Z),
22 = +90° (вперёд -X). Арка (door_arch, item 4): rot 0 — проход вдоль Z,
rot 22 — вдоль X. У маркера спавна rot задаёт, куда смотрит игрок.

Запуск: python3 tools/gen_demo_levels.py (из корня репозитория).
Идемпотентен: перезаписывает пять файлов уровней.
"""

import os

# --- id предметов кита (doom_kit.tres) ---
FLOOR, WALL, CEILING, PILLAR, ARCH = 0, 1, 2, 3, 4

# --- id маркеров слоя Entities (doom_entities.tres / EntitySpawner.SCENES) ---
SPAWN, EXIT = 0, 1
RUSHER, SHOOTER, FLYER = 2, 3, 4
AMMO, SHELLS = 5, 6
HP_BONUS, STIMPACK, MEDIKIT, SOULSPHERE = 7, 8, 9, 10
ARM_BONUS, ARM_GREEN, ARM_BLUE = 11, 12, 13
W_SHOTGUN, W_MACHINEGUN, W_ROCKET = 14, 15, 16

# Повороты вокруг Y (ортогональные индексы GridMap).
ROT_FWD_NZ = 0    # вперёд -Z (по умолчанию)
ROT_FWD_PZ = 10   # вперёд +Z
ROT_FWD_PX = 16   # вперёд +X
ROT_FWD_NX = 22   # вперёд -X (для арок: проход вдоль X)

# --- общие куски .tscn (эталон — level_E1_L1.tscn) ---
EXT_RESOURCES = """\
[ext_resource type="MeshLibrary" uid="uid://b3whaybjnchbg" path="res://scenes/levels/kit/doom_kit.tres" id="1_kit"]
[ext_resource type="Script" uid="uid://d2rybjsije4jf" path="res://scripts/levels/ceiling_gridmap.gd" id="2_ceil"]
[ext_resource type="MeshLibrary" uid="uid://bfwkve8ktv4w3" path="res://scenes/levels/kit/doom_entities.tres" id="3_ents"]
[ext_resource type="Script" uid="uid://cia4bxw40dhsg" path="res://scripts/levels/entity_spawner.gd" id="4_spawn"]
"""

ENVIRONMENT = """\
[sub_resource type="Environment" id="Environment_lvl"]
background_mode = 1
background_color = Color(0.05, 0.05, 0.07, 1)
ambient_light_source = 2
ambient_light_color = Color(0.55, 0.57, 0.62, 1)
ambient_light_energy = 0.7
"""

SUN_TRANSFORM = ("Transform3D(0.81915206, -0.46984634, 0.32898995, 0, 0.57357645, "
                 "0.81915206, -0.57357645, -0.6710101, 0.46984634, 0, 0, 0)")

# Подъём GridMap, чтобы верх пола встал на y≈0 (LIFT из build_doom_kit.gd).
GRID_TRANSFORM = "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.6, 0)"


def rect(x0, z0, x1, z1):
    """Прямоугольник клеток [x0..x1] × [z0..z1] включительно."""
    return {(x, z) for x in range(x0, x1 + 1) for z in range(z0, z1 + 1)}


def encode_cells(cells):
    """cells: iterable (x, z, item, rot) → строка PackedInt32Array."""
    ints = []
    for x, z, item, rot in sorted(cells):
        ints += [x & 0xFFFF, z & 0xFFFF, item | (rot << 16)]
    return ", ".join(str(i) for i in ints)


def build_geometry(floor_cells, arches, pillars):
    """Пол + арки + колонны + стены (8-соседи пола, не являющиеся полом)."""
    cells = []
    for (x, z) in floor_cells:
        if (x, z) in arches:
            cells.append((x, z, ARCH, arches[(x, z)]))
        elif (x, z) in pillars:
            cells.append((x, z, PILLAR, 0))
        else:
            cells.append((x, z, FLOOR, 0))
    walls = set()
    for (x, z) in floor_cells:
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                if dx == 0 and dz == 0:
                    continue
                n = (x + dx, z + dz)
                if n not in floor_cells:
                    walls.add(n)
    for (x, z) in walls:
        cells.append((x, z, WALL, 0))
    return cells


def render_level(name, uid, floor_cells, arches, pillars, entities):
    geometry = build_geometry(floor_cells, arches, pillars)
    ent_cells = [(x, z, i, r) for (x, z, i, r) in entities]
    return f"""[gd_scene format=3 uid="{uid}"]

{EXT_RESOURCES}
{ENVIRONMENT}
[node name="{name}" type="Node3D"]

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = {SUN_TRANSFORM}

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Environment_lvl")

[node name="Ceiling" type="GridMap" parent="."]
transform = {GRID_TRANSFORM}
visible = false
mesh_library = ExtResource("1_kit")
cell_size = Vector3(4, 4, 4)
cell_center_y = false
script = ExtResource("2_ceil")

[node name="GridMap" type="GridMap" parent="."]
transform = {GRID_TRANSFORM}
mesh_library = ExtResource("1_kit")
cell_size = Vector3(4, 4, 4)
cell_center_y = false
data = {{
"cells": PackedInt32Array({encode_cells(geometry)})
}}

[node name="Entities" type="GridMap" parent="."]
mesh_library = ExtResource("3_ents")
cell_size = Vector3(4, 4, 4)
cell_center_y = false
data = {{
"cells": PackedInt32Array({encode_cells(ent_cells)})
}}
script = ExtResource("4_spawn")
"""


# ==========================================================================
# Карты. entities: (x, z, id, rot). rot спавна = куда смотрит игрок.
# ==========================================================================

def level_02():
    """E1L2 «Петля»: комната → коридор на восток → зал с колоннами →
    коридор на юг → большой зал с выходом."""
    floor = (rect(0, 0, 4, 4) | rect(5, 2, 8, 2) | rect(9, 0, 13, 4)
             | rect(11, 5, 11, 8) | rect(7, 9, 14, 13))
    arches = {(5, 2): ROT_FWD_NX, (8, 2): ROT_FWD_NX,
              (11, 5): ROT_FWD_NZ, (11, 8): ROT_FWD_NZ}
    pillars = {(10, 2), (12, 2)}
    entities = [
        (1, 2, SPAWN, ROT_FWD_PX),
        (13, 12, EXIT, 0),
        # враги
        (3, 3, RUSHER, 0), (12, 1, SHOOTER, 0), (10, 4, RUSHER, 0),
        (8, 12, SHOOTER, 0), (13, 10, RUSHER, 0), (10, 11, FLYER, 0),
        # оружие и припасы
        (11, 2, W_SHOTGUN, 0), (13, 0, SHELLS, 0), (9, 0, AMMO, 0),
        (6, 2, STIMPACK, 0), (7, 13, MEDIKIT, 0), (14, 9, ARM_GREEN, 0),
        (11, 6, HP_BONUS, 0), (11, 7, HP_BONUS, 0),
    ]
    return "LevelE1L2", "uid://levele1l2gen", floor, arches, pillars, entities


def level_03():
    """E2L1 «Развилка»: хаб с двумя ветками (восточная и южная), обе сходятся
    в финальном зале с выходом."""
    floor = (rect(0, 0, 3, 3) | rect(2, 4, 2, 5) | rect(0, 6, 5, 9)
             | rect(6, 7, 8, 7) | rect(9, 5, 12, 9)
             | rect(2, 10, 2, 11) | rect(0, 12, 5, 15)
             | rect(10, 10, 10, 12) | rect(7, 13, 13, 16) | rect(6, 14, 6, 14))
    arches = {(2, 4): ROT_FWD_NZ, (6, 7): ROT_FWD_NX, (2, 10): ROT_FWD_NZ,
              (10, 10): ROT_FWD_NZ, (6, 14): ROT_FWD_NX}
    pillars = set()
    entities = [
        (1, 1, SPAWN, ROT_FWD_PZ),
        (12, 16, EXIT, 0),
        # хаб
        (4, 8, RUSHER, 0), (1, 7, RUSHER, 0),
        (2, 8, W_SHOTGUN, 0), (3, 8, SHELLS, 0), (0, 6, AMMO, 0),
        # восточная ветка
        (11, 6, SHOOTER, 0), (12, 8, SHOOTER, 0), (10, 7, RUSHER, 0),
        (12, 5, MEDIKIT, 0), (9, 5, ARM_GREEN, 0),
        # южная ветка
        (1, 13, RUSHER, 0), (4, 14, RUSHER, 0), (2, 13, FLYER, 0),
        (3, 13, W_MACHINEGUN, 0), (0, 15, SHELLS, 0), (5, 12, STIMPACK, 0),
        # финальный зал
        (8, 15, SHOOTER, 0), (12, 14, FLYER, 0), (9, 14, RUSHER, 0),
        (7, 16, MEDIKIT, 0), (10, 13, HP_BONUS, 0), (11, 13, HP_BONUS, 0),
    ]
    return "LevelE2L1", "uid://levele2l1gen", floor, arches, pillars, entities


def level_04():
    """E2L2 «Арена»: предбанник → большая арена с колоннами и ракетомётом →
    восточная комната выхода под охраной."""
    floor = (rect(0, 0, 2, 2) | rect(1, 3, 1, 4) | rect(0, 5, 10, 13)
             | rect(11, 9, 12, 9) | rect(13, 7, 15, 11))
    arches = {(1, 4): ROT_FWD_NZ, (11, 9): ROT_FWD_NX}
    pillars = {(2, 7), (8, 7), (2, 11), (8, 11)}
    entities = [
        (1, 0, SPAWN, ROT_FWD_PZ),
        (14, 9, EXIT, 0),
        # вход на арену
        (1, 3, HP_BONUS, 0), (1, 6, W_SHOTGUN, 0), (0, 6, SHELLS, 0),
        # арена
        (5, 9, W_ROCKET, 0), (9, 6, W_MACHINEGUN, 0), (0, 5, SOULSPHERE, 0),
        (4, 5, AMMO, 0), (6, 5, AMMO, 0), (5, 13, SHELLS, 0), (0, 7, ARM_BONUS, 0),
        (0, 13, SHOOTER, 0), (10, 13, SHOOTER, 0), (10, 5, SHOOTER, 0),
        (3, 9, RUSHER, 0), (7, 9, RUSHER, 0), (5, 12, RUSHER, 0),
        (5, 6, FLYER, 0), (9, 10, FLYER, 0),
        # комната выхода
        (14, 7, SHOOTER, 0), (14, 11, RUSHER, 0), (13, 11, MEDIKIT, 0),
    ]
    return "LevelE2L2", "uid://levele2l2gen", floor, arches, pillars, entities


def level_05():
    """E3L1 «Коридоры»: цепочка залов зигзагом, плотный дальний бой."""
    floor = (rect(0, 0, 3, 3) | rect(2, 4, 2, 4) | rect(0, 5, 5, 8)
             | rect(6, 6, 7, 6) | rect(8, 4, 11, 9)
             | rect(9, 10, 9, 11) | rect(6, 12, 12, 15)
             | rect(4, 13, 5, 13) | rect(0, 11, 3, 15))
    arches = {(2, 4): ROT_FWD_NZ, (6, 6): ROT_FWD_NX,
              (9, 10): ROT_FWD_NZ, (5, 13): ROT_FWD_NX}
    pillars = {(9, 6), (10, 7), (8, 13), (11, 14)}
    entities = [
        (1, 1, SPAWN, ROT_FWD_PZ),
        (1, 14, EXIT, 0),
        # зал B
        (1, 6, SHOOTER, 0), (4, 7, SHOOTER, 0), (3, 5, RUSHER, 0),
        (1, 5, W_SHOTGUN, 0), (0, 5, SHELLS, 0), (0, 8, MEDIKIT, 0),
        # зал C
        (9, 4, SHOOTER, 0), (11, 8, SHOOTER, 0), (8, 6, RUSHER, 0), (10, 5, FLYER, 0),
        (11, 9, W_MACHINEGUN, 0), (8, 4, AMMO, 0), (11, 4, AMMO, 0),
        # зал D
        (7, 14, SHOOTER, 0), (12, 13, SHOOTER, 0), (10, 13, RUSHER, 0), (11, 15, FLYER, 0),
        (6, 12, STIMPACK, 0), (12, 15, ARM_BLUE, 0), (12, 12, AMMO, 0),
        # зал E (выход)
        (2, 12, RUSHER, 0), (0, 15, SHOOTER, 0),
        (4, 13, HP_BONUS, 0), (2, 11, HP_BONUS, 0),
    ]
    return "LevelE3L1", "uid://levele3l1gen", floor, arches, pillars, entities


def level_06():
    """E3L2 «Ядро»: стартовая комната с арсеналом → гранд-арена с волнами →
    южная комната выхода."""
    floor = (rect(0, 0, 3, 3) | rect(2, 4, 2, 5) | rect(0, 6, 12, 16)
             | rect(6, 17, 6, 18) | rect(4, 19, 8, 21))
    arches = {(2, 4): ROT_FWD_NZ, (6, 17): ROT_FWD_NZ}
    pillars = {(3, 9), (9, 9), (3, 13), (9, 13)}
    entities = [
        (1, 1, SPAWN, ROT_FWD_PZ),
        (6, 20, EXIT, 0),
        # стартовая комната — арсенал на руки
        (1, 3, W_SHOTGUN, 0), (2, 3, SHELLS, 0), (3, 0, W_MACHINEGUN, 0),
        # арена: припасы
        (6, 11, W_ROCKET, 0), (6, 16, SOULSPHERE, 0), (0, 7, ARM_BLUE, 0),
        (12, 7, MEDIKIT, 0), (0, 15, MEDIKIT, 0),
        (5, 11, SHELLS, 0), (7, 11, SHELLS, 0), (4, 6, AMMO, 0), (8, 6, AMMO, 0),
        (2, 6, HP_BONUS, 0), (10, 6, HP_BONUS, 0),
        # арена: волны врагов
        (0, 6, SHOOTER, 0), (12, 6, SHOOTER, 0), (0, 16, SHOOTER, 0), (12, 16, SHOOTER, 0),
        (4, 11, RUSHER, 0), (8, 11, RUSHER, 0), (6, 14, RUSHER, 0),
        (2, 8, RUSHER, 0), (10, 8, RUSHER, 0),
        (6, 8, FLYER, 0), (3, 15, FLYER, 0), (9, 15, FLYER, 0),
        # комната выхода
        (4, 21, SHOOTER, 0), (8, 21, SHOOTER, 0), (6, 19, FLYER, 0), (4, 19, MEDIKIT, 0),
    ]
    return "LevelE3L2", "uid://levele3l2gen", floor, arches, pillars, entities


LEVELS = [level_02, level_03, level_04, level_05, level_06]


def main():
    out_dir = os.path.join(os.path.dirname(__file__), "..", "scenes", "levels")
    for make in LEVELS:
        name, uid, floor, arches, pillars, entities = make()
        # арки и колонны обязаны стоять на полу
        assert set(arches) <= floor, f"{name}: арка вне пола"
        assert pillars <= floor, f"{name}: колонна вне пола"
        for (x, z, _i, _r) in entities:
            assert (x, z) in floor, f"{name}: маркер вне пола: {(x, z)}"
        # node name "LevelE1L2" → эпизод 1 → папка episode_1, файл level_E1_L2.tscn.
        episode_num = name[6]                       # цифра эпизода из "LevelE1L2"
        fname = f"level_{name[5:7]}_{name[7:]}.tscn"
        ep_dir = os.path.join(out_dir, f"episode_{episode_num}")
        os.makedirs(ep_dir, exist_ok=True)
        path = os.path.join(ep_dir, fname)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(render_level(name, uid, floor, arches, pillars, entities))
        print(f"[gen] episode_{episode_num}/{fname}: пол {len(floor)}, маркеров {len(entities)}")


if __name__ == "__main__":
    main()
