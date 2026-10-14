# Rasteriza faces planas (com furos) usando z-buffer, para os "prints" do SketchUp simulado.
# Entrada (JSON): {"w":, "h":, "scale":, "bg":[r,g,b], "faces":[{"loops":[[[x,y,z],...],...], "rgb":[r,g,b]}]}
# x,y em pixels (já projetados), z = profundidade (maior = mais longe). Saída: PNG com contornos.
# Uso: python3 dev/zbuf.py entrada.json saida.png
import json, sys
import numpy as np
from PIL import Image, ImageDraw

def main(src, dst):
    d = json.load(open(src))
    s = d.get('scale', 2)
    W, H = int(d['w'] * s), int(d['h'] * s)
    zbuf = np.full((H, W), np.inf)
    ids = np.full((H, W), -1, dtype=np.int32)
    faces = d['faces']
    for i, f in enumerate(faces):
        loops = [[(p[0] * s, p[1] * s, p[2]) for p in lp] for lp in f['loops']]
        outer = loops[0]
        xs = [p[0] for p in outer]; ys = [p[1] for p in outer]
        x0, x1 = max(int(min(xs)) - 1, 0), min(int(max(xs)) + 2, W)
        y0, y1 = max(int(min(ys)) - 1, 0), min(int(max(ys)) + 2, H)
        if x1 <= x0 or y1 <= y0:
            continue
        # profundidade como plano z = a x + b y + c (projeção ortográfica)
        P = np.array(outer)
        A = np.c_[P[:, 0], P[:, 1], np.ones(len(P))]
        try:
            (a, b, c), *_ = np.linalg.lstsq(A, P[:, 2], rcond=None)
        except np.linalg.LinAlgError:
            continue
        mask = Image.new('L', (x1 - x0, y1 - y0), 0)
        dr = ImageDraw.Draw(mask)
        dr.polygon([(p[0] - x0, p[1] - y0) for p in outer], fill=1, outline=1)
        for hole in loops[1:]:
            dr.polygon([(p[0] - x0, p[1] - y0) for p in hole], fill=0)
        m = np.array(mask, dtype=bool)
        if not m.any():
            continue
        yy, xx = np.mgrid[y0:y1, x0:x1]
        z = a * (xx + 0.5) + b * (yy + 0.5) + c - 1e-4 * f.get('bias', 0)
        sub = zbuf[y0:y1, x0:x1]
        win = m & (z < sub)
        sub[win] = z[win]
        ids[y0:y1, x0:x1][win] = i
    bg = np.array(d.get('bg', [245, 241, 238]), dtype=np.uint8)
    pal = np.array([f['rgb'] for f in faces] + [list(bg)], dtype=np.uint8)
    img = pal[ids]  # -1 vira o fundo (último)
    # contorno onde muda a face (como as arestas do SketchUp)
    edge = np.zeros((H, W), dtype=bool)
    edge[:, 1:] |= ids[:, 1:] != ids[:, :-1]
    edge[1:, :] |= ids[1:, :] != ids[:-1, :]
    ink = np.array(d.get('ink', [62, 75, 87]), dtype=np.float32)
    out = img.astype(np.float32)
    out[edge] = out[edge] * 0.35 + ink * 0.65
    im = Image.fromarray(out.clip(0, 255).astype(np.uint8))
    im = im.resize((d['w'] * 2, d['h'] * 2), Image.LANCZOS) if s != 2 else im
    im.save(dst)

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
