#!/usr/bin/env python3
"""Пакер мугшота: N одноразмерных кадров-лиц -> горизонтальный стрип (для hud.gd).

По умолчанию кадры уже с прозрачным фоном — просто тайлятся в стрип, существующая
альфа сохраняется. Если фон — ровная хрома (напр. магента от ChatGPT), передай
`--chroma R,G,B`: тогда цвет вырезается flood-fill'ом ОТ ГРАНИЦ (внутренние пятна
того же цвета внутри лица не трогаются).

БЕЗ ресайза — кадры уже в нативном пиксель-гриде (ресайз замылил бы пиксель-арт).
Hard alpha (резкий край) + палитровая квантизация — под вес билда.

Кадры подаются в порядке состояний HP (0 — полное здоровье … последний — мёртвый),
он же порядок в стрипе; hud.gd выбирает столбец по HP (mugshot_frames = число кадров).

Использование:
    python3 tools/pack_mugshot_strip.py <выход>.png <кадр0> ... <кадрN> \
        [--chroma R,G,B] [--tol N]
"""
import sys
import numpy as np
from PIL import Image


def load_rgba(path, chroma, tol):
    """RGBA-массив кадра. chroma=None — берём альфу как есть; иначе кейим хрому."""
    a = np.array(Image.open(path).convert("RGBA"))
    if chroma is None:
        return a
    from scipy import ndimage  # нужен только в режиме кейинга
    rgb = a[:, :, :3].astype(int)
    close = np.abs(rgb - np.array(chroma)).max(2) <= tol
    lbl, _ = ndimage.label(close)
    border = (set(lbl[0].tolist()) | set(lbl[-1].tolist())
              | set(lbl[:, 0].tolist()) | set(lbl[:, -1].tolist()))
    border.discard(0)
    bg = np.isin(lbl, list(border))
    a[:, :, 3] = np.where(bg, 0, a[:, :, 3]).astype(np.uint8)
    return a


def main(out_path, frame_paths, chroma, tol):
    arrs = [load_rgba(p, chroma, tol) for p in frame_paths]
    h, w = arrs[0].shape[:2]
    for k in arrs:
        if k.shape[:2] != (h, w):
            raise SystemExit("кадры разного размера — мугшот ждёт одинаковые")

    strip = np.zeros((h, w * len(arrs), 4), np.uint8)
    for i, k in enumerate(arrs):
        strip[:, i * w:(i + 1) * w] = k

    # Hard alpha (резкий край) + палитра (вес билда).
    strip[:, :, 3] = np.where(strip[:, :, 3] >= 128, 255, 0).astype(np.uint8)
    out = Image.fromarray(strip, "RGBA").quantize(
        colors=64, method=Image.FASTOCTREE, dither=Image.NONE)
    out.save(out_path, optimize=True)
    print("saved:", out_path, (w * len(arrs), h), "кадров:", len(arrs))


if __name__ == "__main__":
    chroma = None
    tol = 40
    positional = []
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--chroma":
            chroma = tuple(int(x) for x in args[i + 1].split(","))
            i += 2
        elif args[i] == "--tol":
            tol = int(args[i + 1])
            i += 2
        else:
            positional.append(args[i])
            i += 1
    if len(positional) < 2:
        raise SystemExit(__doc__)
    main(positional[0], positional[1:], chroma, tol)
