#!/usr/bin/env python3
"""Пакер оружейного спрайта (ChatGPT-лист 2x2 -> горизонтальный стрип 4 кадров).

Использование:
    python3 tools/pack_weapon_strip.py <лист 2x2>.png <выход>.png
    python3 tools/pack_weapon_strip.py --single <кадр>.png <выход>.png [высота=128]
    python3 tools/pack_weapon_strip.py --frames <выход>.png <кадр1>.png <кадр2>.png [...]

Вход: один квадратный лист на белом фоне, сетка 2x2:
    TL = покой (idle) | TR = начало выстрела
    BL = пик выстрела | BR = возврат
Выход: стрип 4 кадров по горизонтали (idle, fire1, fire2, fire3),
клетка 160x128 -> 640x128 RGBA(индекс.), под weapon.gd (sprite_frames = 4).

Приёмы — те же, что в pack_sprite_sheet.py:
- фон убирается flood-fill'ом от границ (светлое, связное с краем = фон);
- ЕДИНЫЙ масштаб на все кадры (нет «пульсации» размера);
- кадры прижаты к НИЗУ клетки по центру (руки «растут» из-за нижнего края
  экрана; запас снизу добирается в weapon.gd параметром bottom_overhang);
- hard alpha (под резкий край), палитровая квантизация (вес билда).
"""
import sys
import numpy as np
from PIL import Image

from pack_sprite_sheet import foreground_mask  # тот же keying, не дублируем

COLS = 4                # кадров в выходном стрипе
CW, CH = 160, 128       # клетка стрипа
MARGIN_X, MARGIN_TOP = 4, 4


def quadrants(img):
    """Режем лист пополам по обеим осям: TL, TR, BL, BR (порядок кадров)."""
    w, h = img.size
    boxes = [(0, 0, w // 2, h // 2), (w // 2, 0, w, h // 2),
             (0, h // 2, w // 2, h), (w // 2, h // 2, w, h)]
    return [img.crop(b) for b in boxes]


def key_and_crop(quad):
    """Убрать белый фон, обрезать по контенту. Возвращает RGBA-спрайт."""
    a = np.array(quad.convert("RGBA"))
    fg = foreground_mask(a[:, :, :3].astype(int))
    if not fg.any():
        raise SystemExit("пустой квадрант — лист не похож на сетку 2x2")
    out = a.copy()
    out[:, :, 3] = np.where(fg, 255, 0).astype(np.uint8)
    ys, xs = np.where(fg)
    return Image.fromarray(out[ys.min():ys.max() + 1, xs.min():xs.max() + 1], "RGBA")


def finalize(img, out_path):
    """Hard alpha (под резкий край) + палитровая квантизация (вес билда)."""
    arr = np.array(img)
    arr[:, :, 3] = np.where(arr[:, :, 3] >= 128, 255, 0).astype(np.uint8)
    out = Image.fromarray(arr, "RGBA").quantize(
        colors=48, method=Image.FASTOCTREE, dither=Image.NONE)
    out.save(out_path, optimize=True)
    print("saved:", out_path, img.size)


def pack_single(in_path, out_path, height=128):
    """Одиночный кадр (ближний бой): кейинг фона + обрезка + вписывание по высоте.
    Выход — «стрип из 1 кадра», в weapon.gd назначается со sprite_frames = 1."""
    spr = key_and_crop(Image.open(in_path))
    scale = height / spr.height
    finalize(spr.resize((max(1, round(spr.width * scale)), height), Image.LANCZOS),
             out_path)


def pack_frames(out_path, frame_paths, height=128):
    """Стрип из ОТДЕЛЬНЫХ кадров-файлов (idle + вспышки стволов): кейинг каждого,
    единый масштаб, прижим к низу по центру. Ширина клетки — по самому широкому.
    В weapon.gd назначается со sprite_frames = <число файлов>."""
    sprites = [key_and_crop(Image.open(p)) for p in frame_paths]
    scale = (height - MARGIN_TOP) / max(s.height for s in sprites)
    cw = max(round(s.width * scale) for s in sprites) + 2 * MARGIN_X
    strip = Image.new("RGBA", (cw * len(sprites), height), (0, 0, 0, 0))
    for i, spr in enumerate(sprites):
        w = max(1, round(spr.width * scale))
        h = max(1, round(spr.height * scale))
        spr = spr.resize((w, h), Image.LANCZOS)
        strip.alpha_composite(spr, (i * cw + (cw - w) // 2, height - h))
    print(f"кадров={len(sprites)}, клетка={cw}x{height}, авто-масштаб={scale:.3f}")
    finalize(strip, out_path)


def main(sheet_path, out_path):
    sprites = [key_and_crop(q) for q in quadrants(Image.open(sheet_path))]
    # Единый масштаб: самый широкий/высокий кадр вписывается в клетку.
    scale = min((CW - 2 * MARGIN_X) / max(s.width for s in sprites),
                (CH - MARGIN_TOP) / max(s.height for s in sprites))
    print(f"авто-масштаб={scale:.3f}")

    strip = Image.new("RGBA", (COLS * CW, CH), (0, 0, 0, 0))
    for i, spr in enumerate(sprites):
        w = max(1, round(spr.width * scale))
        h = max(1, round(spr.height * scale))
        spr = spr.resize((w, h), Image.LANCZOS)
        # Центр по горизонтали, прижим к низу клетки (руки уходят за край экрана).
        strip.alpha_composite(spr, (i * CW + (CW - w) // 2, CH - h))

    finalize(strip, out_path)


if __name__ == "__main__":
    if sys.argv[1] == "--single":
        pack_single(sys.argv[2], sys.argv[3],
                    int(sys.argv[4]) if len(sys.argv) > 4 else 128)
    elif sys.argv[1] == "--frames":
        pack_frames(sys.argv[2], sys.argv[3:])
    else:
        main(sys.argv[1], sys.argv[2])
