import sys, numpy as np
from PIL import Image
ramp = ".,:-=+*#%@"
for p in sys.argv[1:]:
    im = np.asarray(Image.open(p).convert("RGB")).astype(float)
    h, w, _ = im.shape
    corners = np.concatenate([im[:8,:8].reshape(-1,3), im[:8,-8:].reshape(-1,3), im[-8:,:8].reshape(-1,3), im[-8:,-8:].reshape(-1,3)])
    bg = np.median(corners, axis=0)
    diff = np.abs(im - bg).sum(axis=2)
    mask = diff > 45
    cov = mask.mean() * 100
    ys, xs = np.nonzero(mask)
    bbox = (xs.min(), ys.min(), xs.max(), ys.max()) if len(xs) else None
    q = (im[mask] // 32).astype(int)
    ncol = len({tuple(c) for c in q[::7]}) if len(q) else 0
    g = im.mean(axis=2)
    gx = np.abs(np.diff(g, axis=1))[:-1, :]; gy = np.abs(np.diff(g, axis=0))[:, :-1]
    strong = (gx + gy) > 40
    ang = np.degrees(np.arctan2(gy[strong], gx[strong] + 1e-6))
    axis = ((ang < 8) | (ang > 82)).mean() if strong.sum() else 0
    print(f"== {p.split(chr(92))[-1]}  cover {cov:.1f}%  bbox {bbox}  colors {ncol}  axis-aligned-edge {axis:.2f}  bg {bg.astype(int)}")
    cw, ch = 64, 28
    for r in range(ch):
        row = ""
        for c in range(cw):
            blk = im[r*h//ch:(r+1)*h//ch, c*w//cw:(c+1)*w//cw]
            m = mask[r*h//ch:(r+1)*h//ch, c*w//cw:(c+1)*w//cw]
            if m.mean() < 0.3: row += " "; continue
            lum = blk[m].mean(axis=0).mean() / 255
            row += ramp[min(9, int(lum * 9.99))]
        print("|" + row + "|")