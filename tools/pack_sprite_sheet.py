#!/usr/bin/env python3
"""Пакер спрайт-листа врага (ChatGPT-разворот -> игровой атлас 5x8, клетка 80x64).

Использование:
    python3 tools/pack_sprite_sheet.py <лист>.png <выход>.png [align]
    align = ground (по умолчанию) | fly

Вход: единая картинка-лист, 8 строк, слева-направо 5 ракурсов
(front/front34/side/back34/back); нижняя строка — death (4 фронт-кадра).
Порядок строк во входе: walk0..3, attack0..1, pain, death.

Выход: 400x512 RGBA(индекс.), раскладка под DirectionalSprite3D:
  0-3 walk (направл.) | 4-5 attack (направл.) | 6 death (фронт, 1 ряд) | 7 pain (направл.)

Ключевые приёмы:
- режет лист по connected-components (сетка ChatGPT неровная — фикс-грид не годится);
- фон убирается flood-fill'ом от границ: светлое, связное с краем = фон; белое тело/брюхо
  внутри тёмного контура НЕ трогается;
- ЕДИНЫЙ авто-масштаб на все кадры (нет «пульсации» размера): вписывает самый широкий
  и самый высокий кадр в клетку с полями, берётся меньший коэффициент;
- выравнивание: ground = ступни на базовой линии; fly = центр по вертикали.
  Death-ряд ВСЕГДА по нижней линии (гибнут на землю) независимо от align;
- альфа хардится под Alpha Cut = Discard, палитра индексируется (вес билда).
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

COLS, ROWS = 5, 8
CW, CH = 80, 64
MARGIN_X, MARGIN_Y = 3, 3          # поля внутри клетки при авто-вписывании
BASELINE = 61                      # y нижней точки контента для ground / death
MIN_BLOB = 400

def foreground_mask(rgb):
    """True = персонаж. Фон = светлый, связный с границей; светлое внутри контура — не фон."""
    bright = rgb.mean(2); sat = rgb.max(2) - rgb.min(2)
    bg_cand = (bright > 180) & (sat < 35)
    lbl, n = ndimage.label(bg_cand)
    border = set(lbl[0].tolist()) | set(lbl[-1].tolist()) | set(lbl[:,0].tolist()) | set(lbl[:,-1].tolist())
    border.discard(0)
    bg = np.isin(lbl, list(border))
    fg = ~bg
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
    out = out[ys.min():ys.max()+1, xs.min():xs.max()+1]
    return Image.fromarray(out, "RGBA")

def auto_scale(sprites):
    max_w = max(s.width for s in sprites); max_h = max(s.height for s in sprites)
    return min((CW - 2*MARGIN_X) / max_w, (CH - 2*MARGIN_Y) / max_h)

def place(cell_img, spr, scale, mode):
    w = max(1, round(spr.width * scale)); h = max(1, round(spr.height * scale))
    spr = spr.resize((w, h), Image.LANCZOS)
    px = (CW - w) // 2                          # центр по горизонтали всегда
    py = (BASELINE - h) if mode in ("ground", "death") else (CH - h)//2
    cell_img.alpha_composite(spr, (px, py))

def main(sheet_path, out_path, align="ground"):
    alive = "fly" if align == "fly" else "ground"
    a, rows = extract_sprites(Image.open(sheet_path).convert("RGBA"))
    counts = [len(r) for r in rows]
    assert counts == [5,5,5,5,5,5,5,4], f"ожидал 5x7+4, получил {counts}"

    # все спрайты один раз (для общего масштаба)
    keyed = {(r,c): crop_keyed(a, rows[r][c]) for r in range(8) for c in range(len(rows[r]))}
    scale = auto_scale(list(keyed.values()))
    print(f"align={alive}, авто-масштаб={scale:.3f}")

    atlas = Image.new("RGBA", (COLS*CW, ROWS*CH), (0,0,0,0))
    def blit(r_in, r_out, mode, cols):
        for c in cols:
            cell = Image.new("RGBA", (CW, CH), (0,0,0,0))
            place(cell, keyed[(r_in,c)], scale, mode)
            atlas.alpha_composite(cell, (c*CW, r_out*CH))

    for rr in [0,1,2,3,4,5]:            # walk+attack -> те же строки, направленные
        blit(rr, rr, alive, range(5))
    blit(6, 7, alive, range(5))         # вход pain -> строка 7
    blit(7, 6, "death", range(4))       # вход death -> строка 6, столбцы 0-3, по низу

    arr = np.array(atlas); arr[:,:,3] = np.where(arr[:,:,3] >= 128, 255, 0).astype(np.uint8)
    hard = Image.fromarray(arr, "RGBA")
    out = hard.quantize(colors=48, method=Image.FASTOCTREE, dither=Image.NONE)
    out.save(out_path, optimize=True)
    print("saved:", out_path, atlas.size)

if __name__ == "__main__":
    align = sys.argv[3] if len(sys.argv) > 3 else "ground"
    main(sys.argv[1], sys.argv[2], align)
