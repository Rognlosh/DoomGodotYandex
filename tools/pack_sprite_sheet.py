#!/usr/bin/env python3
"""Пакер спрайт-листа врага (ChatGPT-разворот -> игровой атлас 5x8, клетка 80x64).

Вход: единая картинка-лист, 8 строк, слева-направо 5 ракурсов
(front/front34/side/back34/back); нижняя строка — death (4 фронт-кадра).
Порядок строк во ВХОДЕ: walk0..3, attack0..1, pain, death.

Выход: 400x512 RGBA, раскладка под DirectionalSprite3D:
  0-3 walk (направл.) | 4-5 attack (направл.) | 6 death (фронт, 1 ряд) | 7 pain (направл.)

Что делает:
- режет лист по connected-components (сетка ChatGPT неровная — фикс-грид не годится);
- убирает фон flood-fill'ом от границ (белое брюхо внутри тёмного контура остаётся);
- единый масштаб на ВСЕ кадры (нет «пульсации» размера), ступни на общей базовой линии;
- центрирует по горизонтали, кладёт в клетку, хардит альфу под Alpha Cut = Discard.
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

COLS, ROWS = 5, 8
CW, CH = 80, 64            # клетка
BASELINE = 61             # y нижней точки контента внутри клетки (ступни)
SCALE = 0.292             # глобальный масштаб (walk-кадр ~54 px, attack-замах вписывается)
MIN_BLOB = 400

def foreground_mask(rgb):
    """True = персонаж. Фон = светлый, связный с границей; брюхо внутри контура — не фон."""
    bright = rgb.mean(2); sat = rgb.max(2) - rgb.min(2)
    bg_cand = (bright > 180) & (sat < 35)          # светлый малонасыщенный = кандидат в фон/тень
    lbl, n = ndimage.label(bg_cand)
    border = set(lbl[0].tolist()) | set(lbl[-1].tolist()) | set(lbl[:,0].tolist()) | set(lbl[:,-1].tolist())
    border.discard(0)
    bg = np.isin(lbl, list(border))
    fg = ~bg
    # выкинуть мелкий мусор
    fl, fn = ndimage.label(fg)
    if fn:
        sizes = ndimage.sum(np.ones_like(fl), fl, range(1, fn+1))
        keep = {i+1 for i, s in enumerate(sizes) if s >= 30}
        fg = np.isin(fl, list(keep))
    return fg

def extract_sprites(sheet):
    a = np.array(sheet); rgb = a[:,:,:3].astype(int); al = a[:,:,3]
    bright = rgb.mean(2); sat = rgb.max(2)-rgb.min(2)
    content = ((bright < 205) | (sat > 55)) & (al > 20)
    lbl, n = ndimage.label(ndimage.binary_dilation(content, iterations=2))
    boxes = []
    for i in range(1, n+1):
        ys, xs = np.where(lbl == i)
        if len(xs) < MIN_BLOB: continue
        boxes.append((xs.min(), ys.min(), xs.max(), ys.max()))
    boxes.sort(key=lambda b: (b[1]+b[3])/2)
    rows, cur, last = [], [], None
    for b in boxes:
        yc = (b[1]+b[3])/2
        if last is None or abs(yc-last) < 70: cur.append(b)
        else: rows.append(cur); cur = [b]
        last = yc
    rows.append(cur)
    for r in rows: r.sort(key=lambda b: b[0])
    return a, rows

def crop_keyed(a, box, pad=4):
    x0,y0,x1,y1 = box
    x0=max(0,x0-pad); y0=max(0,y0-pad); x1+=pad; y1+=pad
    sub = a[y0:y1, x0:x1].copy()
    fg = foreground_mask(sub[:,:,:3].astype(int))
    out = sub.copy(); out[:,:,3] = np.where(fg, 255, 0).astype(np.uint8)
    ys, xs = np.where(fg)
    out = out[ys.min():ys.max()+1, xs.min():xs.max()+1]   # тесная обрезка по контенту
    return Image.fromarray(out, "RGBA")

def place(cell_img, spr):
    w = max(1, round(spr.width * SCALE)); h = max(1, round(spr.height * SCALE))
    spr = spr.resize((w, h), Image.LANCZOS)
    px = (CW - w) // 2                 # центр по горизонтали
    py = BASELINE - h                  # ступни на базовой линии
    cell_img.alpha_composite(spr, (px, py))

def main(sheet_path, out_path):
    a, rows = extract_sprites(Image.open(sheet_path).convert("RGBA"))
    counts = [len(r) for r in rows]
    assert counts == [5,5,5,5,5,5,5,4], f"ожидал 5x7+4, получил {counts}"
    atlas = Image.new("RGBA", (COLS*CW, ROWS*CH), (0,0,0,0))

    # вход row 0..3 walk -> атлас 0..3; 4..5 attack -> 4..5 (все направленные, 5 колонок)
    for out_r, in_r in [(0,0),(1,1),(2,2),(3,3),(4,4),(5,5)]:
        for c, box in enumerate(rows[in_r]):
            cell = Image.new("RGBA", (CW, CH), (0,0,0,0))
            place(cell, crop_keyed(a, box)); atlas.alpha_composite(cell, (c*CW, out_r*CH))

    # вход row 6 pain -> атлас row 7 (направленная, 5 колонок)
    for c, box in enumerate(rows[6]):
        cell = Image.new("RGBA", (CW, CH), (0,0,0,0))
        place(cell, crop_keyed(a, box)); atlas.alpha_composite(cell, (c*CW, 7*CH))

    # вход row 7 death -> атлас row 6, столбцы 0..3 (фронт, один ряд)
    for c, box in enumerate(rows[7]):
        cell = Image.new("RGBA", (CW, CH), (0,0,0,0))
        place(cell, crop_keyed(a, box)); atlas.alpha_composite(cell, (c*CW, 6*CH))

    # хардим альфу под Alpha Cut = Discard
    arr = np.array(atlas); arr[:,:,3] = np.where(arr[:,:,3] >= 128, 255, 0).astype(np.uint8)
    hard = Image.fromarray(arr, "RGBA")
    # индексируем палитру (48 цветов) — вес билда; альфа остаётся бинарной
    out = hard.quantize(colors=48, method=Image.FASTOCTREE, dither=Image.NONE)
    out.save(out_path, optimize=True)
    print("saved:", out_path, atlas.size)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
